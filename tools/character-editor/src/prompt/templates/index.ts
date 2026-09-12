// Asset Type -> Prompt Template registry (spec section 26). One file per family; nothing here
// concatenates a giant prompt string.
import type { AssetType } from "@/domain/asset-spec";
import type { TypeTemplate } from "./types";
import { hairTemplate } from "./hair";
import { headAccessoryTemplate, headgearTemplate } from "./headgear";
import { armArmorTemplate, bootsTemplate, chestArmorTemplate, glovesTemplate, waistTemplate } from "./armor";
import { shoulderLeftTemplate, shoulderRightTemplate } from "./shoulder";
import { weaponTemplate } from "./weapon";
import { shieldTemplate } from "./shield";
import { backTemplate } from "./back";

export const TYPE_TEMPLATES: Record<AssetType, TypeTemplate> = {
  hair: hairTemplate,
  headgear: headgearTemplate,
  head_accessory: headAccessoryTemplate,
  chest_armor: chestArmorTemplate,
  shoulder_left: shoulderLeftTemplate,
  shoulder_right: shoulderRightTemplate,
  arm_armor: armArmorTemplate,
  gloves: glovesTemplate,
  waist: waistTemplate,
  boots: bootsTemplate,
  weapon: weaponTemplate,
  shield: shieldTemplate,
  back: backTemplate,
};

/** Template file each asset type is served by; surfaced in the package README for traceability. */
export const TYPE_TEMPLATE_FILE: Record<AssetType, string> = {
  hair: "prompt/templates/hair.ts",
  headgear: "prompt/templates/headgear.ts",
  head_accessory: "prompt/templates/headgear.ts",
  chest_armor: "prompt/templates/armor.ts",
  shoulder_left: "prompt/templates/shoulder.ts",
  shoulder_right: "prompt/templates/shoulder.ts",
  arm_armor: "prompt/templates/armor.ts",
  gloves: "prompt/templates/armor.ts",
  waist: "prompt/templates/armor.ts",
  boots: "prompt/templates/armor.ts",
  weapon: "prompt/templates/weapon.ts",
  shield: "prompt/templates/shield.ts",
  back: "prompt/templates/back.ts",
};

export type { TypeTemplate };
