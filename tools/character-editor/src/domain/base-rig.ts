import type { CharacterSocket } from "./constants";

export type Vector3Tuple = [number, number, number];
export type StandardBoneRole = "upper_body" | "body" | "chest" | "head" | "pelvis" | "arm_left" | "arm_right" | "forearm_left" | "forearm_right" | "hand_left" | "hand_right" | "leg_left" | "leg_right" | "lower_leg_left" | "lower_leg_right";

/** Semantic aliases only: never rename or reparent source nodes. */
export const baseRigMapping = {
  zyouhannshin: "upper_body",
  body: "body",
  dou: "chest",
  ganmen: "head",
  kahanshi: "pelvis",
  hand_left: "arm_left",
  hand_right: "arm_right",
  hand_left_kote: "forearm_left",
  hand_right_kote: "forearm_right",
  hand_left_te: "hand_left",
  hand_right_te: "hand_right",
  foot_left: "leg_left",
  foot_right: "leg_right",
  ashi_left: "lower_leg_left",
  ashi_right: "lower_leg_right",
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
const socketParents = {
  socket_head: "ganmen", socket_hair: "ganmen", socket_headgear: "ganmen",
  socket_chest: "dou", socket_back: "body", socket_waist: "kahanshi",
  socket_shoulder_left: "hand_left", socket_shoulder_right: "hand_right",
  socket_arm_left: "hand_left_kote", socket_arm_right: "hand_right_kote",
  socket_hand_left: "hand_left_te", socket_hand_right: "hand_right_te",
  socket_foot_left: "ashi_left", socket_foot_right: "ashi_right",
} as const satisfies Record<CharacterSocket, keyof typeof baseRigMapping>;

/** Initial anchors at existing pivots, NOT validated equipment attachment positions. */
export const baseSocketDefinitions: SocketDefinition[] = Object.entries(socketParents).map(([id, parent]) => ({
  id: id as CharacterSocket, parent, position: [0, 0, 0], rotation: [0, 0, 0],
  space: "parent_local_runtime", status: "pivot_only_uncalibrated",
}));

export const BASE_COORDINATES = {
  source: "assets/characters/base/base_1.bbmodel",
  metersPerSourceUnit: 1 / 12,
  up: "+Y", forward: "+X", left: "+Z",
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
