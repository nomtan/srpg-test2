import type { AssetMetadata } from "./asset";
import type { CharacterRecipe } from "./character-recipe";
import { PALETTE_SLOTS, type PaletteSlot, type RecipeSlot, type AssetCategory, type AnimationSet, type CharacterSocket } from "./constants.ts";

export type Palette = Record<PaletteSlot, string>;
export const DEFAULT_PALETTE: Palette = { primary: "#8c2430", secondary: "#303030", metal: "#a0a0a0", leather: "#654321", hair: "#36251c", skin: "#d8aa85" };
export const isHexColor = (value: unknown): value is string => typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value);
export interface PaletteMap { version: 1; mode: "material"; materials: Record<string, PaletteSlot> }
export interface WorkshopAsset extends AssetMetadata {
  recipeSlot: RecipeSlot;
  binding: { roots: string[]; kind: "source_group" | "fixture" };
}
const base = { specVersion: 1, assetVersion: 1, bodyTypes: ["adult"], hairPolicy: null, hideParts: [], model: "preview-rig.glb" } as const;
function weapon(id: string, name: string, roots: string[], set: AnimationSet, handling: "one_hand" | "two_hand", socket: CharacterSocket): WorkshopAsset {
  return { ...base, bodyTypes: ["adult"], hideParts: [], id, name, type: "weapon", recipeSlot: "mainHand", equipment: { slot: "main_hand", handling, animationSet: set }, attachment: { main: { assetPoint: "authored_origin", characterSocket: socket } }, appearance: { paletteSlots: ["metal", "leather", "primary"] }, binding: { roots, kind: "source_group" } };
}
/**
 * Phase 3 leftovers. The `characterSocket` values here mirror the SOURCE's own spelling
 * (`onehand_sword` lives under `hand_left_te`), which is the character's RIGHT hand — see
 * SOURCE_NODE_BY_SIDE in base-rig.ts. The Builder does not read these; it uses SLOT_SOCKET.
 */
