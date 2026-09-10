// Const tuples keep runtime choices and JSON-compatible literal types in sync.
export const SPEC_VERSION = 1 as const;
export const ASSET_CATEGORIES = ["base", "hair", "headgear", "head_accessory", "chest_armor", "shoulder_left", "shoulder_right", "arm_armor", "gloves", "waist", "boots", "weapon", "shield", "back", "texture"] as const;
export type AssetCategory = typeof ASSET_CATEGORIES[number];
export const CATEGORY_LABELS: Record<AssetCategory, string> = {
  base: "Base Body", hair: "Hair", headgear: "Headgear", head_accessory: "Head Accessory",
  chest_armor: "Chest Armor", shoulder_left: "Shoulder L", shoulder_right: "Shoulder R",
  arm_armor: "Arm Armor", gloves: "Gloves", waist: "Waist", boots: "Boots",
  weapon: "Weapon", shield: "Shield", back: "Back", texture: "Texture",
};
export const BODY_TYPES = ["adult", "child"] as const;
export type BodyType = typeof BODY_TYPES[number];
export const BODY_PRESETS = ["adult_normal", "adult_slim", "adult_large", "child"] as const;
export type BodyPreset = typeof BODY_PRESETS[number];
export const CHARACTER_SOCKETS = ["socket_head", "socket_hair", "socket_headgear", "socket_chest", "socket_back", "socket_waist", "socket_shoulder_left", "socket_shoulder_right", "socket_arm_left", "socket_arm_right", "socket_hand_left", "socket_hand_right", "socket_foot_left", "socket_foot_right"] as const;
export type CharacterSocket = typeof CHARACTER_SOCKETS[number];
export const GRIP_POINTS = ["grip_main", "grip_sub"] as const;
export const WEAPON_HANDLING = ["one_hand", "two_hand", "off_hand"] as const;
export type WeaponHandling = typeof WEAPON_HANDLING[number];
export const WEAPON_TYPES = ["sword", "great_sword", "spear", "bow", "dagger", "staff"] as const;
export type WeaponType = typeof WEAPON_TYPES[number];
export const ANIMATION_SETS = ["onehand_sword", "great_sword", "spear", "bow", "dagger", "staff"] as const;
export type AnimationSet = typeof ANIMATION_SETS[number];
export const BASE_ANIMATIONS = ["idle", "walk", "run", "damage", "death"] as const;
export const WEAPON_ANIMATIONS = ["idle", "walk", "run", "attack", "skill"] as const;
export const PALETTE_SLOTS = ["primary", "secondary", "metal", "leather", "hair", "skin"] as const;
export type PaletteSlot = typeof PALETTE_SLOTS[number];
export const HAIR_POLICIES = ["hide", "overlay"] as const;
export type HairPolicy = typeof HAIR_POLICIES[number];
export const EQUIPMENT_SLOTS = ["hair", "headgear", "head_accessory", "chest_armor", "shoulder_left", "shoulder_right", "arm_armor", "gloves", "waist", "boots", "main_hand", "off_hand", "back"] as const;
export type EquipmentSlot = typeof EQUIPMENT_SLOTS[number];
export const RECIPE_SLOTS = ["hair", "headgear", "headAccessory", "chestArmor", "shoulderLeft", "shoulderRight", "armArmor", "gloves", "waist", "boots", "mainHand", "offHand", "back", "texture"] as const;
export type RecipeSlot = typeof RECIPE_SLOTS[number];
export const COORDINATE_SYSTEM = { upAxis: "Y", metersPerFieldCell: 1, godotScale: 1 } as const;
export const BASE_TEXTURE_RESOLUTION = { width: 32, height: 32 } as const;
