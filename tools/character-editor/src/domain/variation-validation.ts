// Phase 8 preset validation + feasibility (spec section 43-45).
// Run before generating: an impossible rule set must be reported up front, never discovered by an
// unbounded retry loop inside the generator.
import { isSnakeCase } from "./asset-spec";
import { PALETTE_SLOTS } from "./constants";
import { isHexColor } from "./phase3";
import { buildPool, emptyContext, type CandidateAsset } from "./variation-candidates";
import { findPaletteSet, paletteCandidates, type PaletteLibrary } from "./variation-palette";
import {
  SLOT_ORDER, VARIATION_SCALE_MAX, VARIATION_SCALE_MIN, MAX_COUNT, MIN_COUNT,
  type VariationPreset, type VariationSlot,
} from "./variation-preset";
import { SLOT_LABEL } from "./builder-recipe";

export interface PresetIssue {
  level: "error" | "warning" | "info";
  code: string;
  message: string;
  slot?: VariationSlot;
}

export interface PresetValidationContext {
  assets: readonly CandidateAsset[];
  palettes: PaletteLibrary;
  /** Every other preset id, for the duplicate-id check. */
  otherPresetIds: readonly string[];
}

export interface PresetValidationResult {
  issues: PresetIssue[];
  /** Candidate count per slot, for the preset editor's live counters. */
  poolSizes: Record<VariationSlot, number>;
  canGenerate: boolean;
}

