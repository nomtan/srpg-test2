// Phase 8 Variation Preset schema (spec section 3-4, 7, 12-16, 36-37, 40-42).
// A preset is a *rule set*, not a character: tags + presence + probability + weights per slot,
// plus body-scale ranges and a palette plan. Generation reads it; nothing here draws anything.
import { PALETTE_SLOTS, type BodyType, type PaletteSlot, type WeaponType } from "./constants";
import { EXPORT_ASSET_SLOTS, type ExportAssetSlot } from "./character-export";

export type VariationSlot = ExportAssetSlot;
export const VARIATION_SLOTS = EXPORT_ASSET_SLOTS;

/**
 * Selection order (spec section 11-13). Main Hand first because two-hand weapons remove the Off
 * Hand; headgear before hair so a hairPolicy "hide" headgear can suppress an optional hairstyle.
 */
export const SLOT_ORDER: readonly VariationSlot[] = [
  "mainHand", "offHand",
  "chestArmor", "shoulderLeft", "shoulderRight", "armArmor", "gloves", "waist", "boots", "back",
  "headgear", "headAccessory", "hair",
];

/** Left / right shoulders are independent assets, so the preset drives the pairing (spec 16). */
export const SHOULDER_MODES = ["both", "left", "right", "none", "random", "symmetric"] as const;
export type ShoulderMode = (typeof SHOULDER_MODES)[number];
export const SHOULDER_MODE_LABEL: Record<ShoulderMode, string> = {
  both: "Both", left: "Left Only", right: "Right Only", none: "None",
  random: "Random", symmetric: "Symmetric Only",
};

/** required / optional / forbidden for every category (spec section 14-15). */
export const PRESENCE_MODES = ["required", "optional", "forbidden"] as const;
export type PresenceMode = (typeof PRESENCE_MODES)[number];

export const GENDER_EXPRESSIONS = ["any", "male_style", "female_style", "neutral"] as const;
export type GenderExpression = (typeof GENDER_EXPRESSIONS)[number];
/** Style tags read off assets (spec section 8). "any" never filters. */
export const GENDER_STYLE_TAGS: readonly string[] = ["male_style", "female_style", "neutral"];

export interface SlotRule {
  presence: PresenceMode;
  /** 0..1, applied when presence === "optional" (spec section 14-15). */
  probability: number;
  /** Any-of tag filter. Empty = no tag constraint (spec section 5: do not over-require tags). */
  tags: string[];
  excludeTags: string[];
  /** Explicit allow list from the Allowed Assets checkboxes. Empty = every tag match. */
  assetIds: string[];
  /** Main Hand / Off Hand only (spec section 12). Empty = any weapon type. */
  weaponTypes: WeaponType[];
  /** Per-asset weight override; wins over asset metadata weight / rarity (spec section 9-10). */
  weights: Record<string, number>;
}

export function emptySlotRule(presence: PresenceMode = "optional", probability = 0.5): SlotRule {
  return { presence, probability, tags: [], excludeTags: [], assetIds: [], weaponTypes: [], weights: {} };
}

export interface ScaleRange { min: number; max: number }

/** Generated scale is deliberately narrow - spec section 7 forbids extreme bodies. */
export const VARIATION_SCALE_MIN = 0.85;
export const VARIATION_SCALE_MAX = 1.15;
export const clampVariationScale = (v: number) =>
  Math.min(VARIATION_SCALE_MAX, Math.max(VARIATION_SCALE_MIN, Number.isFinite(v) ? v : 1));

export const BODY_SCALE_PROFILES = ["normal", "slightly_large", "slightly_slim", "wide_variation", "custom"] as const;
export type BodyScaleProfile = (typeof BODY_SCALE_PROFILES)[number];
export const BODY_SCALE_PROFILE_LABEL: Record<BodyScaleProfile, string> = {
  normal: "Normal", slightly_large: "Slightly Large", slightly_slim: "Slightly Slim",
  wide_variation: "Wide Variation", custom: "Custom",
};

export interface PresetBodyScale {
  profile: BodyScaleProfile;
  height: ScaleRange;
  bodyWidth: ScaleRange;
  headScale: ScaleRange;
}

