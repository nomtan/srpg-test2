"use client";

// Client-side derivations over the Library Index: dependency graph, per-character export/stale
// evaluation, registry sync diff, dashboard counters, and the list search / filter / sort used
// by the Asset & Character Library screens.
import type { AssetRecord, CharacterRecord, LibraryIndex, ValidationStatus } from "@/domain/library-index";
import { buildDependencyGraph, type DependencyGraph } from "@/domain/library-dependency";
import { evaluateExport, type ExportEvaluation } from "@/domain/library-stale";
import { diffRegistry, type RegistrySyncReport } from "@/domain/library-registry";
import type { WeaponType } from "@/domain/constants";

export interface DerivedLibrary {
  assetsById: Map<string, AssetRecord>;
  charactersById: Map<string, CharacterRecord>;
  graph: DependencyGraph;
  exportEval: Map<string, ExportEvaluation>;
  registrySync: RegistrySyncReport;
  dashboard: {
    assets: number;
    characters: number;
    validationErrors: number;
    reexportRequired: number;
    registryIssues: number;
    missingDependencies: number;
    /** Phase 8: characters produced by the Variation Generator (spec section 31). */
    generatedCharacters: number;
    /** Phase 9: production jobs, and the two states that need a human next (spec section 54). */
    productionJobs: number;
    productionAwaitingAction: number;
  };
  recentAssets: AssetRecord[];
  recentCharacters: CharacterRecord[];
}

export function deriveLibrary(index: LibraryIndex): DerivedLibrary {
  const assetsById = new Map(index.assets.map((a) => [a.metadata.id, a]));
  const charactersById = new Map(index.characters.map((c) => [c.recipe.id, c]));
  const graph = buildDependencyGraph(index.characters, index.assets);

  const exportEval = new Map<string, ExportEvaluation>();
  for (const c of index.characters) exportEval.set(c.recipe.id, evaluateExport(c, assetsById));

  const registrySync = diffRegistry(index.characters, index.registry);

  const byUpdated = <T extends { updatedAt: string }>(list: readonly T[]) =>
    [...list].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));

  return {
    assetsById,
    charactersById,
    graph,
    exportEval,
    registrySync,
    dashboard: {
      assets: index.assets.length,
      characters: index.characters.length,
      validationErrors:
        index.assets.filter((a) => a.validation.status === "error").length +
        index.characters.filter((c) => c.validation.status === "error").length,
      reexportRequired: [...exportEval.values()].filter((e) => e.status === "reexport_required").length,
      registryIssues: registrySync.issueCount,
      missingDependencies: Object.keys(graph.missingByCharacter).length,
      generatedCharacters: index.characters.filter((c) => !!c.recipe.generation).length,
      productionJobs: index.productions.length,
      productionAwaitingAction: index.productions.filter(
        (p) => p.status === "validation_error" || p.status === "needs_revision",
      ).length,
    },
    recentAssets: byUpdated(index.assets).slice(0, 6),
    recentCharacters: byUpdated(index.characters).slice(0, 6),
  };
}

// ---- Asset category filter tree (spec section 3) ----------------------------------
export interface CategoryNode {
  id: string;
  label: string;
  /** asset metadata.type values this node covers; empty = weapon subtype filter. */
  types?: string[];
  weaponType?: WeaponType;
  indent?: boolean;
}

export const ASSET_CATEGORY_TREE: CategoryNode[] = [
  { id: "all", label: "All" },
  { id: "hair", label: "Hair", types: ["hair"] },
  { id: "headgear", label: "Headgear", types: ["headgear"] },
  { id: "head_accessory", label: "Head Accessory", types: ["head_accessory"] },
  { id: "chest_armor", label: "Armor", types: ["chest_armor"] },
  { id: "shoulder", label: "Shoulder", types: ["shoulder_left", "shoulder_right"] },
  { id: "gloves", label: "Gloves", types: ["gloves", "arm_armor"] },
  { id: "waist", label: "Waist", types: ["waist"] },
  { id: "boots", label: "Boots", types: ["boots"] },
  { id: "weapon", label: "Weapon", types: ["weapon"] },
  { id: "weapon:sword", label: "Sword", weaponType: "sword", indent: true },
  { id: "weapon:great_sword", label: "Great Sword", weaponType: "great_sword", indent: true },
  { id: "weapon:spear", label: "Spear", weaponType: "spear", indent: true },
  { id: "weapon:bow", label: "Bow", weaponType: "bow", indent: true },
  { id: "weapon:dagger", label: "Dagger", weaponType: "dagger", indent: true },
  { id: "weapon:staff", label: "Staff", weaponType: "staff", indent: true },
  { id: "shield", label: "Shield", types: ["shield"] },
  { id: "back", label: "Back", types: ["back"] },
];

