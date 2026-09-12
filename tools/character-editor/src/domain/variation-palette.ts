// Phase 8 Palette Sets (spec section 17-19). Colour is never a free RGB roll: every palette slot
// draws from a curated list, either the Palette Set of the faction or the global Skin / Hair pools.
// The whole structure is user-editable and persisted as library-data/palette-sets.json.
import { PALETTE_SLOTS, type PaletteSlot } from "./constants";
import { isHexColor } from "./phase3";

export interface PaletteSet {
  id: string;
  name: string;
  /** Candidate colours per slot. An empty list falls back to the global pool / the recipe default. */
  colors: Record<PaletteSlot, string[]>;
}

export interface PaletteLibrary {
  specVersion: 1;
  updatedAt: string;
  sets: PaletteSet[];
  /** Shared natural pools (spec section 19); used whenever a set leaves skin / hair empty. */
  skinPool: string[];
  hairPool: string[];
}

export const DEFAULT_SKIN_POOL = [
  "#f3d3bd", "#e8bda0", "#d8aa85", "#c08e6a", "#a9734f", "#8a5a3b", "#6b4430",
];

export const DEFAULT_HAIR_POOL = [
  "#1d1613", "#36251c", "#4a3527", "#6b4a2f", "#8a6a3d", "#b79b63", "#d9c38a",
  "#7a3b2a", "#5a5a63", "#cfd3d8",
];

function set(id: string, name: string, colors: Partial<Record<PaletteSlot, string[]>>): PaletteSet {
  const full = Object.fromEntries(PALETTE_SLOTS.map((s) => [s, [...(colors[s] ?? [])]])) as Record<PaletteSlot, string[]>;
  return { id, name, colors: full };
}

/** Seeded on first run; every value stays editable in the Palette Sets tab. */
export const BUILTIN_PALETTE_SETS: PaletteSet[] = [
  set("kingdom", "Kingdom", {
    primary: ["#263f70", "#314f82", "#1f3560"],
    secondary: ["#d8d8d8", "#a8a8a8", "#c3c9d1"],
    metal: ["#929292", "#b0b0b0", "#7f8a95"],
    leather: ["#6b4a2f", "#5a3b26", "#7d5a3a"],
  }),
  set("empire", "Empire", {
    primary: ["#5c1f24", "#71272c", "#43171b"],
    secondary: ["#2c2c30", "#3c3c42", "#1f1f23"],
    metal: ["#8b8f96", "#a3a7ad", "#6f757d"],
    leather: ["#4a2f21", "#5d3c29", "#38241a"],
  }),
  set("elf", "Elf", {
    primary: ["#2f5d46", "#3b7256", "#254c39"],
    secondary: ["#d6cfae", "#c2b994", "#e3ddc4"],
    metal: ["#b9ad7a", "#cfc496", "#9c9166"],
    leather: ["#6e5a37", "#836c44", "#57462b"],
    hair: ["#d9c38a", "#b79b63", "#cfd3d8", "#8a6a3d"],
  }),
  set("villager", "Villager", {
    primary: ["#7a6a4f", "#8a7a5c", "#6a5a42", "#95795a"],
    secondary: ["#c9bda3", "#b3a68c", "#ded4bd"],
    metal: ["#8a8a8a", "#9a9a9a"],
    leather: ["#6b4a2f", "#7d5a3a", "#5a3b26"],
  }),
  set("bandit", "Bandit", {
    primary: ["#4a3a2c", "#5b4736", "#3a2d23", "#63452c"],
    secondary: ["#3c3a36", "#4d4a44", "#2b2a27"],
    metal: ["#7d7d7d", "#8f8f8f", "#6a6a6a"],
    leather: ["#4a2f21", "#3a251a", "#5d3c29"],
  }),
];

export function defaultPaletteLibrary(): PaletteLibrary {
  return {
    specVersion: 1,
    updatedAt: new Date().toISOString(),
    sets: BUILTIN_PALETTE_SETS.map((s) => ({ ...s, colors: { ...s.colors } })),
    skinPool: [...DEFAULT_SKIN_POOL],
    hairPool: [...DEFAULT_HAIR_POOL],
  };
}

const cleanColors = (input: unknown): string[] => {
  if (!Array.isArray(input)) return [];
  return [...new Set(input.filter((c): c is string => isHexColor(c)).map((c) => c.toLowerCase()))];
};

export function normalizePaletteLibrary(input: unknown): PaletteLibrary {
  const fallback = defaultPaletteLibrary();
  if (!input || typeof input !== "object") return fallback;
  const raw = input as Record<string, unknown>;
  const sets = Array.isArray(raw.sets)
    ? raw.sets
        .filter((s): s is Record<string, unknown> => !!s && typeof s === "object")
        .map((s): PaletteSet => {
          const colorsRaw = (s.colors ?? {}) as Record<string, unknown>;
          return {
            id: String(s.id ?? "").trim() || "set",
            name: String(s.name ?? s.id ?? "Set"),
            colors: Object.fromEntries(
              PALETTE_SLOTS.map((slot) => [slot, cleanColors(colorsRaw[slot])]),
            ) as Record<PaletteSlot, string[]>,
          };
        })
    : fallback.sets;
  const skinPool = cleanColors(raw.skinPool);
  const hairPool = cleanColors(raw.hairPool);
  return {
    specVersion: 1,
    updatedAt: typeof raw.updatedAt === "string" ? raw.updatedAt : new Date().toISOString(),
    sets: sets.length ? sets : fallback.sets,
    skinPool: skinPool.length ? skinPool : fallback.skinPool,
    hairPool: hairPool.length ? hairPool : fallback.hairPool,
  };
}

export function findPaletteSet(library: PaletteLibrary, id: string): PaletteSet | null {
  return library.sets.find((s) => s.id === id) ?? null;
}

/**
 * Candidate colours for one slot: the set's own list, then the global pool for skin / hair.
 * Returns [] when nothing is defined — the generator then keeps the recipe's default colour.
 */
export function paletteCandidates(library: PaletteLibrary, setId: string, slot: PaletteSlot): string[] {
  const set = findPaletteSet(library, setId);
  const own = set?.colors[slot] ?? [];
  if (own.length) return own;
  if (slot === "skin") return library.skinPool;
  if (slot === "hair") return library.hairPool;
  return [];
}
