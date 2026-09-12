import type { CharacterSocket } from "./constants";

export type Vector3Tuple = [number, number, number];
export type StandardBoneRole = "upper_body" | "body" | "chest" | "head" | "pelvis" | "arm_left" | "arm_right" | "forearm_left" | "forearm_right" | "hand_left" | "hand_right" | "leg_left" | "leg_right" | "lower_leg_left" | "lower_leg_right";

/**
 * The source's lateral names are mirrored relative to the character.
 *
 * With `+X forward` and `+Y up`, a right-handed triad requires `forward x left = up`, and
 * `+X x -Z = +Y`. So the character's LEFT is **-Z** and its RIGHT is **+Z**. Every source group
 * spelled `*_left` sits at +Z (`hand_left_te` is at z = +0.48 m) and is therefore the character's
 * RIGHT limb; `*_right` groups are its LEFT limb. The source's own weapon hierarchy agrees: the
 * one-hand sword is parented under `hand_left_te`, i.e. the hand a right-handed character uses.
 *
 * Source spelling is never changed (Phase 2). Instead every semantic mapping below resolves a
 * physical side to the source group that actually occupies it.
 */
export const SOURCE_NODE_BY_SIDE = {
  arm: { left: "hand_right", right: "hand_left" },
  forearm: { left: "hand_right_kote", right: "hand_left_kote" },
  hand: { left: "hand_right_te", right: "hand_left_te" },
  thigh: { left: "foot_right", right: "foot_left" },
  lowerLeg: { left: "ashi_right", right: "ashi_left" },
} as const;

/** Semantic aliases only: never rename or reparent source nodes. */
export const baseRigMapping = {
  zyouhannshin: "upper_body",
  body: "body",
  dou: "chest",
  ganmen: "head",
  kahanshi: "pelvis",
  // Roles follow the physical side, not the mirrored source spelling (see SOURCE_NODE_BY_SIDE).
  hand_left: "arm_right",
  hand_right: "arm_left",
  hand_left_kote: "forearm_right",
  hand_right_kote: "forearm_left",
  hand_left_te: "hand_right",
  hand_right_te: "hand_left",
  foot_left: "leg_right",
  foot_right: "leg_left",
  ashi_left: "lower_leg_right",
  ashi_right: "lower_leg_left",
} as const satisfies Record<string, StandardBoneRole>;

/** Preserve source spelling and handedness, including gread_sword / allow. */
export const equipmentRootClassification = {
  onehand_sword: "sword", gread_sword: "great_sword", spear: "spear",
  bow: "bow", shield: "shield", dagger_left: "dagger", dagger_right: "dagger",
  allow: "projectile_candidate",
} as const;

export interface SocketDefinition {
  id: CharacterSocket;
  parent: keyof typeof baseRigMapping;
  position: Vector3Tuple;
  rotation: Vector3Tuple;
  space: "parent_local_runtime";
  status: "pivot_only_uncalibrated";
}
// Lateral sockets resolve through SOURCE_NODE_BY_SIDE: socket_*_right must land on the group that
// physically sits on the character's right (+Z), which the source spells "*_left".
const socketParents = {
  socket_head: "ganmen", socket_hair: "ganmen", socket_headgear: "ganmen",
  socket_chest: "dou", socket_back: "body", socket_waist: "kahanshi",
  socket_shoulder_left: SOURCE_NODE_BY_SIDE.arm.left,
  socket_shoulder_right: SOURCE_NODE_BY_SIDE.arm.right,
  socket_arm_left: SOURCE_NODE_BY_SIDE.forearm.left,
  socket_arm_right: SOURCE_NODE_BY_SIDE.forearm.right,
  socket_hand_left: SOURCE_NODE_BY_SIDE.hand.left,
  socket_hand_right: SOURCE_NODE_BY_SIDE.hand.right,
  socket_foot_left: SOURCE_NODE_BY_SIDE.lowerLeg.left,
  socket_foot_right: SOURCE_NODE_BY_SIDE.lowerLeg.right,
} as const satisfies Record<CharacterSocket, keyof typeof baseRigMapping>;

/** Initial anchors at existing pivots, NOT validated equipment attachment positions. */
export const baseSocketDefinitions: SocketDefinition[] = Object.entries(socketParents).map(([id, parent]) => ({
  id: id as CharacterSocket, parent, position: [0, 0, 0], rotation: [0, 0, 0],
  space: "parent_local_runtime", status: "pivot_only_uncalibrated",
}));

/**
 * Weapon / shield orientation at the hand sockets, in Blockbench ZYX Euler degrees.
 *
 * Taken from the source's own authored placement: `onehand_sword`, `gread_sword` and `spear` all
 * carry rotation [-180, 0, 90] under `hand_left_te`, and `shield` / `dagger` carry [0, 0, 90].
 * Applied to assets that attach by a grip point, so an asset authored the way the Production
 * Prompt asks (blade along local +Y, grip at the origin) ends up blade-forward (+X) like the
 * source prop. Scale and position are untouched — this is orientation only.
 */
export const GRIP_ORIENTATION_DEGREES = {
  main_hand: [-180, 0, 90] as Vector3Tuple,
  off_hand: [0, 0, 90] as Vector3Tuple,
} as const;

export const BASE_COORDINATES = {
  source: "assets/characters/base/base_1.bbmodel",
  metersPerSourceUnit: 1 / 12,
  // forward x left = up requires +X x -Z = +Y, so the character's left is -Z (its right is +Z).
  up: "+Y", forward: "+X", left: "-Z", right: "+Z",
  axisConversion: "identity",
  evidence: "tools/asset_gen/export_explorer_model.py uses base_1.bbmodel at 1/12 scale; explorer_actor.gd uses +X forward without an extra model scale.",
} as const;

export interface BaseModelAnalysis {
  source: { path: string; sha256: string; format: string };
  coordinates: typeof BASE_COORDINATES;
  counts: { groups: number; elements: number; meshes: number; cubes: number; bodyParts: number; previewMeshes: number; animations: number; textures: number };
  groups: { uuid: string; name: string; parent: string | null; origin: number[]; rotation: number[]; classification: string; visible: boolean; exported: boolean; role: StandardBoneRole | null; animatedBy: string[] }[];
  bodyParts: { uuid: string; name: string; parent: string | null; visible: boolean; exported: boolean }[];
  equipmentGroups: { uuid: string; name: string; parent: string | null; classification: string; visible: boolean; exported: boolean }[];
  animations: { uuid: string; name: string; length: number; loop: string; keyframeCount: number; targets: { uuid: string; name: string; keyframes: unknown[] }[] }[];
  bounds: { min: number[]; max: number[]; size: number[]; units: string };
}
