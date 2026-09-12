// Phase 8 Variation Generator (spec section 2, 6-16, 20-23, 26-29, 32, 35).
// Produces Character *Recipes* only: asset references + body scale + palette. No GLB is loaded,
// composed or baked here, which is what keeps a 100-character batch cheap (spec section 35).
//
// Determinism: every draw comes from streamRng(seed, presetId, index, salt, field). Re-running with
// the same preset + seed over the same Asset Library yields the same batch; rerolling one character
// bumps only that character's salt, so its neighbours are untouched (spec section 20-21, 26).
import type { BodyPreset, BodyType, PaletteSlot, WeaponHandling } from "./constants";
import { PALETTE_SLOTS } from "./constants";
import type { CharacterRecipe } from "./character-recipe";
import type { CharacterGeneration } from "./character-generation";
import { DEFAULT_PALETTE, isHexColor, type Palette } from "./phase3";
import { SPEC_VERSION } from "./constants";
import {
  buildPool, emptyContext, pairShoulder, slotIsHidden,
  type CandidateAsset, type CandidateCheck, type CompatibilityContext,
} from "./variation-candidates";
import { paletteCandidates, type PaletteLibrary } from "./variation-palette";
import {
  SLOT_ORDER, VARIATION_SLOTS, clampVariationScale,
  type ScaleRange, type VariationPreset, type VariationSlot,
} from "./variation-preset";
import { streamRng } from "./variation-rng";

export const LOCK_FIELDS = [...VARIATION_SLOTS, "bodyScale", "palette"] as const;
export type LockField = (typeof LOCK_FIELDS)[number];
export const LOCK_FIELD_LABEL: Record<LockField, string> = {
  hair: "Hair", headgear: "Headgear", headAccessory: "Head Accessory", chestArmor: "Chest Armor",
  shoulderLeft: "Shoulder L", shoulderRight: "Shoulder R", armArmor: "Arm Armor", gloves: "Gloves",
  waist: "Waist", boots: "Boots", mainHand: "Main Hand", offHand: "Off Hand", back: "Back",
  bodyScale: "Body Scale", palette: "Palette",
};

export interface GeneratedVariation {
  index: number;
  id: string;
  name: string;
  recipe: CharacterRecipe;
  /** Reroll counter for this one character (spec section 26). */
  salt: number;
  locks: LockField[];
  /** Full-match key over scale + asset ids + palette (spec section 28). */
  signature: string;
  duplicate: boolean;
  warnings: string[];
}

export interface GenerationFailure {
  index: number;
  id: string;
  reason: string;
}

export interface GenerationReport {
  presetId: string;
  seed: number;
  variations: GeneratedVariation[];
  failures: GenerationFailure[];
  duplicates: number;
  generatedAt: string;
}

export interface GenerateInput {
  preset: VariationPreset;
  assets: readonly CandidateAsset[];
  palettes: PaletteLibrary;
  /** Character ids already used in the Character Library (spec section 22). */
  takenIds: ReadonlySet<string>;
}

/** Retry budget for an exact duplicate. Bounded on purpose: spec section 44 forbids infinite retry. */
const DUPLICATE_RETRIES = 6;

// ---- ids / names ---------------------------------------------------------------

export function generatedId(prefix: string, n: number): string {
  const stem = (prefix || "character").replace(/[^a-z0-9_]/g, "_").replace(/^_+|_+$/g, "") || "character";
  return `${stem}_${String(n).padStart(3, "0")}`;
}

function allocateId(prefix: string, taken: Set<string>): { id: string; n: number } {
  for (let n = 1; n <= 9999; n++) {
    const id = generatedId(prefix, n);
    if (!taken.has(id)) { taken.add(id); return { id, n }; }
  }
  const id = `${prefix}_${Date.now()}`;
  taken.add(id);
  return { id, n: 0 };
}

/** Display name for rank-and-file characters (spec section 23); no proper-noun generation in v1. */
export function generatedName(namePrefix: string, n: number): string {
  return `${namePrefix || "Character"} ${String(n).padStart(3, "0")}`;
}

// ---- body ----------------------------------------------------------------------

const round2 = (v: number) => Math.round(v * 100) / 100;

function sampleRange(range: ScaleRange, roll: number, bias: number): number {
  const min = Math.min(range.min, range.max);
  const max = Math.max(range.min, range.max);
  const value = min + roll * (max - min) + bias * (max - min);
  return round2(clampVariationScale(Math.min(max, Math.max(min, value))));
}

