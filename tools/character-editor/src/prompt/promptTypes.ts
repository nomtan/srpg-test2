import type { AssetDraft, AssetType, GripPoint } from "@/domain/asset-spec";
import type { PaletteSlot } from "@/domain/constants";
import type { AlphaPolicy, AttachmentSpec, BudgetDefinition, BudgetProfile } from "@/domain/production-profile";
import type { MeasuredBox, MeasuredSocket } from "@/domain/base-measurements";
import type { ProductionReference } from "@/domain/production-job";

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

  // ---- Phase 9 production context ----------------------------------------------------
  /** Prompt Template version (spec section 50). */
  promptVersion: number;
  hideParts: string[];
  attachment: AttachmentSpec;
  budget: BudgetDefinition & { profile: BudgetProfile };
  alphaPolicy: AlphaPolicy;
  /** Measured socket transform from the Phase 2 mapping (spec section 15). */
  socketInfo: MeasuredSocket | null;
  /** Base body regions the asset has to fit, with measured boxes (spec section 12). */
  fitRegions: { region: string; box: MeasuredBox }[];
  /** Regions the asset must stay clear of. */
  clearanceRegions: string[];
  /** Recommended overall length for weapons, derived from the measured character height. */
  weaponLength: { min: number; max: number } | null;
  /** Palette slot -> current reference hex (spec section 21); guidance, not a fixed colour. */
  paletteReference: Partial<Record<PaletteSlot, string>>;
  references: ProductionReference[];
  animationTest: { set: string; roles: string[] };
  /** Asset directory category, for the repository path the delivery folder lands at. */
  categoryDir: string;
  /** The exact asset.json the delivery must ship, embedded so nothing is re-typed by hand. */
  assetJson: string;
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
  // forward x left = up requires +X x -Z = +Y, so the character's left is -Z.
  left: "-Z",
  right: "+Z",
  unit: "1 unit = 1 metre (Godot scale 1.0), base authored in Blockbench at 1/12 scale",
};
