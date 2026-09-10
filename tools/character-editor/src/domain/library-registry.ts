// Character Registry sync (spec prompt 30-32). library-data/registry.json is the mirror of the
// Godot-side character registry; Godot imports characters listed here. This module diffs the
// Character Library against that file so both drift directions are visible.
import type { CharacterRecord, RegistryEntry, RegistryFile } from "./library-index";

export function registryEntryFor(record: CharacterRecord, at = new Date().toISOString()): RegistryEntry {
  return {
    id: record.recipe.id,
    name: record.name,
    characterVersion: record.recipe.characterVersion ?? 1,
    model: `${record.recipe.id}.glb`,
    activeAnimationSet: record.export.activeAnimationSet,
    registeredAt: at,
  };
}

export function upsertRegistryEntry(file: RegistryFile, entry: RegistryEntry): RegistryFile {
  const entries = file.entries.filter((e) => e.id !== entry.id);
  entries.push(entry);
  entries.sort((a, b) => a.id.localeCompare(b.id));
  return { ...file, updatedAt: new Date().toISOString(), entries };
}

export function removeRegistryEntry(file: RegistryFile, id: string): RegistryFile {
  return { ...file, updatedAt: new Date().toISOString(), entries: file.entries.filter((e) => e.id !== id) };
}

export interface RegistrySyncReport {
  /** Library characters with no registry entry. */
  missingInRegistry: string[];
  /** Registry entries with no matching library character (spec prompt 32). */
  unknownInRegistry: string[];
  /** id -> {library, registry} where characterVersion differs. */
  versionMismatch: { id: string; libraryVersion: number; registryVersion: number }[];
  issueCount: number;
}

export function diffRegistry(characters: readonly CharacterRecord[], file: RegistryFile): RegistrySyncReport {
  const byId = new Map(file.entries.map((e) => [e.id, e]));
  const libIds = new Set(characters.map((c) => c.recipe.id));

  const missingInRegistry: string[] = [];
  const versionMismatch: RegistrySyncReport["versionMismatch"] = [];
  for (const c of characters) {
    const entry = byId.get(c.recipe.id);
    if (!entry) { missingInRegistry.push(c.recipe.id); continue; }
    const libVer = c.recipe.characterVersion ?? 1;
    if (entry.characterVersion !== libVer) {
      versionMismatch.push({ id: c.recipe.id, libraryVersion: libVer, registryVersion: entry.characterVersion });
    }
  }
  const unknownInRegistry = file.entries.filter((e) => !libIds.has(e.id)).map((e) => e.id);

  return {
    missingInRegistry,
    unknownInRegistry,
    versionMismatch,
    issueCount: missingInRegistry.length + unknownInRegistry.length + versionMismatch.length,
  };
}
