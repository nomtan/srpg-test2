// Phase 4 Asset Creator domain: the equippable asset types, their defaults, and the
// draft -> asset.json projection. `base` and `texture` categories are out of scope here.
import type { AssetMetadata } from "./asset";
import {
  type AnimationSet, type BodyType, type CharacterSocket, type EquipmentSlot,
  type HairPolicy, type PaletteSlot, type RecipeSlot, type WeaponHandling, type WeaponType,
} from "./constants";

export const ASSET_TYPES = [
  "hair", "headgear", "head_accessory",
  "chest_armor",
  "shoulder_left", "shoulder_right",
  "arm_armor", "gloves",
  "waist", "boots",
  "weapon", "shield",
  "back",
] as const;
export type AssetType = typeof ASSET_TYPES[number];

export const ASSET_TYPE_LABELS: Record<AssetType, string> = {
  hair: "Hair", headgear: "Headgear", head_accessory: "Head Accessory",
  chest_armor: "Chest Armor", shoulder_left: "Shoulder Left", shoulder_right: "Shoulder Right",
  arm_armor: "Arm Armor", gloves: "Gloves", waist: "Waist", boots: "Boots",
  weapon: "Weapon", shield: "Shield", back: "Back",
};

/** Auto-selected on type change; the user can still override in the form. */
export const RECOMMENDED_SOCKET: Record<AssetType, CharacterSocket> = {
  hair: "socket_hair",
  headgear: "socket_headgear",
  head_accessory: "socket_head",
  chest_armor: "socket_chest",
  shoulder_left: "socket_shoulder_left",
  shoulder_right: "socket_shoulder_right",
  arm_armor: "socket_arm_right",
  gloves: "socket_hand_right",
  waist: "socket_waist",
  boots: "socket_foot_right",
  weapon: "socket_hand_right",
  shield: "socket_hand_left",
  back: "socket_back",
};

export const EQUIPMENT_SLOT_BY_TYPE: Record<AssetType, EquipmentSlot | "main_hand" | "off_hand"> = {
  hair: "hair", headgear: "headgear", head_accessory: "head_accessory",
  chest_armor: "chest_armor", shoulder_left: "shoulder_left", shoulder_right: "shoulder_right",
  arm_armor: "arm_armor", gloves: "gloves", waist: "waist", boots: "boots",
  weapon: "main_hand", shield: "off_hand", back: "back",
};

export const RECIPE_SLOT_BY_TYPE: Record<AssetType, RecipeSlot> = {
  hair: "hair", headgear: "headgear", head_accessory: "headAccessory",
  chest_armor: "chestArmor", shoulder_left: "shoulderLeft", shoulder_right: "shoulderRight",
  arm_armor: "armArmor", gloves: "gloves", waist: "waist", boots: "boots",
  weapon: "mainHand", shield: "offHand", back: "back",
};

/** Only these types expose the hairPolicy control (spec section 13). */
export const HAIR_POLICY_TYPES: readonly AssetType[] = ["headgear", "head_accessory"];
export const isWeapon = (type: AssetType) => type === "weapon";

export type GripPoint = "grip_main" | "grip_sub";
/** Grip point -> character socket alignment by handling (spec section 12). */
export const GRIP_ALIGNMENT: Record<WeaponHandling, Partial<Record<GripPoint, CharacterSocket>>> = {
  one_hand: { grip_main: "socket_hand_right" },
  off_hand: { grip_main: "socket_hand_left" },
  two_hand: { grip_main: "socket_hand_right", grip_sub: "socket_hand_left" },
};
export const gripPointsFor = (handling: WeaponHandling): GripPoint[] =>
  Object.keys(GRIP_ALIGNMENT[handling]) as GripPoint[];

export const WEAPON_TYPE_HANDLING: Record<WeaponType, WeaponHandling> = {
  sword: "one_hand", great_sword: "two_hand", spear: "two_hand",
  bow: "two_hand", dagger: "one_hand", staff: "two_hand",
};
export const WEAPON_TYPE_ANIMATION_SET: Record<WeaponType, AnimationSet> = {
  sword: "onehand_sword", great_sword: "great_sword", spear: "spear",
  bow: "bow", dagger: "dagger", staff: "staff",
};

/** Suggested palette slots on type change; multi-select, fully editable. */
export const SUGGESTED_PALETTE_SLOTS: Record<AssetType, PaletteSlot[]> = {
  hair: ["hair"],
  headgear: ["primary", "secondary", "metal"],
  head_accessory: ["metal", "primary"],
  chest_armor: ["primary", "secondary", "metal", "leather"],
  shoulder_left: ["primary", "metal"],
  shoulder_right: ["primary", "metal"],
  arm_armor: ["primary", "metal", "leather"],
  gloves: ["leather", "primary"],
  waist: ["leather", "primary", "metal"],
  boots: ["leather", "primary"],
  weapon: ["metal", "leather", "primary"],
  shield: ["metal", "leather", "primary", "secondary"],
  back: ["secondary", "primary"],
};

export const BASE_TEXTURE_SIZE = 32;
export const WEAPON_TEXTURE_SIZES = [16, 32, 48, 64] as const;

