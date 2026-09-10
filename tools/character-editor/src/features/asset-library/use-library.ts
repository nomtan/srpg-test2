"use client";

import { useMemo } from "react";
import { assetLibrary } from "./asset-library";
import { createAssetLibrary, type AssetLibrary, type AssetLibraryEntry } from "./library";
import { useUserAssets, type UserAsset } from "./user-assets";
import { useLibraryIndex } from "@/features/library/use-library-index";
import { libFileUrl } from "@/features/library/api";
import type { AssetRecord } from "@/domain/library-index";

function toEntry(asset: UserAsset): AssetLibraryEntry {
  return {
    metadata: asset.metadata,
    baseUrl: "",
    provenance: "user",
    resolved: { model: asset.model, texture: asset.texture, thumbnail: asset.thumbnail },
  };
}

/** Phase 7 filesystem asset -> library entry, files served from the local library API. */
function fsToEntry(record: AssetRecord): AssetLibraryEntry {
  const id = record.metadata.id;
  return {
    metadata: record.metadata,
    baseUrl: "",
    provenance: "user",
    resolved: {
      model: record.files.model ? libFileUrl("asset", id, "model.glb") : undefined,
      texture: record.files.texture ? libFileUrl("asset", id, "texture.png") : undefined,
      thumbnail: record.files.thumbnail ? libFileUrl("asset", id, "thumbnail.png") : undefined,
    },
  };
}

/**
 * Static library (base + demo) merged with the Phase 7 filesystem library and, as a legacy
 * fallback, localStorage user assets. Filesystem entries win over localStorage on id clash.
 */
export function useMergedLibrary(): AssetLibrary {
  const userAssets = useUserAssets();
  const { index } = useLibraryIndex();
  return useMemo(() => {
    const staticEntries = assetLibrary.ids.map((id) => assetLibrary.byId[id]);
    const fsEntries = index.assets.map(fsToEntry);
    const fsIds = new Set(index.assets.map((a) => a.metadata.id));
    const userIds = new Set(userAssets.map((a) => a.metadata.id));
    const merged = [
      ...staticEntries.filter((e) => !userIds.has(e.metadata.id) && !fsIds.has(e.metadata.id)),
      ...userAssets.filter((a) => !fsIds.has(a.metadata.id)).map(toEntry),
      ...fsEntries,
    ];
    return createAssetLibrary(merged);
  }, [userAssets, index]);
}
