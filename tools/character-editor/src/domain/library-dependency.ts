// Dependency tracking (spec prompt 19-21). Character Recipe -> Asset ids, both directions,
// with missing-asset detection so the Character Library never breaks on a dangling id.
import type { CharacterRecipe } from "./character-recipe";
import type { AssetRecord, CharacterRecord } from "./library-index";
import { EXPORT_ASSET_SLOTS } from "./character-export";

export interface AssetRef {
  slot: string;
  assetId: string;
  missing: boolean;
}

/** Every asset id a recipe references: the base body plus each filled equipment slot. */
export function recipeAssetRefs(recipe: CharacterRecipe, known: Set<string>): AssetRef[] {
  const refs: AssetRef[] = [];
  const base = recipe.body.assetId;
  if (base && base !== "base_body") refs.push({ slot: "base", assetId: base, missing: !known.has(base) });
  for (const slot of EXPORT_ASSET_SLOTS) {
    const id = recipe.assets[slot];
    if (id) refs.push({ slot, assetId: id, missing: !known.has(id) });
  }
  return refs;
}

export interface DependencyGraph {
  /** character id -> the asset refs it uses (with missing flag). */
  byCharacter: Record<string, AssetRef[]>;
  /** asset id -> character ids that use it. */
  usedBy: Record<string, string[]>;
  /** character id -> missing asset ids. */
  missingByCharacter: Record<string, string[]>;
  knownAssetIds: Set<string>;
}

export function buildDependencyGraph(
  characters: readonly CharacterRecord[],
  assets: readonly AssetRecord[],
): DependencyGraph {
  const knownAssetIds = new Set<string>(["base_body", ...assets.map((a) => a.metadata.id)]);
  const byCharacter: Record<string, AssetRef[]> = {};
  const usedBy: Record<string, string[]> = {};
  const missingByCharacter: Record<string, string[]> = {};

  for (const character of characters) {
    const refs = recipeAssetRefs(character.recipe, knownAssetIds);
    byCharacter[character.recipe.id] = refs;
    const missing: string[] = [];
    for (const ref of refs) {
      (usedBy[ref.assetId] ??= []).push(character.recipe.id);
      if (ref.missing) missing.push(ref.assetId);
    }
    if (missing.length) missingByCharacter[character.recipe.id] = missing;
  }
  return { byCharacter, usedBy, missingByCharacter, knownAssetIds };
}

export function usageCount(graph: DependencyGraph, assetId: string): number {
  return graph.usedBy[assetId]?.length ?? 0;
}

export function usersOfAsset(graph: DependencyGraph, assetId: string): string[] {
  return graph.usedBy[assetId] ?? [];
}