export function validatePreset(preset: VariationPreset, ctx: PresetValidationContext): PresetValidationResult {
  const issues: PresetIssue[] = [];
  const add = (level: PresetIssue["level"], code: string, message: string, slot?: VariationSlot) =>
    issues.push({ level, code, message, slot });

  // ---- identity ----
  if (!preset.id.trim()) add("error", "id", "Preset ID が空です。");
  else if (!isSnakeCase(preset.id)) add("error", "id", `Preset ID が snake_case ではありません: ${preset.id}`);
  if (ctx.otherPresetIds.includes(preset.id)) add("error", "id_duplicate", `Preset ID が重複しています: ${preset.id}`);
  if (!preset.name.trim()) add("warning", "name", "Name が未設定です。");
  if (!preset.idPrefix.trim()) add("warning", "idPrefix", "Character ID Prefix が未設定です。Preset ID を使用します。");

  // ---- count ----
  if (preset.count < MIN_COUNT || preset.count > MAX_COUNT) {
    add("error", "count", `Count は ${MIN_COUNT} - ${MAX_COUNT} の範囲で指定してください（現在 ${preset.count}）。`);
  }

  // ---- body ----
  if (preset.bodyTypes.length === 0) add("error", "bodyTypes", "Body Type が 1 つも選択されていません。");
  for (const [key, range] of [
    ["Height", preset.bodyScale.height], ["Body Width", preset.bodyScale.bodyWidth], ["Head Scale", preset.bodyScale.headScale],
  ] as const) {
    if (range.min > range.max) add("error", "scale_range", `${key} の min (${range.min}) が max (${range.max}) を超えています。`);
    if (range.min < VARIATION_SCALE_MIN || range.max > VARIATION_SCALE_MAX) {
      add("warning", "scale_extreme", `${key} が安全範囲 ${VARIATION_SCALE_MIN} - ${VARIATION_SCALE_MAX} の外です。生成時にクランプされます。`);
    }
  }

  // ---- palette ----
  if (!findPaletteSet(ctx.palettes, preset.palette.setId)) {
    add("error", "palette_set", `Palette Set が見つかりません: ${preset.palette.setId}`);
  } else {
    for (const slot of PALETTE_SLOTS) {
      const rule = preset.palette.slots[slot];
      if (rule.mode === "fixed" && !isHexColor(rule.fixed)) {
        add("error", "palette_fixed", `palette.${slot} の fixed 色が #RRGGBB ではありません。`);
      }
      if (rule.mode !== "fixed" && paletteCandidates(ctx.palettes, preset.palette.setId, slot).length === 0) {
        add("warning", "palette_empty", `palette.${slot} の候補色が空です。Recipe 既定色を使用します。`);
      }
    }
  }

  // ---- per-slot rules + candidate feasibility ----
  const poolSizes = Object.fromEntries(SLOT_ORDER.map((s) => [s, 0])) as Record<VariationSlot, number>;
  const bodyType = preset.bodyTypes[0] ?? "adult";
  const baseCtx = emptyContext(bodyType, preset.genderExpression);
  let twoHandOnlyMain = false;
  let anyMainCandidate = false;

  for (const slot of SLOT_ORDER) {
    const rule = preset.slots[slot];
    if (rule.probability < 0 || rule.probability > 1) {
      add("error", "probability", `${SLOT_LABEL[slot]} の Probability は 0 - 1 で指定してください（現在 ${rule.probability}）。`, slot);
    }
    if (rule.presence === "forbidden") continue;

    const pool = buildPool(ctx.assets, slot, rule, baseCtx);
    poolSizes[slot] = pool.candidates.length;

    if (slot === "mainHand") {
      anyMainCandidate = pool.candidates.length > 0;
      twoHandOnlyMain = anyMainCandidate && pool.candidates.every((c) => c.asset.handling === "two_hand");
    }

    if (pool.candidates.length === 0) {
      const why = Object.entries(pool.rejected).map(([r, n]) => `${r} × ${n}`).join(", ");
      const detail = why ? `（除外理由: ${why}）` : "（該当カテゴリの Asset がありません）";
      if (rule.presence === "required") {
        add("error", "no_candidate", `required の ${SLOT_LABEL[slot]} に候補 Asset が 0 件です${detail}。`, slot);
      } else {
        add("warning", "no_candidate", `${SLOT_LABEL[slot]} に候補 Asset が 0 件です${detail}。常に未装備になります。`, slot);
      }
    }
  }

  // ---- impossible combinations (spec section 44) ----
  if (preset.slots.offHand.presence === "required") {
    if (preset.slots.mainHand.presence !== "forbidden" && twoHandOnlyMain) {
      add("error", "impossible", "Main Hand の候補が Two Hand 武器のみですが Off Hand が required です。両立しません。", "offHand");
    }
    if (preset.slots.mainHand.presence === "required" && !anyMainCandidate) {
      add("error", "impossible", "Main Hand が required ですが候補がありません。Off Hand の required も満たせません。", "mainHand");
    }
  }
  const mainWeaponTypes = preset.slots.mainHand.weaponTypes;
  if (preset.slots.offHand.presence === "required" && mainWeaponTypes.length > 0) {
    const onlyTwoHand = mainWeaponTypes.every((w) => w === "bow" || w === "great_sword" || w === "spear" || w === "staff");
    if (onlyTwoHand) {
      add("error", "impossible", `Weapon Type 制限 (${mainWeaponTypes.join(" / ")}) は両手武器のみですが Off Hand が required です。`, "offHand");
    }
  }
  if (preset.shoulderMode === "symmetric") {
    const left = poolSizes.shoulderLeft;
    const right = poolSizes.shoulderRight;
    if (left > 0 && right === 0) {
      add("warning", "symmetric", "Symmetric Only ですが右肩の候補がありません。右肩は常に未装備になります。", "shoulderRight");
    }
  }
  if (preset.genderExpression !== "any" && ctx.assets.every((a) => a.tags.every((t) => t !== preset.genderExpression))) {
    add("info", "gender", `Gender Expression "${preset.genderExpression}" のタグを持つ Asset がありません。Style タグの無い Asset のみで生成します。`);
  }

  const canGenerate = !issues.some((i) => i.level === "error");
  return { issues, poolSizes, canGenerate };
}

export function countIssues(issues: readonly PresetIssue[]) {
  return {
    errors: issues.filter((i) => i.level === "error").length,
    warnings: issues.filter((i) => i.level === "warning").length,
  };
}