/** Gender expression nudges the silhouette rather than swapping the base body (spec section 8). */
function widthBias(gender: VariationPreset["genderExpression"]): number {
  if (gender === "female_style") return -0.12;
  if (gender === "male_style") return 0.12;
  return 0;
}

function bodyPresetFor(bodyType: BodyType, bodyWidth: number): BodyPreset {
  if (bodyType === "child") return "child";
  if (bodyWidth <= 0.96) return "adult_slim";
  if (bodyWidth >= 1.05) return "adult_large";
  return "adult_normal";
}

function chooseBaseAsset(assets: readonly CandidateAsset[], bodyType: BodyType): string {
  const match = assets.find((a) => a.type === "base" && a.bodyTypes.includes(bodyType) && a.hasModel);
  return match?.id ?? "base_body";
}

// ---- palette --------------------------------------------------------------------

function rollPalette(preset: VariationPreset, palettes: PaletteLibrary, seedParts: (string | number)[]): Palette {
  const palette: Palette = { ...DEFAULT_PALETTE };
  for (const slot of PALETTE_SLOTS) {
    const rule = preset.palette.slots[slot];
    if (rule.mode === "fixed") {
      if (isHexColor(rule.fixed)) palette[slot] = rule.fixed.toLowerCase();
      continue;
    }
    const pool = rule.mode === "pool" && slot === "skin" ? palettes.skinPool
      : rule.mode === "pool" && slot === "hair" ? palettes.hairPool
      : paletteCandidates(palettes, preset.palette.setId, slot);
    if (pool.length === 0) continue; // keep the recipe default rather than inventing an RGB value
    const picked = streamRng(...seedParts, "palette", slot).pick(pool);
    if (picked) palette[slot] = picked;
  }
  return palette;
}

// ---- single roll ----------------------------------------------------------------

type SlotAssignment = Partial<Record<VariationSlot, string | null>>;

interface RollOutcome {
  ok: boolean;
  assets: SlotAssignment;
  scale: { height: number; bodyWidth: number; headScale: number };
  bodyType: BodyType;
  palette: Palette;
  warnings: string[];
  failure?: string;
}

interface RollOptions {
  index: number;
  salt: number;
  locks: readonly LockField[];
  /** Previous recipe, used to carry locked fields through a reroll (spec section 27). */
  previous?: CharacterRecipe;
}

function shoulderSides(preset: VariationPreset, stream: (field: string) => ReturnType<typeof streamRng>) {
  switch (preset.shoulderMode) {
    case "both": return { left: true, right: true, symmetric: false };
    case "left": return { left: true, right: false, symmetric: false };
    case "right": return { left: false, right: true, symmetric: false };
    case "none": return { left: false, right: false, symmetric: false };
    case "symmetric": return { left: true, right: true, symmetric: true };
    case "random": {
      const pick = stream("shoulderMode").pick(["both", "left", "right", "none"] as const) ?? "both";
      return { left: pick === "both" || pick === "left", right: pick === "both" || pick === "right", symmetric: false };
    }
  }
}

