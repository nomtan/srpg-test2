import type { AnimationSet, AssetCategory, AssetRarity, BodyType, CharacterSocket, EquipmentSlot, HairPolicy, PaletteSlot, WeaponHandling, WeaponType } from "./constants";

export type AssetId = string;
export type RuntimeAssetPath = `${string}.glb`;
export interface SourceAsset { format: "bbmodel"; path: `${string}.bbmodel` }
export interface AttachmentPoint {
  /** Named node in the asset; grip_main / grip_sub for weapons. */
  assetPoint: string;
  characterSocket: CharacterSocket;
}
export interface AssetMetadata {
  specVersion: 1;
  assetVersion: number;
  id: AssetId;
  name: string;
  /** Optional free-text note surfaced in Asset Detail (spec section 7). */
  description?: string;
  type: AssetCategory;
  bodyTypes: BodyType[];
  /** Search / filter / Variation Generator tags (spec prompt 5). */
  tags?: string[];
  /** Phase 8 optional draw rate. `weight` wins over `rarity`; both are optional (spec section 9-10). */
  rarity?: AssetRarity;
  weight?: number;
  equipment?: {
    slot: EquipmentSlot;
    handling?: WeaponHandling;
    animationSet?: AnimationSet;
    weaponType?: WeaponType;
  };
  attachment?: { main: AttachmentPoint; sub?: AttachmentPoint };
  appearance: { paletteSlots: PaletteSlot[] };
  hairPolicy: HairPolicy | null;
  /** Names remain open until the base model migration establishes a part map. */
  hideParts: string[];
  /** Relative to the asset directory; texture-only assets need no model. */
  model?: RuntimeAssetPath;
  texture?: string;
  thumbnail?: string;
  /** Optional source reference; never loaded by the browser preview. */
  source?: SourceAsset;
  /** Phase 9 production provenance (spec section 49). Absent for hand-made assets. */
  production?: AssetProduction;
}

/** How an asset was produced. Deliberately provider-agnostic (spec section 49 / 57). */
export interface AssetProduction {
  method: "ai_assisted" | "manual";
  /** Production revision the approved files came from. */
  revision: number;
  status: "approved";
  /** Prompt Template version used (spec section 50). */
  promptVersion: number;
  producedAt: string;
}
