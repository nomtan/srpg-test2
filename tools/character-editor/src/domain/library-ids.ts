// Duplicate / tag id helpers (spec prompt 10-11, 43-44). IDs are stable once used: renaming the
// display name and changing the id are separate operations, and Phase 7 does not implement id
// change at all (prompt 44) — dependency rewrites are out of scope, so the id is write-once.
import { isSnakeCase } from "./asset-spec";

const TRAILING_NUM = /_(\d+)$/;

/** Next free "…_NNN" id for a duplicate. Keeps zero-padding width; falls back to "_copy". */
export function nextDuplicateId(baseId: string, taken: Iterable<string>): string {
  const set = new Set(taken);
  const match = baseId.match(TRAILING_NUM);
  if (match) {
    const width = match[1].length;
    const stem = baseId.slice(0, match.index);
    for (let n = Number(match[1]) + 1; n < Number(match[1]) + 1000; n++) {
      const candidate = `${stem}_${String(n).padStart(width, "0")}`;
      if (!set.has(candidate)) return candidate;
    }
  }
  for (let n = 2; n < 1000; n++) {
    const candidate = `${baseId}_copy${n === 2 ? "" : n}`;
    if (!set.has(candidate)) return candidate;
  }
  return `${baseId}_copy_${Date.now()}`;
}

export function normalizeTag(raw: string): string {
  return raw.trim().toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_-]/g, "");
}

export function addTag(tags: readonly string[], raw: string): string[] {
  const tag = normalizeTag(raw);
  if (!tag || tags.includes(tag)) return [...tags];
  return [...tags, tag].sort();
}

export function removeTag(tags: readonly string[], tag: string): string[] {
  return tags.filter((t) => t !== tag);
}

export function isValidNewId(id: string, taken: Iterable<string>): boolean {
  return isSnakeCase(id) && !new Set(taken).has(id);
}
