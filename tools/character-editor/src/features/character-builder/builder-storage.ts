"use client";

// Character Builder handoff storage. Shared by the Builder itself (auto-save of the working
// recipe) and by the Character Library / Variation Generator, which stage a saved character for
// manual editing (spec section 48: auto-generate -> Character Builder -> hand tweak).
import type { CharacterRecipe } from "@/domain/character-recipe";
import { recipeText } from "@/domain/builder-recipe";

export const BUILDER_RECIPE_KEY = "srpg-character-editor/builder-recipe/v1";
export const BUILDER_NAME_KEY = "srpg-character-editor/builder-name/v1";

/** Write a recipe into the Builder's working slot. Returns false if storage is unavailable. */
export function stageRecipeForBuilder(recipe: CharacterRecipe, name: string): boolean {
  try {
    window.localStorage.setItem(BUILDER_RECIPE_KEY, recipeText(recipe));
    window.localStorage.setItem(BUILDER_NAME_KEY, name);
    return true;
  } catch {
    return false;
  }
}

export function readStagedName(fallback: string): string {
  try {
    return window.localStorage.getItem(BUILDER_NAME_KEY) || fallback;
  } catch {
    return fallback;
  }
}
