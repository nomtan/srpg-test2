// Stale character detection (spec prompt 26-28). A character's Godot export goes stale when an
// asset it uses has a newer assetVersion than the one baked, when the recipe's asset set
// changed, or when the recipe's own characterVersion moved past the exported one.
import type { AssetRecord, CharacterRecord, CharacterExportStatus } from "./library-index";
import { recipeAssetRefs } from "./library-dependency";

export interface StaleAsset {
  assetId: string;
  exportedVersion: number | null;
  currentVersion: number | null;
  reason: "updated" | "added" | "removed" | "missing";
}

export interface ExportEvaluation {
  status: CharacterExportStatus;
  reasons: string[];
  staleAssets: StaleAsset[];
}

export function evaluateExport(
  character: CharacterRecord,
  assetsById: Map<string, AssetRecord>,
): ExportEvaluation {
  const ex = character.export;
  if (ex.status === "export_error") {
    return { status: "export_error", reasons: [ex.lastError ?? "前回の Export が失敗しています。"], staleAssets: [] };
  }
  if (!ex.exportedAt) {
    return { status: "not_exported", reasons: ["まだ Export されていません。"], staleAssets: [] };
  }

  const reasons: string[] = [];
  const staleAssets: StaleAsset[] = [];

  const currentVersion = character.recipe.characterVersion ?? 1;
  if (ex.exportedCharacterVersion != null && currentVersion > ex.exportedCharacterVersion) {
    reasons.push(`Character Recipe が更新されています (v${ex.exportedCharacterVersion} → v${currentVersion})。`);
  }

  const known = new Set<string>(["base_body", ...assetsById.keys()]);
  const currentRefs = recipeAssetRefs(character.recipe, known);
  const currentIds = new Set(currentRefs.map((r) => r.assetId));
  const exportedIds = new Set(Object.keys(ex.exportedAssetVersions));

  for (const ref of currentRefs) {
    const current = assetsById.get(ref.assetId)?.metadata.assetVersion ?? null;
    if (ref.missing) {
      staleAssets.push({ assetId: ref.assetId, exportedVersion: ex.exportedAssetVersions[ref.assetId] ?? null, currentVersion: null, reason: "missing" });
      reasons.push(`使用中の Asset ${ref.assetId} が存在しません。`);
      continue;
    }
    if (!exportedIds.has(ref.assetId)) {
      staleAssets.push({ assetId: ref.assetId, exportedVersion: null, currentVersion: current, reason: "added" });
      reasons.push(`Asset ${ref.assetId} が Export 後に追加されました。`);
      continue;
    }
    const exported = ex.exportedAssetVersions[ref.assetId];
    if (current != null && exported != null && current > exported) {
      staleAssets.push({ assetId: ref.assetId, exportedVersion: exported, currentVersion: current, reason: "updated" });
      reasons.push(`${ref.assetId} v${exported} → v${current}`);
    }
  }
  for (const id of exportedIds) {
    if (!currentIds.has(id)) {
      staleAssets.push({ assetId: id, exportedVersion: ex.exportedAssetVersions[id], currentVersion: assetsById.get(id)?.metadata.assetVersion ?? null, reason: "removed" });
      reasons.push(`Asset ${id} が Recipe から外されました。`);
    }
  }

  const status: CharacterExportStatus = reasons.length ? "reexport_required" : "up_to_date";
  return { status, reasons, staleAssets };
}

/** assetVersions snapshot for the current recipe, to store on a successful export. */
export function currentAssetVersionSnapshot(
  character: CharacterRecord,
  assetsById: Map<string, AssetRecord>,
): Record<string, number> {
  const known = new Set<string>(["base_body", ...assetsById.keys()]);
  const snap: Record<string, number> = {};
  for (const ref of recipeAssetRefs(character.recipe, known)) {
    if (ref.missing) continue;
    snap[ref.assetId] = assetsById.get(ref.assetId)?.metadata.assetVersion ?? 1;
  }
  return snap;
}
