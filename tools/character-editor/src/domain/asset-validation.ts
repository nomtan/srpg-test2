// Detect-and-report only: no auto-fix (spec sections 24-25). Every check returns a
// level so the UI can group Error / Warning / Info.
import { CHARACTER_SOCKETS, type CharacterSocket } from "./constants";
import {
  BASE_TEXTURE_SIZE, WEAPON_TEXTURE_SIZES, gripPointsFor, isWeapon, isSnakeCase,
  type AssetDraft,
} from "./asset-spec";

export type ValidationLevel = "error" | "warning" | "info";
export type ValidationSection = "metadata" | "model" | "texture" | "attachment";
export interface ValidationItem {
  level: ValidationLevel;
  section: ValidationSection;
  message: string;
}

export interface GlbStats {
  hasMesh: boolean;
  meshCount: number;
  materialCount: number;
  triangleCount: number;
  boundingBox: { min: [number, number, number]; max: [number, number, number]; size: [number, number, number] };
  nodeNames: string[];
  /** Phase 9: every mesh carries a UV set (checked by the production Validation Pipeline). */
  hasUv: boolean;
  meshesWithoutUv: number;
}
export interface TextureStats {
  width: number;
  height: number;
  hasAlpha: boolean;
}

export interface ValidationContext {
  existingIds: readonly string[];
  model: GlbStats | null;
  texture: TextureStats | null;
  /** Base character rest-pose size in metres (X, Y, Z). */
  baseSize: readonly [number, number, number];
  hasSourceFile: boolean;
}

const MAX_TRIANGLES = 4000;
const MAX_MATERIALS = 4;

