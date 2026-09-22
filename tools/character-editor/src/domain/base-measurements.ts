// Phase 9: measured dimensions of the official base body, for AI Production Packages.
//
// The numbers come from `npm run build:measurements`, which re-walks base_1.bbmodel's Outliner
// (via the Phase 2 analysis) with the Phase 5 normalization — 1/12 m per source unit, +Y up,
// +X forward, +Z left. Phase 9 introduces NO new scale rule; it only reports what is already
// there so a prompt can say "the head is 0.58 m wide" instead of "use an appropriate size".
import measurements from "../../public/generated-assets/base_body/measurements.json";
import type { CharacterSocket, WeaponType } from "./constants";
import type { AssetType } from "./asset-spec";

export type Vec3 = [number, number, number];

export interface MeasuredBox {
  min: number[];
  max: number[];
  size: number[];
  center: number[];
}

export interface MeasuredSocket {
  parent: string;
  parentUuid: string;
  /**
   * Offset from the parent node, in the parent's local frame (metres). This is the attachment
   * point: Phase 2 left it at [0,0,0] (the group's rotation pivot), which is up to 0.53 m away
   * from the body part the socket serves. `build:measurements` now calibrates it.
   */
  position: number[];
  rotation: number[];
  scale: number[];
  space: string;
  status: string;
  /** Rest-pose world position of the attachment point, in metres. */
  worldPosition: number[];
  /** The measured body region the socket is calibrated against. */
  region?: string | null;
  /** Where Phase 2 anchored it — the parent group's rotation pivot. Traceability only. */
  pivotWorldPosition?: number[];
}

export type BaseRegion = keyof typeof measurements.regions;

const asBox = (value: unknown) => value as MeasuredBox;

export const BASE_MEASUREMENTS = measurements;
export const BASE_SOURCE_PATH = measurements.source.path;
export const BASE_CHARACTER = measurements.character;
export const BASE_COORDINATE_INFO = measurements.coordinates;

export const baseRegion = (region: BaseRegion): MeasuredBox =>
  asBox((measurements.regions as Record<string, unknown>)[region]);

export const baseRegionOrNull = (region: string): MeasuredBox | null =>
  region in measurements.regions ? asBox((measurements.regions as Record<string, unknown>)[region]) : null;

export const baseSocket = (socket: CharacterSocket): MeasuredSocket | null =>
  ((measurements.sockets as Record<string, MeasuredSocket>)[socket] ?? null);

export const recommendedWeaponLength = (weaponType: WeaponType) =>
  (measurements.recommendedLength as Record<string, { min: number; max: number; ratioOfCharacterHeight: number[] }>)[weaponType] ?? null;

/**
 * Body regions an asset type has to fit against. Used both for the "asset dimensions" block in
 * the Model Prompt (spec section 12) and for the import-time clipping check (spec section 44).
 */
export const FIT_REGIONS: Record<AssetType, BaseRegion[]> = {
  hair: ["head"],
  headgear: ["head"],
  head_accessory: ["head"],
  chest_armor: ["torso"],
  shoulder_left: ["shoulder_left"],
  shoulder_right: ["shoulder_right"],
  arm_armor: ["forearm_right"],
  gloves: ["hand_right"],
  waist: ["pelvis"],
  boots: ["ankle_right"],
  weapon: ["hand_right"],
  shield: ["hand_left"],
  back: ["torso"],
};

/**
 * How much larger than its fit region an asset should read, as a multiplier on the region's
 * bounding box.
 *
 * 1.0 means "sits on the region at its size" and is right for anything that follows the body
 * closely. Armour that is *worn over* a part has to overhang it, and a prompt that only quotes the
 * bare body measurement produces a piece the same size as the limb — which reads as too small.
 * Shoulder pauldrons are the clearest case, so they carry a real coverage factor.
 *
 * Only change a value with a produced asset to point at: this number goes straight into the
 * Model Prompt as a target size in metres.
 */
export const TYPE_COVERAGE: Record<AssetType, number> = {
  hair: 1,
  headgear: 1,
  head_accessory: 1,
  chest_armor: 1,
  // A pauldron sits over the shoulder and overhangs it; 1x reads as a shoulder pad, not armour.
  shoulder_left: 1.5,
  shoulder_right: 1.5,
  arm_armor: 1,
  gloves: 1,
  waist: 1,
  boots: 1,
  weapon: 1,
  shield: 1,
  back: 1,
};

/** The size an asset should aim for: its fit region scaled by the coverage factor. */
export function targetSizeFor(type: AssetType): { region: BaseRegion; size: number[]; coverage: number } | null {
  const region = FIT_REGIONS[type][0];
  const box = region ? baseRegion(region) : null;
  if (!box) return null;
  const coverage = TYPE_COVERAGE[type];
  return { region, coverage, size: box.size.map((v) => Math.round(v * coverage * 1e4) / 1e4) };
}

/** Regions the asset must stay clear of; a bounding-box overlap becomes a clipping warning. */
export const CLEARANCE_REGIONS: Record<AssetType, BaseRegion[]> = {
  hair: [],
  headgear: [],
  head_accessory: ["head"],
  chest_armor: ["head", "neck"],
  shoulder_left: ["head", "neck"],
  shoulder_right: ["head", "neck"],
  arm_armor: ["torso"],
  gloves: [],
  waist: ["torso"],
  boots: ["thigh_right"],
  weapon: ["torso", "head"],
  shield: ["torso", "head"],
  back: ["head", "shoulder_left", "shoulder_right"],
};

/** Human-readable dimension lines for the prompt / technical spec. */
export function fitDimensionLines(type: AssetType): string[] {
  const lines: string[] = [];
  for (const region of FIT_REGIONS[type]) {
    const box = baseRegion(region);
    if (!box) continue;
    lines.push(
      `${region}: size ${box.size.join(" x ")} m, centre ${box.center.join(", ")} m, ` +
      `range Y ${box.min[1]} to ${box.max[1]} m`,
    );
  }
  return lines;
}