export function assetMatchesCategory(rec: AssetRecord, nodeId: string): boolean {
  if (nodeId === "all") return true;
  const node = ASSET_CATEGORY_TREE.find((n) => n.id === nodeId);
  if (!node) return true;
  if (node.weaponType) return rec.metadata.type === "weapon" && rec.metadata.equipment?.weaponType === node.weaponType;
  return !!node.types?.includes(rec.metadata.type);
}

// ---- Search ----------------------------------
export function searchAssets(records: readonly AssetRecord[], query: string): AssetRecord[] {
  const q = query.trim().toLowerCase();
  if (!q) return [...records];
  return records.filter((r) => {
    const m = r.metadata;
    return (
      m.id.toLowerCase().includes(q) ||
      m.name.toLowerCase().includes(q) ||
      m.type.toLowerCase().includes(q) ||
      r.tags.some((t) => t.includes(q))
    );
  });
}

export function searchCharacters(records: readonly CharacterRecord[], query: string): CharacterRecord[] {
  const q = query.trim().toLowerCase();
  if (!q) return [...records];
  return records.filter((r) =>
    r.recipe.id.toLowerCase().includes(q) ||
    r.name.toLowerCase().includes(q) ||
    r.tags.some((t) => t.includes(q)),
  );
}

// ---- Sort ----------------------------------
export const ASSET_SORTS = ["Newest", "Oldest", "Name", "Type", "Version", "Validation Status"] as const;
export type AssetSort = (typeof ASSET_SORTS)[number];

const STATUS_ORDER: Record<ValidationStatus, number> = { error: 0, warning: 1, unknown: 2, valid: 3 };

export function sortAssets(records: readonly AssetRecord[], sort: AssetSort): AssetRecord[] {
  const list = [...records];
  switch (sort) {
    case "Newest": return list.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    case "Oldest": return list.sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
    case "Name": return list.sort((a, b) => a.metadata.name.localeCompare(b.metadata.name));
    case "Type": return list.sort((a, b) => a.metadata.type.localeCompare(b.metadata.type) || a.metadata.name.localeCompare(b.metadata.name));
    case "Version": return list.sort((a, b) => b.metadata.assetVersion - a.metadata.assetVersion);
    case "Validation Status": return list.sort((a, b) => STATUS_ORDER[a.validation.status] - STATUS_ORDER[b.validation.status]);
  }
}

export const CHARACTER_SORTS = ["Newest", "Oldest", "Name", "Export Status", "Version"] as const;
export type CharacterSort = (typeof CHARACTER_SORTS)[number];

export function sortCharacters(
  records: readonly CharacterRecord[],
  sort: CharacterSort,
  exportEval: Map<string, ExportEvaluation>,
): CharacterRecord[] {
  const list = [...records];
  const exportOrder = { export_error: 0, reexport_required: 1, not_exported: 2, up_to_date: 3 } as const;
  switch (sort) {
    case "Newest": return list.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
    case "Oldest": return list.sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
    case "Name": return list.sort((a, b) => a.name.localeCompare(b.name));
    case "Version": return list.sort((a, b) => (b.recipe.characterVersion ?? 1) - (a.recipe.characterVersion ?? 1));
    case "Export Status":
      return list.sort(
        (a, b) =>
          exportOrder[exportEval.get(a.recipe.id)?.status ?? "not_exported"] -
          exportOrder[exportEval.get(b.recipe.id)?.status ?? "not_exported"],
      );
  }
}

export function allTags(records: readonly { tags: string[] }[]): string[] {
  return [...new Set(records.flatMap((r) => r.tags))].sort();
}