export interface AssetDraft {
  type: AssetType;
  name: string;
  id: string;
  bodyTypes: BodyType[];
  description: string;
  socket: CharacterSocket;
  paletteSlots: PaletteSlot[];
  hairPolicy: HairPolicy | null;
  hideParts: string[];
  weaponType: WeaponType;
  handling: WeaponHandling;
  animationSet: AnimationSet;
  gripPoints: GripPoint[];
  textureResolution: number;
  sourceFileName: string | null;
}

const SLUG_STOPWORDS = new Set(["the", "a", "an", "of"]);
/** snake_case id candidate from a free-text name; user stays free to edit. */
export function suggestId(name: string, type: AssetType): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .split("_")
    .filter((part) => part && !SLUG_STOPWORDS.has(part))
    .join("_");
  const stem = slug || type;
  return /_\d{3}$/.test(stem) ? stem : `${stem}_001`;
}
export const isSnakeCase = (id: string) => /^[a-z][a-z0-9]*(_[a-z0-9]+)*$/.test(id);

export function emptyDraft(type: AssetType = "hair"): AssetDraft {
  const weaponType: WeaponType = "sword";
  return {
    type,
    name: "",
    id: "",
    bodyTypes: ["adult"],
    description: "",
    socket: RECOMMENDED_SOCKET[type],
    paletteSlots: [...SUGGESTED_PALETTE_SLOTS[type]],
    hairPolicy: type === "headgear" ? "hide" : type === "head_accessory" ? "overlay" : null,
    hideParts: [],
    weaponType,
    handling: WEAPON_TYPE_HANDLING[weaponType],
    animationSet: WEAPON_TYPE_ANIMATION_SET[weaponType],
    gripPoints: gripPointsFor(WEAPON_TYPE_HANDLING[weaponType]),
    textureResolution: BASE_TEXTURE_SIZE,
    sourceFileName: null,
  };
}

/** Re-apply type-driven defaults while keeping user identity fields. */
export function applyTypeDefaults(draft: AssetDraft, type: AssetType): AssetDraft {
  const next: AssetDraft = {
    ...draft,
    type,
    socket: RECOMMENDED_SOCKET[type],
    paletteSlots: [...SUGGESTED_PALETTE_SLOTS[type]],
    hairPolicy: HAIR_POLICY_TYPES.includes(type)
      ? (type === "headgear" ? "hide" : "overlay")
      : null,
    textureResolution: type === "weapon" ? draft.textureResolution : BASE_TEXTURE_SIZE,
  };
  if (isWeapon(type)) next.gripPoints = gripPointsFor(next.handling);
  return next;
}

export function draftToAssetJson(draft: AssetDraft): AssetMetadata {
  const weapon = isWeapon(draft.type);
  const shield = draft.type === "shield";
  const metadata: AssetMetadata = {
    specVersion: 1,
    assetVersion: 1,
    id: draft.id,
    name: draft.name,
    type: draft.type,
    bodyTypes: [...draft.bodyTypes],
    attachment: {
      main: {
        assetPoint: weapon ? "grip_main" : "fixture_origin",
        characterSocket: draft.socket,
      },
    },
    appearance: { paletteSlots: [...draft.paletteSlots] },
    hairPolicy: draft.hairPolicy,
    hideParts: [...draft.hideParts],
    model: "model.glb",
    texture: "texture.png",
    thumbnail: "thumbnail.png",
  };
  if (draft.sourceFileName) {
    metadata.source = { format: "bbmodel", path: `source/${draft.sourceFileName}` as `${string}.bbmodel` };
  }
  if (weapon || shield) {
    metadata.equipment = {
      slot: weapon ? "main_hand" : "off_hand",
      handling: weapon ? draft.handling : "off_hand",
      ...(weapon ? { animationSet: draft.animationSet, weaponType: draft.weaponType } : {}),
    };
  }
  if (weapon && draft.handling === "two_hand" && draft.gripPoints.includes("grip_sub")) {
    metadata.attachment!.sub = { assetPoint: "grip_sub", characterSocket: "socket_hand_left" };
  }
  return metadata;
}

/** Pretty JSON matching the spec section 10/13 key order for a stable diff. */
export function assetJsonText(draft: AssetDraft): string {
  const m = draftToAssetJson(draft);
  const ordered: Record<string, unknown> = {
    specVersion: m.specVersion,
    assetVersion: m.assetVersion,
    id: m.id,
    name: m.name,
    type: m.type,
    bodyTypes: m.bodyTypes,
  };
  if (m.equipment) ordered.equipment = m.equipment;
  ordered.attachment = m.attachment;
  ordered.appearance = m.appearance;
  ordered.hairPolicy = m.hairPolicy;
  ordered.hideParts = m.hideParts;
  if (m.source) ordered.source = m.source;
  ordered.model = m.model;
  ordered.texture = m.texture;
  ordered.thumbnail = m.thumbnail;
  return JSON.stringify(ordered, null, 2) + "\n";
}

export const ASSET_CATEGORY_DIR: Record<AssetType, string> = {
  hair: "hair", headgear: "headgear", head_accessory: "head_accessory",
  chest_armor: "armor", shoulder_left: "shoulder", shoulder_right: "shoulder",
  arm_armor: "armor", gloves: "gloves", waist: "waist", boots: "boots",
  weapon: "weapon", shield: "shield", back: "back",
};
/** assets/character-assets/<category>/<id>/ (spec section 9). */
export const assetDir = (draft: AssetDraft) =>
  `assets/character-assets/${ASSET_CATEGORY_DIR[draft.type]}/${draft.id || "<id>"}`;