export function validateDraft(draft: AssetDraft, ctx: ValidationContext): ValidationItem[] {
  const items: ValidationItem[] = [];
  const add = (level: ValidationLevel, section: ValidationSection, message: string) =>
    items.push({ level, section, message });

  // ---- Metadata ----
  if (!draft.name.trim()) add("error", "metadata", "Name が未入力です。");
  if (!draft.id.trim()) add("error", "metadata", "ID が未入力です。");
  else if (!isSnakeCase(draft.id)) add("error", "metadata", `ID は snake_case で入力してください: ${draft.id}`);
  else if (!/_\d{2,}$/.test(draft.id)) add("info", "metadata", "ID 末尾に連番 (例 _001) を付けると管理しやすくなります。");
  if (draft.id && ctx.existingIds.includes(draft.id)) add("error", "metadata", `ID が Asset Library 内で重複しています: ${draft.id}`);
  if (draft.bodyTypes.length === 0) add("error", "metadata", "Body Type を 1 つ以上選択してください。");
  if (!CHARACTER_SOCKETS.includes(draft.socket)) add("error", "metadata", `未定義の Socket: ${draft.socket}`);
  if (draft.paletteSlots.length === 0) add("warning", "metadata", "Palette Slot が未選択です。色変更ができません。");
  if (draft.type === "hair" && draft.paletteSlots.length && !draft.paletteSlots.includes("hair"))
    add("info", "metadata", "Hair は通常 palette slot 'hair' を含めます。");

  if (["headgear", "head_accessory"].includes(draft.type)) {
    if (!draft.hairPolicy) add("warning", "metadata", "Headgear / Head Accessory は hairPolicy (hide / overlay) を設定してください。");
  } else if (draft.hairPolicy) {
    add("info", "metadata", `${draft.type} で hairPolicy は無視されます。`);
  }

  if (isWeapon(draft.type)) {
    if (!draft.handling) add("error", "metadata", "Weapon Handling が未設定です。");
    if (!draft.animationSet) add("error", "metadata", "Animation Set が未設定です。");
    const expected = gripPointsFor(draft.handling);
    for (const grip of expected) {
      if (!draft.gripPoints.includes(grip))
        add("warning", "attachment", `${draft.handling} は ${grip} を必要とします。`);
    }
    if (draft.handling !== "two_hand" && draft.gripPoints.includes("grip_sub"))
      add("info", "attachment", "grip_sub は two_hand でのみ使用されます。");
  }

  // ---- Model ----
  if (!ctx.model) {
    add("warning", "model", "GLB Model が未 Import です。Preview / Validation が限定されます。");
  } else {
    const m = ctx.model;
    if (!m.hasMesh) add("error", "model", "GLB に表示可能な Mesh がありません。");
    add("info", "model", `Mesh ${m.meshCount} / Material ${m.materialCount} / 三角形 ${m.triangleCount.toLocaleString()}`);
    if (m.materialCount > MAX_MATERIALS) add("warning", "model", `Material 数が多いです (${m.materialCount} > ${MAX_MATERIALS})。`);
    // Without UVs a texture cannot map onto the mesh, so the Preview shows the untextured model
    // even though the PNG imported fine. Say so rather than leaving it a mystery.
    if (!m.hasUv) {
      add("warning", "model", ctx.texture
        ? `UV を持たない Mesh が ${m.meshesWithoutUv} 個あります。Texture は Preview / Runtime に反映されません。`
        : `UV を持たない Mesh が ${m.meshesWithoutUv} 個あります。Texture を適用できません。`);
    }
    if (m.triangleCount > MAX_TRIANGLES) add("warning", "model", `Polygon 数が多いです (${m.triangleCount} > ${MAX_TRIANGLES})。low-poly を維持してください。`);
    const [sx, sy, sz] = m.boundingBox.size;
    add("info", "model", `Bounding Box: ${sx.toFixed(3)} × ${sy.toFixed(3)} × ${sz.toFixed(3)} m`);
    if ([sx, sy, sz].some((v) => !Number.isFinite(v) || v <= 0)) add("error", "model", "Bounding Box が不正です。");
    const center = m.boundingBox.min.map((v, i) => v + m.boundingBox.size[i] / 2);
    if (Math.hypot(...center) > 3) add("warning", "model", `原点から離れています (center ≈ ${center.map((v) => v.toFixed(2)).join(", ")})。Pivot / Origin を確認してください。`);

    // ---- Attachment: bounding box vs base (spec section 25) ----
    const baseMax = Math.max(...ctx.baseSize);
    const assetMax = Math.max(sx, sy, sz);
    const ratio = assetMax / baseMax;
    if (ratio > 3) add("warning", "attachment", `Asset がベースキャラクターに対して約 ${ratio.toFixed(1)} 倍あります。スケールを確認してください。`);
    else if (ratio < 0.02) add("warning", "attachment", `Asset がベースキャラクターに対して極端に小さいです (約 ${(ratio * 100).toFixed(1)}%)。`);
    else add("info", "attachment", `Asset / Base 最大寸法比: ${(ratio * 100).toFixed(1)}%`);
  }

  // ---- Texture ----
  if (!ctx.texture) {
    add("warning", "texture", "Texture (PNG) が未 Import です。");
  } else {
    const t = ctx.texture;
    add("info", "texture", `Resolution: ${t.width} × ${t.height}${t.hasAlpha ? " (alpha あり)" : ""}`);
    const allowed = isWeapon(draft.type) ? (WEAPON_TEXTURE_SIZES as readonly number[]) : [BASE_TEXTURE_SIZE];
    if (t.width !== t.height) add("warning", "texture", "Texture が正方形ではありません。");
    if (!allowed.includes(t.width)) {
      const label = allowed.join(" / ");
      add(isWeapon(draft.type) ? "warning" : "warning", "texture", `Texture 解像度 ${t.width} は想定 (${label}) と異なります。`);
    }
    if (t.width !== draft.textureResolution)
      add("info", "texture", `フォーム指定 (${draft.textureResolution}) と Import 画像 (${t.width}) が一致していません。`);
  }

  // ---- Attachment: sockets / grip existence ----
  const sockets: CharacterSocket[] = [draft.socket];
  if (isWeapon(draft.type) && draft.handling === "two_hand") sockets.push("socket_hand_left");
  for (const socket of sockets) {
    if (!CHARACTER_SOCKETS.includes(socket)) add("error", "attachment", `Socket が存在しません: ${socket}`);
  }
  if (isWeapon(draft.type) && ctx.model) {
    for (const grip of draft.gripPoints) {
      const present = ctx.model.nodeNames.some((n) => n === grip || n.toLowerCase() === grip);
      add(present ? "info" : "warning", "attachment", present
        ? `Grip Point ノード ${grip} を検出しました。`
        : `GLB 内に Grip Point ノード ${grip} が見つかりません (authored_origin にフォールバック)。`);
    }
  }

  if (!ctx.hasSourceFile) add("info", "metadata", ".bbmodel Source 未添付 (任意)。");

  return items;
}

export const countByLevel = (items: readonly ValidationItem[]) => ({
  error: items.filter((i) => i.level === "error").length,
  warning: items.filter((i) => i.level === "warning").length,
  info: items.filter((i) => i.level === "info").length,
});
