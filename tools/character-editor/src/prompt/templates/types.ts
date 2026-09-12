import type { PromptContext } from "../promptTypes";

/** One Asset Type's slice of the prompt. Kept small so templates stay readable (spec section 26). */
export interface TypeTemplate {
  /** GEOMETRY requirements specific to this asset type. */
  geometry: (ctx: PromptContext) => string[];
  /** Asset-only isolation + type-specific prohibitions (spec section 8 / 34). */
  negatives: (ctx: PromptContext) => string[];
  /** Texture rules specific to this asset type (spec section 18-22). */
  texture: (ctx: PromptContext) => string[];
  /** Optional extra sections appended to the Model Prompt. */
  extraSections?: (ctx: PromptContext) => { title: string; lines: string[] }[];
}

/** "Generate only X; do not generate Y" (spec section 8). */
export const onlyThisAsset = (what: string, notThese: readonly string[]): string[] => [
  `Generate only the ${what} asset.`,
  ...notThese.map((n) => `Do not generate: ${n}`),
];
