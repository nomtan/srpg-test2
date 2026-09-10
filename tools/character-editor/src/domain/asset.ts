import type { AnimationSet, AssetCategory, BodyType, CharacterSocket, EquipmentSlot, HairPolicy, PaletteSlot, WeaponHandling, WeaponType } from "./constants";

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
  /** Search / filter / future NPC generation tags (spec prompt 5). */
  tags?: string[];
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
}