const RANGES: Record<Exclude<BodyScaleProfile, "custom">, PresetBodyScale> = {
  normal: {
    profile: "normal",
    height: { min: 0.95, max: 1.05 }, bodyWidth: { min: 0.95, max: 1.05 }, headScale: { min: 0.97, max: 1.03 },
  },
  slightly_large: {
    profile: "slightly_large",
    height: { min: 1.0, max: 1.08 }, bodyWidth: { min: 1.0, max: 1.1 }, headScale: { min: 0.96, max: 1.02 },
  },
  slightly_slim: {
    profile: "slightly_slim",
    height: { min: 0.97, max: 1.05 }, bodyWidth: { min: 0.9, max: 0.99 }, headScale: { min: 0.98, max: 1.04 },
  },
  wide_variation: {
    profile: "wide_variation",
    height: { min: 0.92, max: 1.08 }, bodyWidth: { min: 0.88, max: 1.12 }, headScale: { min: 0.95, max: 1.05 },
  },
};

export function bodyScaleForProfile(profile: BodyScaleProfile): PresetBodyScale {
  const base = profile === "custom" ? RANGES.normal : RANGES[profile];
  return { profile, height: { ...base.height }, bodyWidth: { ...base.bodyWidth }, headScale: { ...base.headScale } };
}

/** Where each palette slot colour comes from (spec section 17-19). */
export type PaletteSlotMode = "set" | "pool" | "fixed";
export interface PaletteSlotRule { mode: PaletteSlotMode; fixed?: string }
export interface PalettePlan {
  setId: string;
  slots: Record<PaletteSlot, PaletteSlotRule>;
}

export function defaultPalettePlan(setId: string): PalettePlan {
  return {
    setId,
    slots: Object.fromEntries(
      PALETTE_SLOTS.map((slot) => [slot, { mode: slot === "skin" || slot === "hair" ? "pool" : "set" } as PaletteSlotRule]),
    ) as Record<PaletteSlot, PaletteSlotRule>,
  };
}

export interface VariationPreset {
  specVersion: 1;
  presetVersion: number;
  id: string;
  name: string;
  description: string;
  /** Carried onto every generated Character as a tag (spec section 36-37). */
  faction: string;
  role: string;
  /** Hint only - Phase 8 never touches Job / Stats data (spec section 38-39). */
  suggestedRole: string;
  bodyTypes: BodyType[];
  genderExpression: GenderExpression;
  count: number;
  seed: number;
  bodyScale: PresetBodyScale;
  shoulderMode: ShoulderMode;
  slots: Record<VariationSlot, SlotRule>;
  palette: PalettePlan;
  /** Extra Character tags beyond faction / role. */
  tags: string[];
  idPrefix: string;
  namePrefix: string;
  updatedAt: string;
}

export const MIN_COUNT = 1;
/** Spec section 34: 1-100 is the v1 target; larger batches are refused rather than hung. */
export const MAX_COUNT = 100;
export const clampCount = (n: number) =>
  Math.min(MAX_COUNT, Math.max(MIN_COUNT, Number.isFinite(n) ? Math.floor(n) : MIN_COUNT));

function slots(overrides: Partial<Record<VariationSlot, Partial<SlotRule>>>): Record<VariationSlot, SlotRule> {
  const base = Object.fromEntries(
    VARIATION_SLOTS.map((slot) => [slot, emptySlotRule("optional", 0.35)]),
  ) as Record<VariationSlot, SlotRule>;
  for (const [slot, patch] of Object.entries(overrides)) {
    base[slot as VariationSlot] = { ...base[slot as VariationSlot], ...patch };
  }
  return base;
}

export function emptyPreset(id = "new_preset"): VariationPreset {
  return {
    specVersion: 1,
    presetVersion: 1,
    id,
    name: "New Preset",
    description: "",
    faction: "",
    role: "",
    suggestedRole: "",
    bodyTypes: ["adult"],
    genderExpression: "any",
    count: 10,
    seed: 12345,
    bodyScale: bodyScaleForProfile("normal"),
    shoulderMode: "random",
    slots: slots({ hair: { presence: "optional", probability: 0.9 } }),
    palette: defaultPalettePlan("kingdom"),
    tags: [],
    idPrefix: id,
    namePrefix: "New Preset",
    updatedAt: new Date().toISOString(),
  };
}

interface BuiltinSpec {
  id: string;
  name: string;
  faction: string;
  role: string;
  profile: BodyScaleProfile;
  paletteSet: string;
  shoulderMode: ShoulderMode;
  count: number;
  seed: number;
  slots: Partial<Record<VariationSlot, Partial<SlotRule>>>;
}

