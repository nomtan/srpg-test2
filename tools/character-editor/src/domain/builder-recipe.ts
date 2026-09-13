// Phase 5 Character Builder recipe helpers. The recipe is the re-editable authoring state
// (spec section 15 / prompt 16); it is NOT the Godot export metadata (domain/character-export.ts).
// Kept separate from the Phase 3 phase3.ts helpers, which are intentionally locked to scale=1.
import type { AssetCategory, CharacterSocket } from "./constants";
import { BODY_PRESETS, PALETTE_SLOTS, SPEC_VERSION } from "./constants";
import { DEFAULT_PALETTE, isHexColor } from "./phase3";
import type { CharacterRecipe } from "./character-recipe";
import { parseGeneration } from "./character-generation";
import { EXPORT_ASSET_SLOTS, type ExportAssetSlot } from "./character-export";

/** Library category that fills each equipment slot (used to filter the picker). */
export const SLOT_CATEGORY: Record<ExportAssetSlot, AssetCategory[]> = {
  hair: ["hair"],
  headgear: ["headgear"],
  headAccessory: ["head_accessory"],
  chestArmor: ["chest_armor"],
  shoulderLeft: ["shoulder_left"],
  shoulderRight: ["shoulder_right"],
  armArmor: ["arm_armor"],
  gloves: ["gloves"],
  waist: ["waist"],
  boots: ["boots"],
  mainHand: ["weapon"],
  offHand: ["shield", "weapon"],
  back: ["back"],
};

/** Character socket each slot attaches to (spec section 6). Weapons follow grip -> hand sockets. */
export const SLOT_SOCKET: Record<ExportAssetSlot, CharacterSocket> = {
  hair: "socket_hair",
  headgear: "socket_headgear",
  headAccessory: "socket_head",
  chestArmor: "socket_chest",
  shoulderLeft: "socket_shoulder_left",
  shoulderRight: "socket_shoulder_right",
  armArmor: "socket_arm_right",
  gloves: "socket_hand_right",
  waist: "socket_waist",
  boots: "socket_foot_right",
  mainHand: "socket_hand_right",
  offHand: "socket_hand_left",
  back: "socket_back",
};

export const SLOT_LABEL: Record<ExportAssetSlot, string> = {
  hair: "Hair", headgear: "Headgear", headAccessory: "Head Accessory", chestArmor: "Chest Armor",
  shoulderLeft: "Shoulder Left", shoulderRight: "Shoulder Right", armArmor: "Arm Armor", gloves: "Gloves",
  waist: "Waist", boots: "Boots", mainHand: "Main Hand", offHand: "Off Hand", back: "Back Equipment",
};

/** Semantic node name given to the attached asset root inside the exported GLB (prompt 5). */
export const SLOT_NODE_NAME: Record<ExportAssetSlot, string> = {
  hair: "Hair", headgear: "Headgear", headAccessory: "HeadAccessory", chestArmor: "ChestArmor",
  shoulderLeft: "ShoulderLeft", shoulderRight: "ShoulderRight", armArmor: "ArmArmor", gloves: "Gloves",
  waist: "Waist", boots: "Boots", mainHand: "MainHand", offHand: "OffHand", back: "BackEquipment",
};

export const SCALE_MIN = 0.7;
export const SCALE_MAX = 1.4;
export const clampScale = (v: number) => Math.min(SCALE_MAX, Math.max(SCALE_MIN, Number.isFinite(v) ? v : 1));

export function emptyRecipe(): CharacterRecipe {
  return {
    specVersion: SPEC_VERSION,
    characterVersion: 1,
    id: "vein",
    body: { base: "adult", preset: "adult_normal", assetId: "base_body", scale: { height: 1, bodyWidth: 1, headScale: 1 } },
    assets: {},
    palette: { ...DEFAULT_PALETTE },
  };
}

export function recipeSlotValue(recipe: CharacterRecipe, slot: ExportAssetSlot): string | null {
  return recipe.assets[slot] ?? null;
}

export interface RecipeIssue { level: "error" | "warning"; message: string }

