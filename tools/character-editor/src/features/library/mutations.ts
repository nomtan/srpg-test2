"use client";

// Higher-level Library operations composed from the API client. Screens call these and then
// refreshLibrary().
import type { AssetMetadata } from "@/domain/asset";
import type { CharacterRecipe } from "@/domain/character-recipe";
import {
  bumpVersionHistory, newAssetRecord, newCharacterRecord,
  type AssetRecord, type CharacterRecord, type LibraryIndex,
} from "@/domain/library-index";
import { nextDuplicateId } from "@/domain/library-ids";
import { validateAssetRecord, validateCharacterRecord, toValidationState } from "@/domain/library-validation";
import { currentAssetVersionSnapshot } from "@/domain/library-stale";
import { registryEntryFor, upsertRegistryEntry, removeRegistryEntry } from "@/domain/library-registry";
import {
  copyFiles, dataUrlToBlob, putAssetRecord, putCharacterRecord, putFile, putRegistry,
} from "./api";

const now = () => new Date().toISOString();

// ---- Assets ----------------------------------------------------------------

export interface SaveAssetInput {
  metadata: AssetMetadata;
  modelBlob?: Blob | null;
  textureBlob?: Blob | null;
  thumbnailDataUrl?: string | null;
  /** Existing record, when updating in place. */
  existing?: AssetRecord | null;
  origin: AssetRecord["origin"];
  versionNote?: string;
}

/** Create-new vs update-existing (spec prompt 37-38). Updating bumps assetVersion + history. */
export async function saveAsset(input: SaveAssetInput): Promise<AssetRecord> {
  let record: AssetRecord;
  if (input.existing) {
    const { version, history } = bumpVersionHistory(
      input.existing.versionHistory,
      input.existing.metadata.assetVersion,
      input.versionNote ?? "metadata / files updated",
    );
    record = {
      ...input.existing,
      metadata: { ...input.metadata, assetVersion: version },
      updatedAt: now(),
    };
    record.versionHistory = history;
  } else {
    record = newAssetRecord(input.metadata, input.origin);
  }
  record.validation = toValidationState(validateAssetRecord(record));

  await putAssetRecord(record);
  if (input.modelBlob) await putFile("asset", record.metadata.id, "model.glb", input.modelBlob);
  if (input.textureBlob) await putFile("asset", record.metadata.id, "texture.png", input.textureBlob);
  if (input.thumbnailDataUrl) await putFile("asset", record.metadata.id, "thumbnail.png", await dataUrlToBlob(input.thumbnailDataUrl));
  return record;
}

/** Non-destructive copy (spec prompt 10-11): new id, copied files, fresh history. */
export async function duplicateAsset(source: AssetRecord, index: LibraryIndex): Promise<AssetRecord> {
  const taken = new Set(["base_body", ...index.assets.map((a) => a.metadata.id)]);
  const id = nextDuplicateId(source.metadata.id, taken);
  const metadata: AssetMetadata = { ...structuredCloneSafe(source.metadata), id, name: `${source.metadata.name} Copy`, assetVersion: 1 };
  const record = newAssetRecord(metadata, "creator");
  record.tags = [...source.tags];
  record.validation = toValidationState(validateAssetRecord(record));
  await putAssetRecord(record);
  await copyFiles("asset", source.metadata.id, id, ["model.glb", "texture.png", "thumbnail.png"]);
  return record;
}

export async function patchAsset(record: AssetRecord, patch: Partial<AssetRecord>): Promise<AssetRecord> {
  const next: AssetRecord = { ...record, ...patch, updatedAt: now() };
  next.validation = toValidationState(validateAssetRecord(next));
  await putAssetRecord(next);
  return next;
}

/** Explicit assetVersion bump for a "meaningful change" without a file swap (spec prompt 12). */
export async function bumpAssetVersion(record: AssetRecord, note: string): Promise<AssetRecord> {
  const { version, history } = bumpVersionHistory(record.versionHistory, record.metadata.assetVersion, note);
  return patchAsset(record, {
    metadata: { ...record.metadata, assetVersion: version },
    versionHistory: history,
  });
}

// ---- Characters ----------------------------------------------------------------

export async function saveCharacter(
  recipe: CharacterRecipe,
  name: string,
  index: LibraryIndex,
  origin: CharacterRecord["origin"] = "builder",
  thumbnailDataUrl?: string | null,
): Promise<CharacterRecord> {
  const existing = index.characters.find((c) => c.recipe.id === recipe.id);
  let record: CharacterRecord;
  if (existing) {
    const changedRecipe = JSON.stringify(existing.recipe) !== JSON.stringify(recipe);
    let history = existing.versionHistory;
    let characterVersion = existing.recipe.characterVersion ?? 1;
    if (changedRecipe) {
      const bump = bumpVersionHistory(history, characterVersion, "recipe updated");
      history = bump.history;
      characterVersion = bump.version;
    }
    record = {
      ...existing,
      recipe: { ...recipe, characterVersion },
      name: name.trim() || recipe.id,
      versionHistory: history,
      updatedAt: now(),
    };
  } else {
    record = newCharacterRecord(recipe, name, origin);
  }
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  record.validation = toValidationState(validateCharacterRecord(record, { assetsById }));
  await putCharacterRecord(record);
  if (thumbnailDataUrl) {
    record.thumbnail = true;
    await putFile("character", record.recipe.id, "thumbnail.png", await dataUrlToBlob(thumbnailDataUrl));
  }
  return record;
}