const BUILTIN_SPECS: BuiltinSpec[] = [
  {
    id: "kingdom_soldier", name: "Kingdom Soldier", faction: "kingdom", role: "soldier",
    profile: "normal", paletteSet: "kingdom", shoulderMode: "symmetric", count: 20, seed: 12345,
    slots: {
      hair: { presence: "optional", probability: 0.85, tags: ["human"] },
      headgear: { presence: "optional", probability: 0.4, tags: ["kingdom", "soldier"] },
      chestArmor: { presence: "required", tags: ["kingdom", "soldier"] },
      shoulderLeft: { presence: "optional", probability: 0.5, tags: ["kingdom"] },
      shoulderRight: { presence: "optional", probability: 0.5, tags: ["kingdom"] },
      gloves: { presence: "optional", probability: 0.4 },
      waist: { presence: "optional", probability: 0.5 },
      boots: { presence: "optional", probability: 0.6 },
      mainHand: { presence: "required", tags: ["kingdom"], weaponTypes: ["sword", "spear"] },
      offHand: { presence: "optional", probability: 0.4 },
      back: { presence: "forbidden" },
    },
  },
  {
    id: "empire_soldier", name: "Empire Soldier", faction: "empire", role: "soldier",
    profile: "normal", paletteSet: "empire", shoulderMode: "symmetric", count: 20, seed: 22345,
    slots: {
      hair: { presence: "optional", probability: 0.8, tags: ["human"] },
      headgear: { presence: "optional", probability: 0.5, tags: ["empire", "soldier"] },
      chestArmor: { presence: "required", tags: ["empire", "soldier"] },
      shoulderLeft: { presence: "optional", probability: 0.6, tags: ["empire"] },
      shoulderRight: { presence: "optional", probability: 0.6, tags: ["empire"] },
      waist: { presence: "optional", probability: 0.5 },
      boots: { presence: "optional", probability: 0.6 },
      mainHand: { presence: "required", tags: ["empire"], weaponTypes: ["sword", "spear"] },
      offHand: { presence: "optional", probability: 0.4 },
      back: { presence: "forbidden" },
    },
  },
  {
    id: "kingdom_archer", name: "Kingdom Archer", faction: "kingdom", role: "archer",
    profile: "slightly_slim", paletteSet: "kingdom", shoulderMode: "random", count: 12, seed: 32345,
    slots: {
      hair: { presence: "optional", probability: 0.9, tags: ["human"] },
      headgear: { presence: "optional", probability: 0.25 },
      chestArmor: { presence: "required", tags: ["kingdom", "light"] },
      shoulderLeft: { presence: "optional", probability: 0.3 },
      shoulderRight: { presence: "optional", probability: 0.3 },
      gloves: { presence: "optional", probability: 0.6 },
      boots: { presence: "optional", probability: 0.6 },
      mainHand: { presence: "required", weaponTypes: ["bow"] },
      offHand: { presence: "forbidden" },
      back: { presence: "optional", probability: 0.6 },
    },
  },
  {
    id: "empire_knight", name: "Empire Knight", faction: "empire", role: "knight",
    profile: "slightly_large", paletteSet: "empire", shoulderMode: "symmetric", count: 8, seed: 42345,
    slots: {
      hair: { presence: "optional", probability: 0.5, tags: ["human"] },
      headgear: { presence: "required", tags: ["empire", "knight", "heavy"] },
      chestArmor: { presence: "required", tags: ["empire", "knight", "heavy"] },
      shoulderLeft: { presence: "required", tags: ["empire", "heavy"] },
      shoulderRight: { presence: "required", tags: ["empire", "heavy"] },
      armArmor: { presence: "optional", probability: 0.7 },
      gloves: { presence: "optional", probability: 0.7 },
      waist: { presence: "optional", probability: 0.5 },
      boots: { presence: "optional", probability: 0.8 },
      mainHand: { presence: "required", weaponTypes: ["sword", "great_sword"] },
      offHand: { presence: "optional", probability: 0.6 },
      back: { presence: "optional", probability: 0.3 },
    },
  },
  {
    id: "bandit", name: "Bandit", faction: "bandit", role: "bandit",
    profile: "wide_variation", paletteSet: "bandit", shoulderMode: "random", count: 15, seed: 52345,
    slots: {
      hair: { presence: "optional", probability: 0.85 },
      headgear: { presence: "optional", probability: 0.35 },
      headAccessory: { presence: "optional", probability: 0.25 },
      chestArmor: { presence: "optional", probability: 0.7, tags: ["light", "common"] },
      shoulderLeft: { presence: "optional", probability: 0.25 },
      shoulderRight: { presence: "optional", probability: 0.25 },
      gloves: { presence: "optional", probability: 0.4 },
      waist: { presence: "optional", probability: 0.5 },
      boots: { presence: "optional", probability: 0.5 },
      mainHand: { presence: "required", weaponTypes: ["dagger", "sword"] },
      offHand: { presence: "optional", probability: 0.3 },
      back: { presence: "optional", probability: 0.2 },
    },
  },
  {
    id: "villager", name: "Villager", faction: "civilian", role: "villager",
    profile: "normal", paletteSet: "villager", shoulderMode: "none", count: 20, seed: 62345,
    slots: {
      hair: { presence: "optional", probability: 0.95 },
      headgear: { presence: "optional", probability: 0.2, tags: ["villager", "common"] },
      headAccessory: { presence: "optional", probability: 0.15 },
      chestArmor: { presence: "optional", probability: 0.5, tags: ["villager", "common"] },
      shoulderLeft: { presence: "forbidden" },
      shoulderRight: { presence: "forbidden" },
      armArmor: { presence: "forbidden" },
      gloves: { presence: "optional", probability: 0.2 },
      waist: { presence: "optional", probability: 0.4 },
      boots: { presence: "optional", probability: 0.5 },
      mainHand: { presence: "optional", probability: 0.2, tags: ["villager", "common"] },
      offHand: { presence: "forbidden" },
      back: { presence: "optional", probability: 0.2 },
    },
  },
  {
    id: "elf_warrior", name: "Elf Warrior", faction: "elf", role: "soldier",
    profile: "slightly_slim", paletteSet: "elf", shoulderMode: "symmetric", count: 10, seed: 72345,
    slots: {
      hair: { presence: "required", tags: ["elf"] },
      headgear: { presence: "optional", probability: 0.3, tags: ["elf"] },
      chestArmor: { presence: "required", tags: ["elf", "light", "medium"] },
      shoulderLeft: { presence: "optional", probability: 0.5, tags: ["elf"] },
      shoulderRight: { presence: "optional", probability: 0.5, tags: ["elf"] },
      gloves: { presence: "optional", probability: 0.5 },
      boots: { presence: "optional", probability: 0.7 },
      mainHand: { presence: "required", weaponTypes: ["sword", "spear"] },
      offHand: { presence: "optional", probability: 0.35 },
      back: { presence: "optional", probability: 0.25 },
    },
  },
  {
    id: "elf_archer", name: "Elf Archer", faction: "elf", role: "archer",
    profile: "slightly_slim", paletteSet: "elf", shoulderMode: "random", count: 10, seed: 82345,
    slots: {
      hair: { presence: "required", tags: ["elf"] },
      headgear: { presence: "optional", probability: 0.2, tags: ["elf"] },
      chestArmor: { presence: "required", tags: ["elf", "light"] },
      shoulderLeft: { presence: "optional", probability: 0.3 },
      shoulderRight: { presence: "optional", probability: 0.3 },
      gloves: { presence: "optional", probability: 0.6 },
      boots: { presence: "optional", probability: 0.7 },
      mainHand: { presence: "required", weaponTypes: ["bow"] },
      offHand: { presence: "forbidden" },
      back: { presence: "optional", probability: 0.7 },
    },
  },
];