/** Structural check only; asset/rig checks happen at export time against the loaded scene. */
export function validateRecipeShape(input: unknown): { recipe?: CharacterRecipe; issues: RecipeIssue[] } {
  const issues: RecipeIssue[] = [];
  const push = (level: RecipeIssue["level"], message: string) => issues.push({ level, message });
  if (!input || typeof input !== "object") { push("error", "Recipe が JSON オブジェクトではありません。"); return { issues }; }
  const raw = input as Record<string, unknown>;
  if (raw.specVersion !== SPEC_VERSION) push("error", `specVersion は ${SPEC_VERSION} である必要があります。`);
  if (typeof raw.id !== "string" || !raw.id.trim()) push("error", "id が未設定です。");
  const body = (raw.body ?? {}) as Record<string, unknown>;
  if (body.base !== "adult" && body.base !== "child") push("error", "body.base は adult / child です。");
  if (!BODY_PRESETS.includes(body.preset as (typeof BODY_PRESETS)[number])) push("warning", "body.preset が未知です。adult_normal を使用します。");
  const scale = (body.scale ?? {}) as Record<string, unknown>;
  for (const key of ["height", "bodyWidth", "headScale"] as const) {
    const v = scale[key];
    if (typeof v !== "number" || !Number.isFinite(v)) push("error", `body.scale.${key} が数値ではありません。`);
    else if (v <= 0) push("error", `body.scale.${key} は 0 以下にできません。`);
    else if (v < SCALE_MIN || v > SCALE_MAX) push("warning", `body.scale.${key} (${v}) が想定範囲 ${SCALE_MIN}–${SCALE_MAX} 外です。`);
  }
  const palette = (raw.palette ?? {}) as Record<string, unknown>;
  for (const slot of PALETTE_SLOTS) {
    if (!isHexColor(palette[slot])) push("error", `palette.${slot} が #RRGGBB ではありません。`);
  }
  // Per-part colour overrides are optional; a bad entry is dropped with a warning rather than
  // failing the whole recipe, because the global skin colour is always a valid fallback.
  const rawPartColors = (raw.bodyPartColors ?? {}) as Record<string, unknown>;
  const bodyPartColors: Record<string, string> = {};
  if (typeof rawPartColors !== "object" || Array.isArray(rawPartColors)) {
    push("warning", "bodyPartColors がオブジェクトではありません。無視します。");
  } else {
    for (const [part, value] of Object.entries(rawPartColors)) {
      if (isHexColor(value)) bodyPartColors[part] = String(value).toLowerCase();
      else push("warning", `bodyPartColors.${part} が #RRGGBB ではありません。無視します。`);
    }
  }

  const assets = (raw.assets ?? {}) as Record<string, unknown>;
  if (typeof assets !== "object" || Array.isArray(assets)) push("error", "assets がオブジェクトではありません。");
  else for (const key of Object.keys(assets)) {
    if (!(EXPORT_ASSET_SLOTS as readonly string[]).includes(key) && key !== "texture")
      push("warning", `未知の asset slot: ${key}`);
    const value = assets[key];
    if (value !== null && typeof value !== "string") push("error", `assets.${key} は文字列または null です。`);
  }
  if (issues.some((i) => i.level === "error")) return { issues };
  const recipe: CharacterRecipe = {
    specVersion: SPEC_VERSION,
    characterVersion: typeof raw.characterVersion === "number" && raw.characterVersion > 0 ? Math.floor(raw.characterVersion) : 1,
    id: (raw.id as string).trim(),
    body: {
      base: body.base as "adult" | "child",
      preset: BODY_PRESETS.includes(body.preset as (typeof BODY_PRESETS)[number]) ? (body.preset as (typeof BODY_PRESETS)[number]) : "adult_normal",
      assetId: typeof body.assetId === "string" ? body.assetId : "base_body",
      scale: {
        height: scale.height as number,
        bodyWidth: scale.bodyWidth as number,
        headScale: scale.headScale as number,
      },
    },
    assets: Object.fromEntries(
      Object.entries(assets).filter(([, v]) => v === null || typeof v === "string"),
    ) as CharacterRecipe["assets"],
    palette: Object.fromEntries(PALETTE_SLOTS.map((s) => [s, String(palette[s]).toLowerCase()])) as CharacterRecipe["palette"],
  } as CharacterRecipe;
  if (Object.keys(bodyPartColors).length) recipe.bodyPartColors = bodyPartColors;
  // Phase 8: keep the generation provenance through a Builder round-trip (spec section 48-49).
  const generation = parseGeneration(raw.generation);
  if (generation) recipe.generation = generation;
  return { recipe, issues };
}

export function recipeText(recipe: CharacterRecipe): string {
  return JSON.stringify(recipe, null, 2) + "\n";
}