/** Duplicate the Character Recipe only — assets are shared, not copied (spec prompt 17). */
export async function duplicateCharacter(source: CharacterRecord, index: LibraryIndex): Promise<CharacterRecord> {
  const taken = new Set(index.characters.map((c) => c.recipe.id));
  const id = nextDuplicateId(source.recipe.id, taken);
  const recipe: CharacterRecipe = { ...structuredCloneSafe(source.recipe), id, characterVersion: 1 };
  const record = newCharacterRecord(recipe, `${source.name} Copy`, "builder");
  record.tags = [...source.tags];
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  record.validation = toValidationState(validateCharacterRecord(record, { assetsById }));
  await putCharacterRecord(record);
  return record;
}

export async function patchCharacter(record: CharacterRecord, patch: Partial<CharacterRecord>, index: LibraryIndex): Promise<CharacterRecord> {
  const next: CharacterRecord = { ...record, ...patch, updatedAt: now() };
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  next.validation = toValidationState(validateCharacterRecord(next, { assetsById }));
  await putCharacterRecord(next);
  return next;
}

// ---- Export + Registry integration (spec prompt 27-32) ----------------------------

export interface ExportOutcome {
  ok: boolean;
  activeAnimationSet: string | null;
  error?: string | null;
}

export async function recordCharacterExport(
  record: CharacterRecord,
  outcome: ExportOutcome,
  index: LibraryIndex,
  opts: { autoRegister?: boolean } = {},
): Promise<{ character: CharacterRecord; registered: boolean }> {
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  const nextRecord: CharacterRecord = { ...record, updatedAt: now() };
  if (outcome.ok) {
    nextRecord.export = {
      status: "up_to_date",
      exportedAt: now(),
      exportedCharacterVersion: record.recipe.characterVersion ?? 1,
      exportedAssetVersions: currentAssetVersionSnapshot(record, assetsById),
      activeAnimationSet: outcome.activeAnimationSet,
      lastError: null,
    };
  } else {
    nextRecord.export = { ...record.export, status: "export_error", lastError: outcome.error ?? "Export failed" };
  }
  nextRecord.validation = toValidationState(validateCharacterRecord(nextRecord, { assetsById }));

  let registered = false;
  if (outcome.ok && opts.autoRegister) {
    const reg = await registerCharacter(nextRecord, index.registry).catch(() => null);
    if (reg) { nextRecord.registry = reg.registry; registered = true; }
  }
  await putCharacterRecord(nextRecord);
  return { character: nextRecord, registered };
}

export async function registerCharacter(record: CharacterRecord, registryFile: LibraryIndex["registry"]) {
  const updated = upsertRegistryEntry(registryFile, registryEntryFor(record));
  await putRegistry(updated);
  const registry: CharacterRecord["registry"] = {
    status: "registered",
    registeredAt: now(),
    registeredCharacterVersion: record.recipe.characterVersion ?? 1,
    lastError: null,
  };
  const next: CharacterRecord = { ...record, registry, updatedAt: now() };
  await putCharacterRecord(next);
  return { registry, character: next, registryFile: updated };
}

export async function unregisterCharacter(record: CharacterRecord, registryFile: LibraryIndex["registry"]) {
  const updated = removeRegistryEntry(registryFile, record.recipe.id);
  await putRegistry(updated);
  const next: CharacterRecord = {
    ...record,
    registry: { status: "not_registered", registeredAt: null, registeredCharacterVersion: null, lastError: null },
    updatedAt: now(),
  };
  await putCharacterRecord(next);
  return updated;
}

// ---- Bulk validation (spec prompt 23-24) ----------------------------------

export interface BulkValidationResult {
  assets: { valid: number; warning: number; error: number };
  characters: { valid: number; warning: number; error: number };
}

export async function runBulkValidation(index: LibraryIndex, which: "assets" | "characters" | "both"): Promise<BulkValidationResult> {
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  const result: BulkValidationResult = { assets: { valid: 0, warning: 0, error: 0 }, characters: { valid: 0, warning: 0, error: 0 } };

  if (which !== "characters") {
    for (const a of index.assets) {
      const state = toValidationState(validateAssetRecord(a));
      result.assets[state.status === "unknown" ? "valid" : state.status]++;
      if (JSON.stringify(state.issues) !== JSON.stringify(a.validation.issues) || state.status !== a.validation.status) {
        await putAssetRecord({ ...a, validation: state });
      }
    }
  }
  if (which !== "assets") {
    for (const c of index.characters) {
      const state = toValidationState(validateCharacterRecord(c, { assetsById }));
      result.characters[state.status === "unknown" ? "valid" : state.status]++;
      if (JSON.stringify(state.issues) !== JSON.stringify(c.validation.issues) || state.status !== c.validation.status) {
        await putCharacterRecord({ ...c, validation: state });
      }
    }
  }
  return result;
}

function structuredCloneSafe<T>(value: T): T {
  return typeof structuredClone === "function" ? structuredClone(value) : JSON.parse(JSON.stringify(value));
}