function rollVariation(input: GenerateInput, opts: RollOptions): RollOutcome {
  const { preset, assets, palettes } = input;
  const { index, salt, locks, previous } = opts;
  const stream = (field: string) => streamRng(preset.seed, preset.id, index, salt, field);
  const warnings: string[] = [];
  const byId = new Map(assets.map((a) => [a.id, a]));
  const lockSet = new Set<LockField>(locks);

  // ---- body ----
  const bodyLocked = lockSet.has("bodyScale") && previous;
  const bodyType = bodyLocked
    ? previous.body.base
    : stream("bodyType").pick(preset.bodyTypes) ?? preset.bodyTypes[0] ?? "adult";
  const bias = widthBias(preset.genderExpression);
  const scale = bodyLocked
    ? { ...previous.body.scale }
    : {
      height: sampleRange(preset.bodyScale.height, stream("height").next(), 0),
      bodyWidth: sampleRange(preset.bodyScale.bodyWidth, stream("bodyWidth").next(), bias),
      headScale: sampleRange(preset.bodyScale.headScale, stream("headScale").next(), 0),
    };

  // ---- equipment ----
  const ctx: CompatibilityContext = emptyContext(bodyType, preset.genderExpression);
  const assigned: SlotAssignment = {};
  const sides = shoulderSides(preset, stream);
  let symmetricLeft: CandidateAsset | null = null;

  const apply = (slot: VariationSlot, asset: CandidateAsset | null) => {
    assigned[slot] = asset?.id ?? null;
    if (!asset) return;
    ctx.usedIds.add(asset.id);
    for (const part of asset.hideParts) ctx.hiddenParts.add(part);
    if (slot === "mainHand") ctx.mainHandHandling = (asset.handling ?? "one_hand") as WeaponHandling;
    // Headgear that hides hair makes an optional hairstyle pointless (spec section 11, Hair Policy).
    if ((slot === "headgear" || slot === "headAccessory") && asset.hairPolicy === "hide") ctx.hiddenParts.add("hair");
  };

  for (const slot of SLOT_ORDER) {
    const rule = preset.slots[slot];

    // Locked slot: keep the previous asset verbatim, but still feed the compatibility context.
    if (lockSet.has(slot) && previous) {
      const keptId = previous.assets[slot] ?? null;
      const kept = keptId ? byId.get(keptId) ?? null : null;
      if (keptId && !kept) warnings.push(`Lock 中の ${slot} (${keptId}) が Asset Library にありません。`);
      if (kept) apply(slot, kept);
      else assigned[slot] = keptId;
      if (slot === "shoulderLeft") symmetricLeft = kept;
      continue;
    }

    if (rule.presence === "forbidden") { assigned[slot] = null; continue; }
    if (slot === "shoulderLeft" && !sides.left) { assigned[slot] = null; continue; }
    if (slot === "shoulderRight" && !sides.right) { assigned[slot] = null; continue; }
    if (slot === "offHand" && ctx.mainHandHandling === "two_hand") {
      // Spec section 13: Two Hand weapon + Off Hand is removed from the candidate space entirely.
      assigned[slot] = null;
      continue;
    }
    if (slotIsHidden(slot, ctx.hiddenParts)) {
      if (rule.presence !== "required") { assigned[slot] = null; continue; }
      warnings.push(`${slot} は他の装備に隠されますが required のため装備します。`);
    }

    const pool = buildPool(assets, slot, rule, ctx);

    // Symmetric shoulders: the right side mirrors the left instead of drawing independently.
    if (slot === "shoulderRight" && sides.symmetric) {
      if (!symmetricLeft) { assigned[slot] = null; continue; }
      const pair = pairShoulder(symmetricLeft, pool.candidates, "right");
      if (!pair) {
        warnings.push(`Symmetric Only ですが ${symmetricLeft.id} の右肩ペアが見つかりません。`);
        assigned[slot] = null;
        continue;
      }
      apply(slot, pair.asset);
      continue;
    }

    if (rule.presence === "optional" && !stream(`${slot}:present`).chance(rule.probability)) {
      assigned[slot] = null;
      continue;
    }

    if (pool.candidates.length === 0) {
      if (rule.presence === "required") {
        return {
          ok: false, assets: assigned, scale, bodyType, palette: { ...DEFAULT_PALETTE }, warnings,
          failure: `required の ${slot} に候補 Asset がありません。`,
        };
      }
      assigned[slot] = null;
      continue;
    }

    const picked = stream(`${slot}:pick`).pickWeighted(pool.candidates, (c: CandidateCheck) => c.weight);
    apply(slot, picked?.asset ?? null);
    if (slot === "shoulderLeft") symmetricLeft = picked?.asset ?? null;
  }

  const palette = lockSet.has("palette") && previous
    ? { ...previous.palette }
    : rollPalette(preset, palettes, [preset.seed, preset.id, index, salt]);

  return { ok: true, assets: assigned, scale, bodyType, palette, warnings };
}

// ---- signature / duplicates ------------------------------------------------------

/** Exact-match key (spec section 28-29): body scale + asset ids + palette. No visual similarity. */
export function variationSignature(recipe: CharacterRecipe): string {
  const assets = VARIATION_SLOTS.map((slot) => `${slot}=${recipe.assets[slot] ?? ""}`).join(",");
  const scale = `${recipe.body.base}:${recipe.body.scale.height}/${recipe.body.scale.bodyWidth}/${recipe.body.scale.headScale}`;
  const palette = PALETTE_SLOTS.map((s: PaletteSlot) => recipe.palette[s]).join(",");
  return `${scale}|${assets}|${palette}`;
}

function buildRecipe(
  preset: VariationPreset,
  input: GenerateInput,
  id: string,
  outcome: RollOutcome,
  index: number,
  salt: number,
  generatedAt: string,
): CharacterRecipe {
  const generation: CharacterGeneration = {
    type: "variation",
    preset: preset.id,
    seed: preset.seed,
    index,
    salt,
    presetVersion: preset.presetVersion,
    generatedAt,
  };
  return {
    specVersion: SPEC_VERSION,
    characterVersion: 1,
    id,
    body: {
      base: outcome.bodyType,
      preset: bodyPresetFor(outcome.bodyType, outcome.scale.bodyWidth),
      assetId: chooseBaseAsset(input.assets, outcome.bodyType),
      scale: outcome.scale,
    },
    assets: { ...outcome.assets },
    palette: outcome.palette,
    generation,
  };
}

