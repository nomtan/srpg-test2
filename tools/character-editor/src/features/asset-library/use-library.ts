"use client";

import { useMemo } from "react";
import { assetLibrary } from "./asset-library";
import { createAssetLibrary, type AssetLibrary, type AssetLibraryEntry } from "./library";
import { useUserAssets, type UserAsset } from "./user-assets";

function toEntry(asset: UserAsset): AssetLibraryEntry {
  return {
    metadata: asset.metadata,
    baseUrl: "",
    provenance: "user",
    resolved: { model: asset.model, texture: asset.texture, thumbnail: asset.thumbnail },
  };
}

/** Static library (base + demo) merged with localStorage user assets. */
export function useMergedLibrary(): AssetLibrary {
  const userAssets = useUserAssets();
  return useMemo(() => {
    const staticEntries = assetLibrary.ids.map((id) => assetLibrary.byId[id]);
    const userIds = new Set(userAssets.map((a) => a.metadata.id));
    const merged = [
      ...staticEntries.filter((e) => !userIds.has(e.metadata.id)),
      ...userAssets.map(toEntry),
    ];
    return createAssetLibrary(merged);
  }, [userAssets]);
}
