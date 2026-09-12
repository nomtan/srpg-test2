// Phase 8 candidate filtering and Asset Compatibility (spec section 11-13, 16).
// Every draw goes through here first: a variation may only pick an asset that is *usable* on the
// character being built. Incompatible combinations are removed from the candidate pool instead of
// being generated and rejected afterwards, so the generator never needs an unbounded retry loop.
import { RARITY_WEIGHT, type AnimationSet, type AssetCategory, type AssetRarity, type BodyType, type CharacterSocket, type HairPolicy, type WeaponHandling, type WeaponType } from "./constants";
import { SLOT_CATEGORY } from "./builder-recipe";
import { GENDER_STYLE_TAGS, type GenderExpression, type SlotRule, type VariationSlot } from "./variation-preset";

/**
 * Library-agnostic view of one asset. Built from the merged Asset Library so the generator works
 * the same for repository assets, demo assets and Phase 7 library-data assets.
 */
export interface CandidateAsset {
  id: string;
  name: string;
  type: AssetCategory;
  bodyTypes: BodyType[];
  tags: string[];
  rarity?: AssetRarity;
  weight?: number;
  weaponType?: WeaponType;
  handling?: WeaponHandling;
  animationSet?: AnimationSet;
  hairPolicy: HairPolicy | null;
  hideParts: string[];
  socket?: CharacterSocket;
  hasModel: boolean;
  thumbnailUrl?: string | null;
}

/** Effective draw weight (spec section 9-10): rule override > metadata weight > rarity > common. */
export function resolveWeight(asset: CandidateAsset, rule?: SlotRule): number {
  const override = rule?.weights?.[asset.id];
  if (typeof override === "number" && Number.isFinite(override) && override >= 0) return override;
  if (typeof asset.weight === "number" && Number.isFinite(asset.weight) && asset.weight >= 0) return asset.weight;
  if (asset.rarity) return RARITY_WEIGHT[asset.rarity];
  return RARITY_WEIGHT.common;
}

/** Assets matching a style the preset is not asking for get dropped; matches get a nudge up. */
export function genderMultiplier(asset: CandidateAsset, gender: GenderExpression): number {
  if (gender === "any") return 1;
  const styles = asset.tags.filter((t) => GENDER_STYLE_TAGS.includes(t));
  if (styles.length === 0) return 1;
  if (styles.includes(gender)) return 2;
  if (styles.includes("neutral")) return 1;
  return 0;
}

export interface CompatibilityContext {
  bodyType: BodyType;
  gender: GenderExpression;
  /** Handling of the already-chosen main hand weapon; drives the two-hand rule (spec 13). */
  mainHandHandling: WeaponHandling | null;
  /** hideParts contributed by the assets chosen so far. */
  hiddenParts: Set<string>;
  /** Asset ids already used on this character; the same asset is never equipped twice. */
  usedIds: Set<string>;
}

export function emptyContext(bodyType: BodyType, gender: GenderExpression): CompatibilityContext {
  return { bodyType, gender, mainHandHandling: null, hiddenParts: new Set(), usedIds: new Set() };
}

/** Part names an already-equipped asset may hide, mapped back to the slot they would blank out. */
const SLOT_HIDE_KEYS: Record<VariationSlot, string[]> = {
  hair: ["hair", "socket_hair"],
  headgear: ["headgear", "socket_headgear"],
  headAccessory: ["head_accessory", "headAccessory", "socket_head"],
  chestArmor: ["chest_armor", "chestArmor", "socket_chest"],
  shoulderLeft: ["shoulder_left", "shoulderLeft", "socket_shoulder_left"],
  shoulderRight: ["shoulder_right", "shoulderRight", "socket_shoulder_right"],
  armArmor: ["arm_armor", "armArmor", "socket_arm_right", "socket_arm_left"],
  gloves: ["gloves", "socket_hand_right"],
  waist: ["waist", "socket_waist"],
  boots: ["boots", "socket_foot_right", "socket_foot_left"],
  mainHand: ["main_hand", "mainHand"],
  offHand: ["off_hand", "offHand"],
  back: ["back", "socket_back"],
};

/** True when something already equipped hides this slot, so filling it would be invisible. */
export function slotIsHidden(slot: VariationSlot, hiddenParts: ReadonlySet<string>): boolean {
  return SLOT_HIDE_KEYS[slot].some((key) => hiddenParts.has(key));
}

export type RejectReason =
  | "category" | "body_type" | "no_model" | "not_allowed" | "tag" | "exclude_tag"
  | "weapon_type" | "handling" | "two_hand" | "gender" | "duplicate";

export interface CandidateCheck {
  asset: CandidateAsset;
  ok: boolean;
  reason?: RejectReason;
  weight: number;
}

