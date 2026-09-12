// Phase 9 per-asset-type production profiles: geometry budget, transparency policy, attachment
// spec and the animations an imported asset is test-driven against.
//
// Spec section 11 asks for a *profile* (low / medium / high) rather than hard numbers, because the
// real numbers can only be settled once a body of assets exists. The numeric ranges here are the
// current working values behind each profile and are meant to be re-tuned later; the profile name
// is what the prompt states, the number is what Validation measures against.
import type { AssetType, GripPoint } from "./asset-spec";
import { GRIP_ALIGNMENT, RECOMMENDED_SOCKET, isWeapon } from "./asset-spec";
import type { CharacterSocket, WeaponHandling } from "./constants";

export const BUDGET_PROFILES = ["low", "medium", "high"] as const;
export type BudgetProfile = typeof BUDGET_PROFILES[number];

export interface BudgetDefinition {
  /** Authoring target an AI agent should aim for. */
  targetTriangles: number;
  /** Above this, Validation raises a warning (never an error — section 40 keeps score advisory). */
  maxTriangles: number;
  maxMaterials: number;
}

/** Working numbers per profile. Re-tune from real assets; the profile label is the contract. */
export const BUDGET_DEFINITION: Record<BudgetProfile, BudgetDefinition> = {
  low: { targetTriangles: 400, maxTriangles: 1200, maxMaterials: 2 },
  medium: { targetTriangles: 1200, maxTriangles: 3000, maxMaterials: 3 },
  high: { targetTriangles: 3000, maxTriangles: 6000, maxMaterials: 4 },
};

export const TYPE_BUDGET: Record<AssetType, BudgetProfile> = {
  hair: "low",
  headgear: "low",
  head_accessory: "low",
  chest_armor: "medium",
  shoulder_left: "medium",
  shoulder_right: "medium",
  arm_armor: "low",
  gloves: "low",
  waist: "low",
  boots: "low",
  weapon: "low",
  shield: "low",
  back: "medium",
};

/** Spec section 23: transparency is opt-in per asset type. */
export const ALPHA_POLICIES = ["alpha_required", "alpha_allowed", "alpha_forbidden"] as const;
export type AlphaPolicy = typeof ALPHA_POLICIES[number];

export const ALPHA_POLICY_LABEL: Record<AlphaPolicy, string> = {
  alpha_required: "alpha required",
  alpha_allowed: "alpha allowed",
  alpha_forbidden: "alpha forbidden",
};

export const TYPE_ALPHA_POLICY: Record<AssetType, AlphaPolicy> = {
  hair: "alpha_allowed",
  headgear: "alpha_forbidden",
  head_accessory: "alpha_allowed",
  chest_armor: "alpha_forbidden",
  shoulder_left: "alpha_forbidden",
  shoulder_right: "alpha_forbidden",
  arm_armor: "alpha_forbidden",
  gloves: "alpha_forbidden",
  waist: "alpha_allowed",
  boots: "alpha_forbidden",
  weapon: "alpha_forbidden",
  shield: "alpha_forbidden",
  back: "alpha_allowed",
};

/**
 * Representative animations each asset type is checked against after import (spec section 43).
 * `set` is the preview animation set; weapons override it with their own animationSet.
 */
export const TYPE_ANIMATION_TEST: Record<AssetType, { set: string; roles: string[] }> = {
  hair: { set: "default", roles: ["idle", "run"] },
  headgear: { set: "default", roles: ["idle", "run"] },
  head_accessory: { set: "default", roles: ["idle", "run"] },
  chest_armor: { set: "default", roles: ["idle", "run"] },
  shoulder_left: { set: "default", roles: ["idle", "run", "attack"] },
  shoulder_right: { set: "default", roles: ["idle", "run", "attack"] },
  arm_armor: { set: "default", roles: ["idle", "run", "attack"] },
  gloves: { set: "default", roles: ["idle", "run", "attack"] },
  waist: { set: "default", roles: ["idle", "run"] },
  boots: { set: "default", roles: ["idle", "run"] },
  weapon: { set: "onehand_sword", roles: ["idle", "run", "attack"] },
  shield: { set: "onehand_sword", roles: ["idle", "run", "attack"] },
  back: { set: "default", roles: ["idle", "run"] },
};

export interface AttachmentSpec {
  socket: CharacterSocket;
  /** Named node the AI must author in the model; weapons use grip points (spec section 16). */
  assetPoint: string;
  gripPoints: GripPoint[];
  /** gripPoint -> character socket, from the Phase 4 GRIP_ALIGNMENT table. */
  gripAlignment: Partial<Record<GripPoint, CharacterSocket>>;
  side: "left" | "right" | "center";
}

/** Spec section 14: attachment info is derived from the asset type, never hand-typed. */
export function attachmentSpecFor(
  type: AssetType,
  socket: CharacterSocket = RECOMMENDED_SOCKET[type],
  handling: WeaponHandling = "one_hand",
): AttachmentSpec {
  const weapon = isWeapon(type);
  const shield = type === "shield";
  const effectiveHandling: WeaponHandling = weapon ? handling : shield ? "off_hand" : "one_hand";
  const gripAlignment = weapon || shield ? GRIP_ALIGNMENT[effectiveHandling] : {};
  return {
    socket,
    assetPoint: weapon || shield ? "grip_main" : "fixture_origin",
    gripPoints: Object.keys(gripAlignment) as GripPoint[],
    gripAlignment,
    side: socket.endsWith("_left") ? "left" : socket.endsWith("_right") ? "right" : "center",
  };
}
