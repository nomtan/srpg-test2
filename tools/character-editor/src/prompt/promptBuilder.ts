import { isWeapon, type AssetDraft } from "@/domain/asset-spec";
import { DEFAULT_PALETTE } from "@/domain/phase3";
import type { PaletteSlot } from "@/domain/constants";
import {
  BUDGET_DEFINITION, TYPE_ALPHA_POLICY, TYPE_ANIMATION_TEST, TYPE_BUDGET, attachmentSpecFor,
  type AlphaPolicy, type BudgetProfile,
} from "@/domain/production-profile";
import {
  CLEARANCE_REGIONS, FIT_REGIONS, baseRegion, baseSocket, recommendedWeaponLength,
} from "@/domain/base-measurements";
import { PROMPT_VERSION, type ProductionReference } from "@/domain/production-job";
import { buildModelPrompt } from "./modelPromptTemplate";
import { buildTexturePrompt } from "./texturePromptTemplate";
import type { GeneratedPrompts, PromptContext } from "./promptTypes";

export interface PromptOptions {
  budgetProfile?: BudgetProfile;
  alphaPolicy?: AlphaPolicy;
  references?: ProductionReference[];
  paletteReference?: Partial<Record<PaletteSlot, string>>;
  promptVersion?: number;
}

export function contextFromDraft(draft: AssetDraft, options: PromptOptions = {}): PromptContext {
  const weapon = isWeapon(draft.type);
  const profile = options.budgetProfile ?? TYPE_BUDGET[draft.type];
  const animationTest = TYPE_ANIMATION_TEST[draft.type];
  return {
    draft,
    type: draft.type,
    name: draft.name.trim(),
    id: draft.id.trim(),
    description: draft.description.trim(),
    bodyTypes: [...draft.bodyTypes],
    socket: draft.socket,
    gripPoints: weapon ? [...draft.gripPoints] : [],
    paletteSlots: [...draft.paletteSlots],
    textureResolution: draft.textureResolution,
    isWeapon: weapon,
    handling: weapon ? draft.handling : null,
    animationSet: weapon ? draft.animationSet : null,
    weaponType: weapon ? draft.weaponType : null,
    hairPolicy: draft.hairPolicy,

    promptVersion: options.promptVersion ?? PROMPT_VERSION,
    hideParts: [...draft.hideParts],
    attachment: attachmentSpecFor(draft.type, draft.socket, draft.handling),
    budget: { profile, ...BUDGET_DEFINITION[profile] },
    alphaPolicy: options.alphaPolicy ?? TYPE_ALPHA_POLICY[draft.type],
    socketInfo: baseSocket(draft.socket),
    fitRegions: FIT_REGIONS[draft.type]
      .map((region) => ({ region, box: baseRegion(region) }))
      .filter((entry) => !!entry.box),
    clearanceRegions: [...CLEARANCE_REGIONS[draft.type]],
    weaponLength: weapon ? recommendedWeaponLength(draft.weaponType) : null,
    paletteReference: options.paletteReference ?? DEFAULT_PALETTE,
    references: options.references ?? [],
    animationTest: weapon
      ? { set: draft.animationSet, roles: [...animationTest.roles] }
      : { set: animationTest.set, roles: [...animationTest.roles] },
  };
}

export function buildPrompts(draft: AssetDraft, options: PromptOptions = {}): GeneratedPrompts {
  const ctx = contextFromDraft(draft, options);
  return { model: buildModelPrompt(ctx), texture: buildTexturePrompt(ctx) };
}
