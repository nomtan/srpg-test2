// Library-level validation (spec prompt 22-25). This is metadata / dependency validation only —
// it does not load GLBs. The Asset Creator's validateDraft() still owns the deep mesh / texture
// checks at authoring time; here we re-check what can be known from the index alone.
import { isSnakeCase, gripPointsFor } from "./asset-spec";
import { isHexColor } from "./phase3";
import { PALETTE_SLOTS } from "./constants";
import type { AssetRecord, CharacterRecord, LibIssue, ValidationState } from "./library-index";
import { rollUpStatus } from "./library-index";
import { recipeAssetRefs } from "./library-dependency";
import { evaluateExport } from "./library-stale";

export function validateAssetRecord(record: AssetRecord): LibIssue[] {
  const issues: LibIssue[] = [];
  const m = record.metadata;
  const add = (level: LibIssue["level"], code: string, message: string) => issues.push({ level, code, message });

  if (!m.id || !isSnakeCase(m.id)) add("error", "id", `Asset ID が snake_case ではありません: ${m.id || "(空)"}`);
  if (!m.name?.trim()) add("warning", "name", "Name が未設定です。");
  if (!m.bodyTypes?.length && m.type !== "texture") add("warning", "bodyTypes", "Body Type が未設定です。");
  if (m.type !== "texture" && !record.files.model && !m.model) add("error", "model", "model.glb がありません。Export できません。");
  if (m.type !== "texture" && !record.files.thumbnail && !m.thumbnail) add("info", "thumbnail", "Thumbnail が未生成です。");
  if (m.appearance.paletteSlots.length === 0 && !["texture", "base"].includes(m.type)) add("warning", "palette", "Palette Slot が未設定です（色変更ができません）。");

  if (m.type === "weapon") {
    const handling = m.equipment?.handling;
    if (!handling) add("error", "weapon", "Weapon handling が未設定です。");
    if (!m.equipment?.animationSet) add("warning", "weapon", "Animation Set が未設定です。");
    if (handling) {
      const needed = gripPointsFor(handling);
      const points = [m.attachment?.main?.assetPoint, m.attachment?.sub?.assetPoint].filter(Boolean) as string[];
      for (const grip of needed) {
        if (!points.includes(grip)) add("warning", "grip", `${handling} は attachment ${grip} を必要とします。`);
      }
    }
  }
  if (["headgear", "head_accessory"].includes(m.type) && !m.hairPolicy) {
    add("warning", "hairPolicy", "Headgear / Head Accessory は hairPolicy (hide / overlay) を設定してください。");
  }
  return issues;
}

export interface CharacterValidationContext {
  assetsById: Map<string, AssetRecord>;
}

export function validateCharacterRecord(record: CharacterRecord, ctx: CharacterValidationContext): LibIssue[] {
  const issues: LibIssue[] = [];
  const add = (level: LibIssue["level"], code: string, message: string, targetId?: string) =>
    issues.push({ level, code, message, targetId });
  const recipe = record.recipe;

  if (!recipe.id || !isSnakeCase(recipe.id)) add("error", "id", `Character ID が snake_case ではありません: ${recipe.id || "(空)"}`);

  // Palette
  for (const slot of PALETTE_SLOTS) {
    if (!isHexColor(recipe.palette?.[slot])) add("error", "palette", `palette.${slot} が #RRGGBB ではありません。`);
  }

  const known = new Set<string>(["base_body", ...ctx.assetsById.keys()]);
  const refs = recipeAssetRefs(recipe, known);

  // Missing assets (spec prompt 21)
  for (const ref of refs) {
    if (ref.missing) { add("error", "missing", `Missing Asset: ${ref.slot} → ${ref.assetId}`, ref.assetId); continue; }
    const asset = ctx.assetsById.get(ref.assetId);
    if (!asset) continue;
    // BodyType compatibility (spec prompt 25)
    if (ref.slot !== "base" && asset.metadata.bodyTypes.length && !asset.metadata.bodyTypes.includes(recipe.body.base)) {
      add("warning", "bodyType", `${ref.assetId} は bodyType ${asset.metadata.bodyTypes.join("/")} 用で、この Character は ${recipe.body.base} です。`, ref.assetId);
    }
    if (ref.slot !== "base" && !asset.files.model && !asset.metadata.model) {
      add("error", "assetModel", `${ref.assetId} に model.glb がなく Export できません。`, ref.assetId);
    }
  }

  // Weapon handling / socket compatibility (spec prompt 25)
  const mainId = recipe.assets.mainHand;
  const offId = recipe.assets.offHand;
  const mainHandling = mainId ? ctx.assetsById.get(mainId)?.metadata.equipment?.handling : undefined;
  if (mainHandling === "two_hand" && offId) {
    add("warning", "handling", "Main Hand が two_hand なのに Off Hand が装備されています（干渉します）。");
  }

  // Animation set resolvable
  const animSet = mainId ? ctx.assetsById.get(mainId)?.metadata.equipment?.animationSet : undefined;
  if (mainId && !animSet) add("info", "animationSet", "Main Hand 武器に animationSet がなく default を使用します。");

  // Export possible?
  const evalResult = evaluateExport(record, ctx.assetsById);
  if (evalResult.status === "reexport_required") add("warning", "stale", `Re-export required: ${evalResult.reasons[0] ?? ""}`);
  if (evalResult.status === "export_error") add("error", "export", `前回 Export エラー: ${record.export.lastError ?? ""}`);

  return issues;
}

export function toValidationState(issues: LibIssue[], at = new Date().toISOString()): ValidationState {
  return { status: rollUpStatus(issues), checkedAt: at, issues };
}

export interface BulkCounts {
  valid: number;
  warning: number;
  error: number;
  unknown: number;
}

export function countStatuses(records: readonly { validation: ValidationState }[]): BulkCounts {
  const c: BulkCounts = { valid: 0, warning: 0, error: 0, unknown: 0 };
  for (const r of records) c[r.validation.status]++;
  return c;
}
