import type { AssetId } from "./asset";
import type { CharacterGeneration } from "./character-generation";
import type { BodyPreset, BodyType, PaletteSlot, RecipeSlot } from "./constants";

export interface BodyScale { height: number; bodyWidth: number; headScale: number }
export interface CharacterRecipe {
  specVersion: 1;
  /** Optional for compatibility with the example in specification section 15. */
  assetVersion?: number;
  /** Phase 5: re-export revision counter (spec section 24 / prompt 17). */
  characterVersion?: number;
  id: string;
  body: {
    base: BodyType;
    preset: BodyPreset;
    scale: BodyScale;
    /** Optional concrete base asset, beyond the body's adult/child classification. */
    assetId?: AssetId;
  };
  assets: Partial<Record<RecipeSlot, AssetId | null>>;
  palette: Record<PaletteSlot, string>;
  /** Phase 8: present only for Variation Generator output (spec section 32). */
  generation?: CharacterGeneration;
}