/**
 * One asset against one slot rule. Order matters only for the reported reason; every check is
 * independent. `two_hand` is the rule from spec section 13: a two-hand main hand removes off hand.
 */
export function checkCandidate(
  asset: CandidateAsset,
  slot: VariationSlot,
  rule: SlotRule,
  ctx: CompatibilityContext,
): CandidateCheck {
  const fail = (reason: RejectReason): CandidateCheck => ({ asset, ok: false, reason, weight: 0 });

  if (!SLOT_CATEGORY[slot].includes(asset.type)) return fail("category");
  if (!asset.hasModel) return fail("no_model");
  if (asset.bodyTypes.length > 0 && !asset.bodyTypes.includes(ctx.bodyType)) return fail("body_type");
  if (ctx.usedIds.has(asset.id)) return fail("duplicate");
  if (rule.assetIds.length > 0 && !rule.assetIds.includes(asset.id)) return fail("not_allowed");
  if (rule.tags.length > 0 && !rule.tags.some((t) => asset.tags.includes(t))) return fail("tag");
  if (rule.excludeTags.length > 0 && rule.excludeTags.some((t) => asset.tags.includes(t))) return fail("exclude_tag");

  if (slot === "mainHand") {
    if (asset.handling === "off_hand") return fail("handling");
    if (rule.weaponTypes.length > 0 && (!asset.weaponType || !rule.weaponTypes.includes(asset.weaponType))) {
      return fail("weapon_type");
    }
  }
  if (slot === "offHand") {
    if (ctx.mainHandHandling === "two_hand") return fail("two_hand");
    // A weapon in the off hand must be single-handed; shields declare off_hand handling.
    if (asset.type === "weapon") {
      if (asset.handling === "two_hand") return fail("handling");
      if (rule.weaponTypes.length > 0 && (!asset.weaponType || !rule.weaponTypes.includes(asset.weaponType))) {
        return fail("weapon_type");
      }
    }
  }

  const genderFactor = genderMultiplier(asset, ctx.gender);
  if (genderFactor === 0) return fail("gender");

  return { asset, ok: true, weight: resolveWeight(asset, rule) * genderFactor };
}

export interface CandidatePool {
  slot: VariationSlot;
  candidates: CandidateCheck[];
  /** Rejection tally, used by preset validation to explain an empty pool. */
  rejected: Partial<Record<RejectReason, number>>;
}

export function buildPool(
  assets: readonly CandidateAsset[],
  slot: VariationSlot,
  rule: SlotRule,
  ctx: CompatibilityContext,
): CandidatePool {
  const candidates: CandidateCheck[] = [];
  const rejected: Partial<Record<RejectReason, number>> = {};
  for (const asset of assets) {
    const check = checkCandidate(asset, slot, rule, ctx);
    if (check.ok) candidates.push(check);
    else if (check.reason && check.reason !== "category") rejected[check.reason] = (rejected[check.reason] ?? 0) + 1;
  }
  return { slot, candidates, rejected };
}

/**
 * Symmetric shoulders (spec section 16): given a left-shoulder asset, find its right-hand partner.
 * The id convention wins (`_left` <-> `_right`); otherwise the best tag overlap is used, so a
 * library that names its pairs differently still produces matched sets for uniformed troops.
 */
export function pairShoulder(chosen: CandidateAsset, others: readonly CandidateCheck[], want: "left" | "right"): CandidateCheck | null {
  if (others.length === 0) return null;
  const swapped = want === "right"
    ? chosen.id.replace(/left/g, "right")
    : chosen.id.replace(/right/g, "left");
  const exact = others.find((c) => c.asset.id === swapped);
  if (exact) return exact;

  let best: CandidateCheck | null = null;
  let bestScore = -1;
  for (const other of others) {
    const overlap = other.asset.tags.filter((t) => chosen.tags.includes(t)).length;
    const nameScore = other.asset.name.replace(/(left|right|L|R)/gi, "") === chosen.name.replace(/(left|right|L|R)/gi, "") ? 5 : 0;
    const score = overlap + nameScore;
    if (score > bestScore) { bestScore = score; best = other; }
  }
  return bestScore > 0 ? best : null;
}

export const REJECT_LABEL: Record<RejectReason, string> = {
  category: "カテゴリ不一致",
  body_type: "Body Type 非対応",
  no_model: "model.glb なし",
  not_allowed: "Allowed Assets 未選択",
  tag: "Tag 条件を満たさない",
  exclude_tag: "Exclude Tag に一致",
  weapon_type: "Weapon Type 制限",
  handling: "Handling 不適合",
  two_hand: "Two Hand 武器と競合",
  gender: "Gender Expression 不一致",
  duplicate: "同一 Character で使用済み",
};
