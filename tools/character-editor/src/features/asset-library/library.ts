import type { AssetId, AssetMetadata } from "@/domain/asset";
import type { AssetCategory, BodyType } from "@/domain/constants";

export interface AssetLibraryEntry {
  metadata: AssetMetadata;
  /** Browser-served directory, separate from portable asset.json paths. */
  baseUrl: string;
  provenance?: "source" | "demo" | "user";
  /** Pre-resolved URLs (data: URLs for user-saved assets); win over baseUrl joins. */
  resolved?: { model?: string; texture?: string; thumbnail?: string };
}
export interface AssetLibrary {
  ids: readonly AssetId[];
  byId: Readonly<Record<AssetId, AssetLibraryEntry>>;
}
export function createAssetLibrary(entries: readonly AssetLibraryEntry[]): AssetLibrary {
  const byId: Record<AssetId, AssetLibraryEntry> = Object.create(null);
  for (const entry of entries) {
    if (byId[entry.metadata.id]) throw new Error(`Duplicate asset ID: ${entry.metadata.id}`);
    byId[entry.metadata.id] = entry;
  }
  return { ids: entries.map(({ metadata }) => metadata.id), byId };
}
export function listAssets(library: AssetLibrary, filter: { category?: AssetCategory; bodyType?: BodyType } = {}) {
  return library.ids.map((id) => library.byId[id]).filter(({ metadata }) =>
    (!filter.category || metadata.type === filter.category) &&
    (!filter.bodyType || metadata.bodyTypes.includes(filter.bodyType)));
}
export function modelUrl(entry: AssetLibraryEntry): string | null {
  if (entry.resolved?.model) return entry.resolved.model;
  return entry.metadata.model ? `${entry.baseUrl.replace(/\/$/, "")}/${entry.metadata.model}` : null;
}
export function textureUrl(entry: AssetLibraryEntry): string | null {
  if (entry.resolved?.texture) return entry.resolved.texture;
  return entry.metadata.texture ? `${entry.baseUrl.replace(/\/$/, "")}/${entry.metadata.texture}` : null;
}
