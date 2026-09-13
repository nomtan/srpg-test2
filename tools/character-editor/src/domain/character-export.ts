// Phase 5 Godot Export metadata. Kept separate from CharacterRecipe (domain/character-recipe.ts):
// the recipe is for re-editing in the Character Builder, this is what the Godot runtime reads.
// Overlap between the two is intentional; they are not merged into one file (spec section 16 / prompt 16).
import { SPEC_VERSION, ANIMATION_SETS, type BodyPreset, type BodyType, type PaletteSlot } from "./constants";
import type { CharacterRecipe } from "./character-recipe";
import { animationMapping, BAKED_BASE_CLIPS } from "@/viewer/animation/animationMapping";

/** 1 GLB unit = 1 metre = 1/12 Blockbench unit; Godot imports at root_scale 1.0 (see docs/phase-5.md section "Scale"). */
export const GODOT_SCALE_RULE =
  "1 glTF unit = 1 metre = 1/12 Blockbench unit (base_1.bbmodel via tools/asset_gen/export_explorer_model.py SCALE=1/12); Godot import apply_root_scale=true root_scale=1.0; 1 field cell = 1 m";

export const CHARACTER_ID_PATTERN = /^[a-z][a-z0-9_]*$/;
export const isValidCharacterId = (id: string) => CHARACTER_ID_PATTERN.test(id);

export interface CharacterExportScale { height: number; bodyWidth: number; headScale: number }

/** Recipe slots that map to Godot equipment, plus the resolved base id. */
export interface CharacterExportAssets {
  base: string | null;
  hair: string | null; headgear: string | null; headAccessory: string | null;
  chestArmor: string | null;
  shoulderLeft: string | null; shoulderRight: string | null;
  armArmor: string | null; gloves: string | null;
  waist: string | null; boots: string | null;
  mainHand: string | null; offHand: string | null; back: string | null;
}

export type AnimationMapping = Record<string, Record<string, string>>;

export interface CharacterExportMetadata {
  specVersion: number;
  characterVersion: number;
  id: string;
  name: string;
  body: { base: BodyType; preset: BodyPreset; scale: CharacterExportScale };
  assets: Partial<CharacterExportAssets>;
  palette: Record<PaletteSlot, string>;
  /** Per-body-part colour overrides; absent when the whole body uses palette.skin. */
  bodyPartColors?: Record<string, string>;
  activeAnimationSet: string;
  /** Mapping layer (prompt 13): normalises the source clip names, incl. the "gread_sword" typo, without renaming clips in the GLB. */
  animations: AnimationMapping;
  visibility: { hiddenParts: string[]; hairPolicy: "hide" | "overlay" | null };
  model: string;
  texture: string;
  thumbnail?: string;
  generator: { tool: string; phase: number; exportedAt: string; scaleRule: string };
}

/** Build the animations map from the baked base clips + their meaning table. */
export function buildAnimationMapping(): AnimationMapping {
  const map: AnimationMapping = {};
  for (const [clip, meaning] of Object.entries(animationMapping)) {
    if (!(BAKED_BASE_CLIPS as readonly string[]).includes(clip)) continue;
    (map[meaning.set] ??= {})[meaning.action] = clip;
  }
  return map;
}

export const EXPORT_ASSET_SLOTS = [
  "hair", "headgear", "headAccessory", "chestArmor", "shoulderLeft", "shoulderRight",
  "armArmor", "gloves", "waist", "boots", "mainHand", "offHand", "back",
] as const;
export type ExportAssetSlot = (typeof EXPORT_ASSET_SLOTS)[number];

export interface BuildMetadataInput {
  recipe: CharacterRecipe;
  name: string;
  activeAnimationSet: string;
  hiddenParts: string[];
  hairPolicy: "hide" | "overlay" | null;
  characterVersion: number;
  thumbnail: boolean;
}

export function buildCharacterMetadata(input: BuildMetadataInput): CharacterExportMetadata {
  const { recipe, name } = input;
  const id = recipe.id;
  const assets: Partial<CharacterExportAssets> = { base: recipe.body.assetId ?? "base_body" };
  for (const slot of EXPORT_ASSET_SLOTS) {
    const value = recipe.assets[slot];
    if (value !== undefined) assets[slot] = value ?? null;
  }
  const activeAnimationSet = (ANIMATION_SETS as readonly string[]).includes(input.activeAnimationSet)
    ? input.activeAnimationSet
    : "default";
  return {
    specVersion: SPEC_VERSION,
    characterVersion: input.characterVersion,
    id,
    name: name.trim() || id,
    body: {
      base: recipe.body.base,
      preset: recipe.body.preset,
      scale: {
        height: recipe.body.scale.height,
        bodyWidth: recipe.body.scale.bodyWidth,
        headScale: recipe.body.scale.headScale,
      },
    },
    assets,
    palette: { ...recipe.palette },
    ...(recipe.bodyPartColors && Object.keys(recipe.bodyPartColors).length
      ? { bodyPartColors: { ...recipe.bodyPartColors } }
      : {}),
    activeAnimationSet,
    animations: buildAnimationMapping(),
    visibility: { hiddenParts: [...input.hiddenParts].sort(), hairPolicy: input.hairPolicy },
    model: `${id}.glb`,
    texture: `${id}.png`,
    ...(input.thumbnail ? { thumbnail: "thumbnail.png" } : {}),
    generator: {
      tool: "srpg-character-editor",
      phase: 5,
      exportedAt: new Date().toISOString(),
      scaleRule: GODOT_SCALE_RULE,
    },
  };
}

/** Deterministic key order for a stable diff, matching spec section 15. */
export function characterMetadataText(meta: CharacterExportMetadata): string {
  const ordered: Record<string, unknown> = {
    specVersion: meta.specVersion,
    characterVersion: meta.characterVersion,
    id: meta.id,
    name: meta.name,
    body: meta.body,
    assets: meta.assets,
    palette: meta.palette,
    ...(meta.bodyPartColors ? { bodyPartColors: meta.bodyPartColors } : {}),
    activeAnimationSet: meta.activeAnimationSet,
    animations: meta.animations,
    visibility: meta.visibility,
    model: meta.model,
    texture: meta.texture,
  };
  if (meta.thumbnail) ordered.thumbnail = meta.thumbnail;
  ordered.generator = meta.generator;
  return JSON.stringify(ordered, null, 2) + "\n";
}