export const SOURCE_EQUIPMENT: WorkshopAsset[] = [
  weapon("source_sword", "Sword · 既存Group", ["onehand_sword"], "onehand_sword", "one_hand", "socket_hand_left"),
  weapon("source_great_sword", "Great Sword · 既存Group", ["gread_sword"], "great_sword", "two_hand", "socket_hand_left"),
  weapon("source_bow", "Bow · 既存Group", ["bow", "allow"], "bow", "two_hand", "socket_hand_right"),
  weapon("source_spear", "Spear · 既存Group", ["spear"], "spear", "two_hand", "socket_hand_left"),
  weapon("source_dagger", "Daggers · 既存Group", ["dagger_left", "dagger_right"], "dagger", "two_hand", "socket_hand_left"),
  { ...base, bodyTypes: ["adult"], hideParts: [], id: "source_shield", name: "Shield · 既存Group", type: "shield", recipeSlot: "offHand", equipment: { slot: "off_hand", handling: "off_hand" }, attachment: { main: { assetPoint: "authored_origin", characterSocket: "socket_arm_right" } }, appearance: { paletteSlots: ["metal", "leather", "primary"] }, binding: { roots: ["shield"], kind: "source_group" } },
];
export interface FixtureSpec { id: string; category: AssetCategory; slot: RecipeSlot; parent: string; socket: CharacterSocket; position: [number, number, number]; size: [number, number, number]; palette: PaletteSlot }
/** Offline-generated fitting samples, in existing group-local Blockbench units. */
export const FIXTURES: FixtureSpec[] = [
  { id: "sample_hair", category: "hair", slot: "hair", parent: "ganmen", socket: "socket_head", position: [0, 7, 0], size: [7.4, 1.2, 7.4], palette: "hair" },
  { id: "sample_headgear", category: "headgear", slot: "headgear", parent: "ganmen", socket: "socket_head", position: [0, 7.3, 0], size: [7.8, 1.8, 7.8], palette: "metal" },
  { id: "sample_chest", category: "chest_armor", slot: "chestArmor", parent: "dou", socket: "socket_chest", position: [2.3, 4, -5], size: [0.6, 4.8, 6.4], palette: "primary" },
  { id: "sample_shoulder_left", category: "shoulder_left", slot: "shoulderLeft", parent: "hand_left", socket: "socket_shoulder_left", position: [0, 0, 0.2], size: [3, 1.8, 2.4], palette: "metal" },
  { id: "sample_shoulder_right", category: "shoulder_right", slot: "shoulderRight", parent: "hand_right", socket: "socket_shoulder_right", position: [0, 0, -0.2], size: [3, 1.8, 2.4], palette: "metal" },
  { id: "sample_back", category: "back", slot: "back", parent: "body", socket: "socket_back", position: [-2.5, 5, 0], size: [0.6, 7, 6.6], palette: "secondary" },
];
export const WORKSHOP_ASSETS: WorkshopAsset[] = [...SOURCE_EQUIPMENT, ...FIXTURES.map((f): WorkshopAsset => ({
  ...base, bodyTypes: ["adult"], hideParts: [], id: f.id, name: `${f.category} · 追従確認用`, type: f.category, recipeSlot: f.slot,
  hairPolicy: f.category === "headgear" ? "hide" : null,
  attachment: { main: { assetPoint: "fixture_origin", characterSocket: f.socket } },
  appearance: { paletteSlots: [f.palette] }, binding: { roots: [f.id], kind: "fixture" },
}))];
export const BASE_PALETTE_SLOTS: PaletteSlot[] = ["primary", "secondary", "metal", "leather", "skin"];
export const assetById = (id: string) => WORKSHOP_ASSETS.find((asset) => asset.id === id);
export function createRecipe(): CharacterRecipe {
  return { specVersion: 1, id: "character_001", body: { base: "adult", preset: "adult_normal", assetId: "base_body", scale: { height: 1, bodyWidth: 1, headScale: 1 } }, assets: { hair: "sample_hair", chestArmor: "sample_chest", mainHand: "source_sword" }, palette: { ...DEFAULT_PALETTE } };
}
export function activePaletteSlots(recipe: CharacterRecipe): Set<PaletteSlot> {
  return new Set([...BASE_PALETTE_SLOTS, ...Object.values(recipe.assets).flatMap((id) => id ? assetById(id)?.appearance.paletteSlots ?? [] : [])]);
}
/** Fail atomically on invalid recipes; never replace working state with partial input. */
export function importRecipe(text: string): CharacterRecipe {
  const input = JSON.parse(text);
  if (!input || input.specVersion !== 1 || typeof input.id !== "string" || !input.id.trim()) throw new Error("RecipeのspecVersion / idが不正です。");
  if (input.body?.base !== "adult" || input.body?.preset !== "adult_normal" || (input.body.assetId && input.body.assetId !== "base_body")) throw new Error("現在のPreviewはadult_normal / base_bodyに対応しています。");
  if (!["height", "bodyWidth", "headScale"].every((key) => input.body?.scale?.[key] === 1)) throw new Error("Body Scale変更は未対応です。各値を1にしてください。");
  if (!input.palette || Object.keys(input.palette).some((key) => !PALETTE_SLOTS.includes(key as PaletteSlot)) || !PALETTE_SLOTS.every((key) => isHexColor(input.palette[key]))) throw new Error("Palette Slotまたは色が不正です。6桁の#RRGGBBを指定してください。");
  if (!input.assets || typeof input.assets !== "object" || Array.isArray(input.assets)) throw new Error("assetsが不正です。");
  const slots = ["hair", "headgear", "chestArmor", "shoulderLeft", "shoulderRight", "mainHand", "offHand", "back"];
  for (const [slot, id] of Object.entries(input.assets)) {
    if (!slots.includes(slot) || (id !== null && (typeof id !== "string" || assetById(id)?.recipeSlot !== slot))) throw new Error(`未対応のAsset / Slot: ${slot}`);
  }
  return { specVersion: 1, id: input.id, body: { ...createRecipe().body }, assets: { ...input.assets }, palette: Object.fromEntries(PALETTE_SLOTS.map((key) => [key, input.palette[key].toLowerCase()])) as Palette };
}
