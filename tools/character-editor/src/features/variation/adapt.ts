"use client";

// Bridge from the merged Asset Library (static base + demo + Phase 7 library-data) to the
// framework-free CandidateAsset view the Phase 8 generator works on. Only metadata and a
// thumbnail URL cross this line — no GLB is fetched to build a candidate list (spec section 35).
import type { AssetLibrary } from "@/features/asset-library/library";
import { modelUrl, thumbnailUrl } from "@/features/asset-library/library";
import type { CandidateAsset } from "@/domain/variation-candidates";

export function candidatesFromLibrary(library: AssetLibrary): CandidateAsset[] {
  return library.ids.map((id) => {
    const entry = library.byId[id];
    const m = entry.metadata;
    return {
      id: m.id,
      name: m.name,
      type: m.type,
      bodyTypes: [...m.bodyTypes],
      tags: [...(m.tags ?? [])],
      rarity: m.rarity,
      weight: m.weight,
      weaponType: m.equipment?.weaponType,
      handling: m.equipment?.handling,
      animationSet: m.equipment?.animationSet,
      hairPolicy: m.hairPolicy,
      hideParts: [...m.hideParts],
      socket: m.attachment?.main?.characterSocket,
      hasModel: modelUrl(entry) !== null,
      thumbnailUrl: thumbnailUrl(entry),
    } satisfies CandidateAsset;
  });
}

/** Every tag present in the library, for the preset editor's tag pickers. */
export function libraryTags(assets: readonly CandidateAsset[]): string[] {
  return [...new Set(assets.flatMap((a) => a.tags))].sort();
}