// ---- batch ---------------------------------------------------------------------

export function generateVariations(input: GenerateInput): GenerationReport {
  const { preset } = input;
  const generatedAt = new Date().toISOString();
  const taken = new Set<string>(input.takenIds);
  const variations: GeneratedVariation[] = [];
  const failures: GenerationFailure[] = [];
  const seen = new Map<string, string>();
  let duplicates = 0;

  for (let index = 0; index < preset.count; index++) {
    const { id, n } = allocateId(preset.idPrefix || preset.id, taken);

    let outcome = rollVariation(input, { index, salt: 0, locks: [] });
    if (!outcome.ok) {
      failures.push({ index, id, reason: outcome.failure ?? "生成できませんでした。" });
      taken.delete(id);
      continue;
    }

    // Exact duplicate -> reroll with a bumped salt, bounded (spec section 28, 44).
    let salt = 0;
    let recipe = buildRecipe(preset, input, id, outcome, index, salt, generatedAt);
    let signature = variationSignature(recipe);
    for (let retry = 0; retry < DUPLICATE_RETRIES && seen.has(signature); retry++) {
      salt = retry + 1;
      const retried = rollVariation(input, { index, salt, locks: [] });
      if (!retried.ok) break;
      outcome = retried;
      recipe = buildRecipe(preset, input, id, outcome, index, salt, generatedAt);
      signature = variationSignature(recipe);
    }

    const isDuplicate = seen.has(signature);
    if (isDuplicate) duplicates++;
    else seen.set(signature, id);

    variations.push({
      index,
      id,
      name: generatedName(preset.namePrefix || preset.name, n),
      recipe,
      salt,
      locks: [],
      signature,
      duplicate: isDuplicate,
      warnings: isDuplicate
        ? [...outcome.warnings, `Duplicate Variation: ${seen.get(signature)} と完全一致です。`]
        : outcome.warnings,
    });
  }

  return { presetId: preset.id, seed: preset.seed, variations, failures, duplicates, generatedAt };
}

export interface RerollResult {
  ok: boolean;
  variation?: GeneratedVariation;
  error?: string;
}

/**
 * Reroll one character (spec section 26-27). Locked fields are carried over from the previous
 * roll; everything else is redrawn from a bumped salt, so no other character is affected.
 */
export function rerollVariation(
  input: GenerateInput,
  current: GeneratedVariation,
  locks: readonly LockField[],
  otherSignatures: ReadonlySet<string>,
): RerollResult {
  const { preset } = input;
  let salt = current.salt;
  let outcome: RollOutcome | null = null;
  let recipe: CharacterRecipe | null = null;
  let signature = "";

  for (let attempt = 0; attempt < DUPLICATE_RETRIES + 1; attempt++) {
    salt += 1;
    const rolled = rollVariation(input, { index: current.index, salt, locks, previous: current.recipe });
    if (!rolled.ok) return { ok: false, error: rolled.failure ?? "Reroll できませんでした。" };
    outcome = rolled;
    recipe = buildRecipe(preset, input, current.id, rolled, current.index, salt, new Date().toISOString());
    signature = variationSignature(recipe);
    if (!otherSignatures.has(signature)) break;
  }
  if (!outcome || !recipe) return { ok: false, error: "Reroll できませんでした。" };

  const duplicate = otherSignatures.has(signature);
  return {
    ok: true,
    variation: {
      ...current,
      recipe,
      salt,
      locks: [...locks],
      signature,
      duplicate,
      warnings: duplicate ? [...outcome.warnings, "Duplicate Variation: 他の Character と完全一致です。"] : outcome.warnings,
    },
  };
}

/** Recompute duplicate flags across the whole preview list (after a reroll). */
export function markDuplicates(variations: readonly GeneratedVariation[]): GeneratedVariation[] {
  const seen = new Map<string, string>();
  return variations.map((v) => {
    const first = seen.get(v.signature);
    if (first === undefined) {
      seen.set(v.signature, v.id);
      return v.duplicate ? { ...v, duplicate: false, warnings: v.warnings.filter((w) => !w.startsWith("Duplicate Variation")) } : v;
    }
    const note = `Duplicate Variation: ${first} と完全一致です。`;
    return {
      ...v,
      duplicate: true,
      warnings: v.warnings.includes(note) ? v.warnings : [...v.warnings.filter((w) => !w.startsWith("Duplicate Variation")), note],
    };
  });
}
