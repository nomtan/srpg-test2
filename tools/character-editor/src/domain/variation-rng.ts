// Phase 8 deterministic RNG (spec section 20-21). Character generation must be reproducible from
// (preset, seed, asset library state) alone, so nothing here touches Math.random: every draw comes
// from a named stream hashed out of the seed. Streams are per (seed, preset, index, salt, field),
// which gives two properties the generator needs:
//   - rerolling character 007 cannot shift characters 001-006 (spec section 26)
//   - locking Hair and rerolling Weapon cannot change the locked field (spec section 27)

/** FNV-1a 32-bit. Stable across runs and platforms; not a security hash. */
export function hashString(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** mulberry32: small, fast, well-distributed for UI-scale batches. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class Rng {
  private readonly next01: () => number;
  constructor(seed: number) { this.next01 = mulberry32(seed); }

  next(): number { return this.next01(); }

  /** Uniform float in [min, max]. */
  float(min: number, max: number): number {
    if (!(max > min)) return min;
    return min + this.next01() * (max - min);
  }

  /** Uniform integer in [min, max] inclusive. */
  int(min: number, max: number): number {
    if (max <= min) return min;
    return min + Math.floor(this.next01() * (max - min + 1));
  }

  chance(probability: number): boolean {
    if (probability <= 0) return false;
    if (probability >= 1) return true;
    return this.next01() < probability;
  }

  pick<T>(list: readonly T[]): T | null {
    if (list.length === 0) return null;
    return list[Math.min(list.length - 1, Math.floor(this.next01() * list.length))];
  }

  /**
   * Weighted draw (spec section 9). Non-positive weights are skipped entirely; if every weight is
   * non-positive the draw falls back to a uniform pick so a mis-tagged library never dead-ends.
   */
  pickWeighted<T>(list: readonly T[], weightOf: (item: T) => number): T | null {
    if (list.length === 0) return null;
    let total = 0;
    for (const item of list) {
      const w = weightOf(item);
      if (Number.isFinite(w) && w > 0) total += w;
    }
    if (total <= 0) return this.pick(list);
    let roll = this.next01() * total;
    for (const item of list) {
      const w = weightOf(item);
      if (!Number.isFinite(w) || w <= 0) continue;
      roll -= w;
      if (roll <= 0) return item;
    }
    return list[list.length - 1];
  }
}

/** Named sub-stream. Same parts -> same sequence, always. */
export function streamRng(...parts: (string | number)[]): Rng {
  return new Rng(hashString(parts.join("|")));
}

/** UI-only helper behind the "Generate New Seed" button (spec section 21). */
export function randomSeed(): number {
  return Math.floor(Math.random() * 1_000_000_000);
}

export function normalizeSeed(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.abs(Math.floor(n)) % 1_000_000_000;
}
