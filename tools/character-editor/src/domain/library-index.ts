// Phase 7 management layer. The Library Index is a thin record wrapper around the Phase 4/5
// artefacts (AssetMetadata, CharacterRecipe). It never replaces the file-based assets — it
// tracks tags, versions, validation state, dependency-derived status and registry state so a
// few hundred assets stay searchable without loading every GLB (spec prompt 41-49).
import type { AssetMetadata } from "./asset";
import type { CharacterRecipe } from "./character-recipe";

export type ValidationStatus = "valid" | "warning" | "error" | "unknown";

export const VALIDATION_BADGE: Record<ValidationStatus, string> = {
  valid: "✓ Valid",
  warning: "⚠ Warning",
  error: "✕ Error",
  unknown: "? Not Validated",
};

export interface LibIssue {
  level: "error" | "warning" | "info";
  code: string;
  message: string;
  /** Optional related id (asset id for a missing dependency, etc). */
  targetId?: string;
}

export function rollUpStatus(issues: readonly LibIssue[]): ValidationStatus {
  if (issues.some((i) => i.level === "error")) return "error";
  if (issues.some((i) => i.level === "warning")) return "warning";
  return "valid";
}

/** Minimal version tracking (spec prompt 13): current + previous + timestamp, diff-ready later. */
export interface VersionHistoryItem {
  version: number;
  previousVersion: number | null;
  updatedAt: string;
  note?: string;
}

export interface ValidationState {
  status: ValidationStatus;
  checkedAt: string | null;
  issues: LibIssue[];
}

export function unknownValidation(): ValidationState {
  return { status: "unknown", checkedAt: null, issues: [] };
}

export interface AssetFileFlags {
  model: boolean;
  texture: boolean;
  thumbnail: boolean;
  source: string | null;
}

export interface AssetRecord {
  kind: "asset";
  metadata: AssetMetadata;
  tags: string[];
  favorite: boolean;
  validation: ValidationState;
  versionHistory: VersionHistoryItem[];
  createdAt: string;
  updatedAt: string;
  files: AssetFileFlags;
  origin: "creator" | "import" | "seed";
}

export type CharacterExportStatus =
  | "not_exported"
  | "up_to_date"
  | "reexport_required"
  | "export_error";

export const EXPORT_STATUS_LABEL: Record<CharacterExportStatus, string> = {
  not_exported: "Not Exported",
  up_to_date: "Up To Date",
  reexport_required: "Re-export Required",
  export_error: "Export Error",
};

export type RegistryStatus = "registered" | "not_registered" | "registry_error";

export const REGISTRY_STATUS_LABEL: Record<RegistryStatus, string> = {
  registered: "Registered",
  not_registered: "Not Registered",
  registry_error: "Registry Error",
};

export interface CharacterExportState {
  status: CharacterExportStatus;
  exportedAt: string | null;
  exportedCharacterVersion: number | null;
  /** assetId -> assetVersion captured at export time, for stale detection (spec prompt 26). */
  exportedAssetVersions: Record<string, number>;
  activeAnimationSet: string | null;
  lastError: string | null;
}

export function freshExportState(): CharacterExportState {
  return {
    status: "not_exported",
    exportedAt: null,
    exportedCharacterVersion: null,
    exportedAssetVersions: {},
    activeAnimationSet: null,
    lastError: null,
  };
}

export interface CharacterRegistryState {
  status: RegistryStatus;
  registeredAt: string | null;
  registeredCharacterVersion: number | null;
  lastError: string | null;
}

export function freshRegistryState(): CharacterRegistryState {
  return { status: "not_registered", registeredAt: null, registeredCharacterVersion: null, lastError: null };
}

export interface CharacterRecord {
  kind: "character";
  recipe: CharacterRecipe;
  name: string;
  tags: string[];
  favorite: boolean;
  validation: ValidationState;
  versionHistory: VersionHistoryItem[];
  createdAt: string;
  updatedAt: string;
  thumbnail: boolean;
  export: CharacterExportState;
  registry: CharacterRegistryState;
  origin: "builder" | "import";
}

export interface RegistryEntry {
  id: string;
  name: string;
  characterVersion: number;
  model: string;
  activeAnimationSet: string | null;
  registeredAt: string;
}

export interface RegistryFile {
  specVersion: 1;
  updatedAt: string;
  entries: RegistryEntry[];
}

export function emptyRegistryFile(): RegistryFile {
  return { specVersion: 1, updatedAt: new Date().toISOString(), entries: [] };
}

export interface LibraryIndex {
  assets: AssetRecord[];
  characters: CharacterRecord[];
  registry: RegistryFile;
}

export function emptyLibraryIndex(): LibraryIndex {
  return { assets: [], characters: [], registry: emptyRegistryFile() };
}

/** Push a new version onto the history and return the next version number. */
export function bumpVersionHistory(
  history: readonly VersionHistoryItem[],
  currentVersion: number,
  note: string,
  at = new Date().toISOString(),
): { version: number; history: VersionHistoryItem[] } {
  const version = currentVersion + 1;
  const item: VersionHistoryItem = { version, previousVersion: currentVersion, updatedAt: at, note };
  return { version, history: [...history, item] };
}

export function initialHistory(version: number, at = new Date().toISOString()): VersionHistoryItem[] {
  return [{ version, previousVersion: null, updatedAt: at, note: "created" }];
}

export function newAssetRecord(metadata: AssetMetadata, origin: AssetRecord["origin"], files: Partial<AssetFileFlags> = {}): AssetRecord {
  const now = new Date().toISOString();
  return {
    kind: "asset",
    metadata,
    tags: [],
    favorite: false,
    validation: unknownValidation(),
    versionHistory: initialHistory(metadata.assetVersion, now),
    createdAt: now,
    updatedAt: now,
    files: { model: false, texture: false, thumbnail: false, source: null, ...files },
    origin,
  };
}

export function newCharacterRecord(recipe: CharacterRecipe, name: string, origin: CharacterRecord["origin"]): CharacterRecord {
  const now = new Date().toISOString();
  const version = recipe.characterVersion ?? 1;
  return {
    kind: "character",
    recipe,
    name: name.trim() || recipe.id,
    tags: [],
    favorite: false,
    validation: unknownValidation(),
    versionHistory: initialHistory(version, now),
    createdAt: now,
    updatedAt: now,
    thumbnail: false,
    export: freshExportState(),
    registry: freshRegistryState(),
    origin,
  };
}