export function builtinPresets(): VariationPreset[] {
  const at = new Date(0).toISOString();
  return BUILTIN_SPECS.map((spec) => ({
    ...emptyPreset(spec.id),
    id: spec.id,
    name: spec.name,
    description: `${spec.faction} / ${spec.role} の一般 Variation Preset。`,
    faction: spec.faction,
    role: spec.role,
    suggestedRole: spec.role,
    count: spec.count,
    seed: spec.seed,
    bodyScale: bodyScaleForProfile(spec.profile),
    shoulderMode: spec.shoulderMode,
    slots: slots(spec.slots),
    palette: defaultPalettePlan(spec.paletteSet),
    tags: [],
    idPrefix: spec.id,
    namePrefix: spec.name,
    updatedAt: at,
  }));
}

// ---- Serialisation -----------------------------------------------------------------

const str = (v: unknown, fallback = "") => (typeof v === "string" ? v : fallback);
const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? v : fallback);
const strList = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

function parseRange(input: unknown, fallback: ScaleRange): ScaleRange {
  const raw = (input ?? {}) as Record<string, unknown>;
  const min = clampVariationScale(num(raw.min, fallback.min));
  const max = clampVariationScale(num(raw.max, fallback.max));
  return { min, max };
}

function parseSlotRule(input: unknown): SlotRule {
  const raw = (input ?? {}) as Record<string, unknown>;
  const presence = (PRESENCE_MODES as readonly string[]).includes(str(raw.presence))
    ? (raw.presence as PresenceMode)
    : "optional";
  const weights: Record<string, number> = {};
  if (raw.weights && typeof raw.weights === "object") {
    for (const [id, w] of Object.entries(raw.weights as Record<string, unknown>)) {
      const value = num(w, NaN);
      if (Number.isFinite(value) && value >= 0) weights[id] = value;
    }
  }
  return {
    presence,
    probability: clamp01(num(raw.probability, 0.5)),
    tags: strList(raw.tags),
    excludeTags: strList(raw.excludeTags),
    assetIds: strList(raw.assetIds),
    weaponTypes: strList(raw.weaponTypes) as WeaponType[],
    weights,
  };
}

