// Pre-export validation (spec section 3 / prompt 3). Errors block the export; warnings do not.
// Rig / bounding-box / animation-clip checks that need the loaded scene run in round-trip.ts.
import type { CharacterRecipe } from "@/domain/character-recipe";
import { ANIMATION_SETS, PALETTE_SLOTS } from "@/domain/constants";
import { isHexColor } from "@/domain/phase3";
import { isValidCharacterId, EXPORT_ASSET_SLOTS, type ExportAssetSlot } from "@/domain/character-export";
import { SLOT_CATEGORY, SLOT_SOCKET, SCALE_MIN, SCALE_MAX } from "@/domain/builder-recipe";
import { socketNodeName } from "@/features/asset-creator/base-parts";
import type { AssetLibrary } from "@/features/asset-library/library";
import { modelUrl } from "@/features/asset-library/library";
import { baseSocketDefinitions } from "@/domain/base-rig";

export type ExportIssueLevel = "error" | "warning" | "info";
export type ExportIssueSection = "character" | "assets" | "rig" | "scale" | "texture";
export interface ExportIssue {
  level: ExportIssueLevel;
  section: ExportIssueSection;
  message: string;
}

export interface ExportValidationInput {
  recipe: CharacterRecipe;
  name: string;
  library: AssetLibrary;
  activeAnimationSet: string;
}

export function validateExport(input: ExportValidationInput): ExportIssue[] {
  const { recipe, library } = input;
  const items: ExportIssue[] = [];
  const add = (level: ExportIssueLevel, section: ExportIssueSection, message: string) => items.push({ level, section, message });

  // ---- Character ----
  if (!recipe.id.trim()) add("error", "character", "Character ID が未設定です。");
  else if (!isValidCharacterId(recipe.id)) add("error", "character", `Character ID は snake_case (先頭英小文字、a-z 0-9 _) にしてください: "${recipe.id}"`);
  if (recipe.specVersion !== 1) add("error", "character", "Character Recipe の specVersion が 1 ではありません。");
  const base = recipe.body.assetId ?? "base_body";
  const baseEntry = library.byId[base];
  if (!baseEntry) add("error", "character", `Base Body がライブラリにありません: ${base}`);
  else if (baseEntry.metadata.type !== "base") add("error", "character", `Base Body の type が base ではありません: ${base}`);
  else if (!modelUrl(baseEntry)) add("error", "character", "Base Body に model GLB がありません。");
  if (baseEntry && !baseEntry.metadata.bodyTypes.includes(recipe.body.base))
    add("warning", "character", `Base Body が bodyType "${recipe.body.base}" 非対応です。`);

  // ---- Assets ----
  const seen = new Map<string, ExportAssetSlot[]>();
  for (const slot of EXPORT_ASSET_SLOTS) {
    const id = recipe.assets[slot];
    if (!id) continue;
    seen.set(id, [...(seen.get(id) ?? []), slot]);
    const entry = library.byId[id];
    if (!entry) { add("error", "assets", `${slot}: Asset "${id}" がライブラリにありません。`); continue; }
    const cats = SLOT_CATEGORY[slot];
    if (!cats.includes(entry.metadata.type)) add("warning", "assets", `${slot}: "${id}" の type (${entry.metadata.type}) が想定 (${cats.join(" / ")}) と異なります。`);
    if (!modelUrl(entry)) add("warning", "assets", `${slot}: "${id}" に model がありません。GLB には含まれません。`);
    if (!entry.metadata.bodyTypes.includes(recipe.body.base)) add("warning", "assets", `${slot}: "${id}" が bodyType "${recipe.body.base}" 非対応です。`);
    const socket = SLOT_SOCKET[slot];
    if (!baseSocketDefinitions.some((s) => s.id === socket)) add("error", "rig", `${slot}: Socket "${socket}" 定義がありません。`);
    if (!socketNodeName(socket)) add("error", "rig", `${slot}: Socket "${socket}" の親ノードが解決できません。`);
    if ((entry.metadata.type === "weapon") && !entry.metadata.equipment?.animationSet)
      add("info", "assets", `${slot}: "${id}" に animationSet がありません。default を使用します。`);
  }
  for (const [id, slots] of seen) if (slots.length > 1 && !(slots.length === 2 && slots.every((s) => s === "shoulderLeft" || s === "shoulderRight")))
    add("info", "assets", `Asset "${id}" が複数スロットで使用されています: ${slots.join(", ")}`);

  // Grip point info (spec section 7)
  const mainId = recipe.assets.mainHand;
  if (mainId && library.byId[mainId]) {
    const grip = library.byId[mainId].metadata.attachment?.main?.assetPoint;
    add("info", "assets", grip ? `Main Hand grip point: ${grip} → ${SLOT_SOCKET.mainHand}` : `Main Hand "${mainId}" に grip point 情報がありません（authored origin を使用）。`);
  }

  // ---- Animation set compatibility ----
  if (input.activeAnimationSet !== "default" && !(ANIMATION_SETS as readonly string[]).includes(input.activeAnimationSet))
    add("warning", "character", `activeAnimationSet "${input.activeAnimationSet}" が未知です。`);

  // ---- Scale ----
  for (const key of ["height", "bodyWidth", "headScale"] as const) {
    const v = recipe.body.scale[key];
    if (!Number.isFinite(v)) add("error", "scale", `body.scale.${key} が NaN / Infinity です。`);
    else if (v === 0) add("error", "scale", `body.scale.${key} が 0 です。`);
    else if (v < 0) add("error", "scale", `body.scale.${key} が負の値です。`);
    else if (v < SCALE_MIN || v > SCALE_MAX) add("warning", "scale", `body.scale.${key} (${v}) が許容範囲 ${SCALE_MIN}–${SCALE_MAX} 外です。非一様スケールで歪む可能性があります。`);
  }

  // ---- Texture / palette ----
  for (const slot of PALETTE_SLOTS) {
    if (!isHexColor(recipe.palette[slot])) add("error", "texture", `palette.${slot} が #RRGGBB ではありません: ${recipe.palette[slot]}`);
  }

  return items;
}

export const hasBlockingErrors = (items: readonly ExportIssue[]) => items.some((i) => i.level === "error");
export const countIssues = (items: readonly ExportIssue[]) => ({
  error: items.filter((i) => i.level === "error").length,
  warning: items.filter((i) => i.level === "warning").length,
  info: items.filter((i) => i.level === "info").length,
});
