import type { AssetDraft, AssetType, GripPoint } from "@/domain/asset-spec";

export interface PromptContext {
  draft: AssetDraft;
  type: AssetType;
  name: string;
  id: string;
  description: string;
  bodyTypes: string[];
  socket: string;
  gripPoints: GripPoint[];
  paletteSlots: string[];
  textureResolution: number;
  isWeapon: boolean;
  handling: string | null;
  animationSet: string | null;
  weaponType: string | null;
  hairPolicy: string | null;
}

export interface GeneratedPrompts {
  model: string;
  texture: string;
}

export const TARGET_GAME = "SRPG (isometric tactics, Godot runtime)";
export const BASE_MODEL_PATH = "assets/characters/base/base_1.bbmodel";

/** Base rest-pose size in metres, from the generated base body analysis. */
export const BASE_MODEL_SIZE_METERS = { x: 0.5833, y: 1.8454, z: 1.2157 };

export const COORD_SYSTEM = {
  up: "+Y",
  forward: "+X",
  left: "+Z",
  unit: "1 unit = 1 metre (Godot scale 1.0), base authored in Blockbench at 1/12 scale",
};