/** Tolerant parse: unknown keys are dropped, missing keys take preset defaults. */
export function parsePreset(input: unknown): VariationPreset {
  const raw = (input ?? {}) as Record<string, unknown>;
  const id = str(raw.id).trim() || "imported_preset";
  const base = emptyPreset(id);
  const rawSlots = (raw.slots ?? raw.assetRules ?? {}) as Record<string, unknown>;
  const scaleRaw = (raw.bodyScale ?? {}) as Record<string, unknown>;
  const profile = (BODY_SCALE_PROFILES as readonly string[]).includes(str(scaleRaw.profile))
    ? (scaleRaw.profile as BodyScaleProfile)
    : "custom";
  const profileBase = bodyScaleForProfile(profile === "custom" ? "normal" : profile);
  const paletteRaw = (raw.palette ?? {}) as Record<string, unknown>;
  const paletteSlotsRaw = (paletteRaw.slots ?? {}) as Record<string, unknown>;
  const bodyTypes = strList(raw.bodyTypes).filter((b): b is BodyType => b === "adult" || b === "child");

  return {
    specVersion: 1,
    presetVersion: Math.max(1, Math.floor(num(raw.presetVersion, 1))),
    id,
    name: str(raw.name) || id,
    description: str(raw.description),
    faction: str(raw.faction),
    role: str(raw.role),
    suggestedRole: str(raw.suggestedRole) || str(raw.role),
    bodyTypes: bodyTypes.length ? bodyTypes : ["adult"],
    genderExpression: (GENDER_EXPRESSIONS as readonly string[]).includes(str(raw.genderExpression))
      ? (raw.genderExpression as GenderExpression)
      : "any",
    count: clampCount(num(raw.count, base.count)),
    seed: Math.abs(Math.floor(num(raw.seed, base.seed))),
    bodyScale: {
      profile,
      height: parseRange(scaleRaw.height, profileBase.height),
      bodyWidth: parseRange(scaleRaw.bodyWidth, profileBase.bodyWidth),
      headScale: parseRange(scaleRaw.headScale, profileBase.headScale),
    },
    shoulderMode: (SHOULDER_MODES as readonly string[]).includes(str(raw.shoulderMode))
      ? (raw.shoulderMode as ShoulderMode)
      : base.shoulderMode,
    slots: Object.fromEntries(
      VARIATION_SLOTS.map((slot) => [slot, rawSlots[slot] ? parseSlotRule(rawSlots[slot]) : base.slots[slot]]),
    ) as Record<VariationSlot, SlotRule>,
    palette: {
      setId: str(paletteRaw.setId) || base.palette.setId,
      slots: Object.fromEntries(
        PALETTE_SLOTS.map((slot) => {
          const rule = (paletteSlotsRaw[slot] ?? {}) as Record<string, unknown>;
          const mode = str(rule.mode);
          return [slot, {
            mode: mode === "set" || mode === "pool" || mode === "fixed" ? mode : base.palette.slots[slot].mode,
            ...(typeof rule.fixed === "string" ? { fixed: rule.fixed } : {}),
          } as PaletteSlotRule];
        }),
      ) as Record<PaletteSlot, PaletteSlotRule>,
    },
    tags: strList(raw.tags),
    idPrefix: str(raw.idPrefix) || id,
    namePrefix: str(raw.namePrefix) || str(raw.name) || id,
    updatedAt: str(raw.updatedAt) || new Date().toISOString(),
  };
}

export function presetText(preset: VariationPreset): string {
  return JSON.stringify(preset, null, 2) + "\n";
}

/** Preset duplicate (spec section 42): new id, everything else copied verbatim. */
export function duplicatePreset(source: VariationPreset, id: string, name: string): VariationPreset {
  const copy = parsePreset(JSON.parse(JSON.stringify(source)));
  return {
    ...copy,
    id,
    name,
    namePrefix: name,
    idPrefix: id,
    presetVersion: 1,
    updatedAt: new Date().toISOString(),
  };
}
