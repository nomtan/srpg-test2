// Phase 8 generation provenance (spec section 32 / 49). Attached to a CharacterRecipe only when
// the character came out of the Variation Generator; hand-built characters have no `generation`.
export interface CharacterGeneration {
  type: "variation";
  /** Variation Preset id the character was rolled from. */
  preset: string;
  /** Batch seed. preset + seed + asset library state reproduce the same batch (spec section 20). */
  seed: number;
  /** Position inside the batch; part of the per-character RNG stream. */
  index: number;
  /** Reroll counter for this single character (spec section 26). 0 = first roll. */
  salt: number;
  presetVersion: number;
  generatedAt: string;
  /** Set once the character is edited by hand so a regenerate does not silently discard it. */
  modified?: boolean;
}

export function markGenerationModified(generation: CharacterGeneration | undefined): CharacterGeneration | undefined {
  if (!generation || generation.modified) return generation;
  return { ...generation, modified: true };
}

/** Structural check for a `generation` block read back from JSON. Unknown shapes are dropped. */
export function parseGeneration(input: unknown): CharacterGeneration | undefined {
  if (!input || typeof input !== "object") return undefined;
  const g = input as Record<string, unknown>;
  if (g.type !== "variation") return undefined;
  if (typeof g.preset !== "string" || !g.preset) return undefined;
  const num = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? v : fallback);
  return {
    type: "variation",
    preset: g.preset,
    seed: Math.floor(num(g.seed, 0)),
    index: Math.floor(num(g.index, 0)),
    salt: Math.floor(num(g.salt, 0)),
    presetVersion: Math.floor(num(g.presetVersion, 1)),
    generatedAt: typeof g.generatedAt === "string" ? g.generatedAt : new Date(0).toISOString(),
    ...(g.modified === true ? { modified: true } : {}),
  };
}
