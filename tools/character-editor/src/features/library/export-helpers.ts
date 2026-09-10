"use client";

// Shared re-export helper (spec prompt 28-29): reuse the Phase 5 bake pipeline for a character
// record and persist the resulting export/registry state.
import { ANIMATION_SETS } from "@/domain/constants";
import type { CharacterRecipe } from "@/domain/character-recipe";
import type { AssetLibrary } from "@/features/asset-library/library";
import type { CharacterRecord, LibraryIndex } from "@/domain/library-index";
import { bakeCharacter, downloadBakeResult } from "@/features/character-builder/export/bake";
import { recordCharacterExport } from "./mutations";

export function activeAnimationSetFor(recipe: CharacterRecipe, library: AssetLibrary): string {
  const id = recipe.assets.mainHand;
  const set = id ? library.byId[id]?.metadata.equipment?.animationSet : undefined;
  return set && (ANIMATION_SETS as readonly string[]).includes(set) ? set : "default";
}

export interface ReexportOptions {
  autoRegister?: boolean;
  download?: boolean;
  onProgress?: (note: string) => void;
}

export async function reexportCharacter(
  record: CharacterRecord,
  library: AssetLibrary,
  index: LibraryIndex,
  opts: ReexportOptions = {},
): Promise<{ ok: boolean; message: string; registered: boolean }> {
  const activeAnimationSet = activeAnimationSetFor(record.recipe, library);
  try {
    const result = await bakeCharacter({
      recipe: record.recipe,
      name: record.name,
      activeAnimationSet,
      library,
      onProgress: (step, _i, note) => opts.onProgress?.(note ? `${step} — ${note}` : step),
    });
    if (opts.download) downloadBakeResult(result);
    const { registered } = await recordCharacterExport(
      record,
      { ok: true, activeAnimationSet: result.metadata.activeAnimationSet },
      index,
      { autoRegister: opts.autoRegister },
    );
    return { ok: true, message: `Export 完了: ${result.id}.glb`, registered };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await recordCharacterExport(record, { ok: false, activeAnimationSet, error: message }, index);
    return { ok: false, message: `Export 失敗: ${message}`, registered: false };
  }
}
