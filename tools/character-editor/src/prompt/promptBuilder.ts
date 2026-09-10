import { isWeapon, type AssetDraft } from "@/domain/asset-spec";
import { buildModelPrompt } from "./modelPromptTemplate";
import { buildTexturePrompt } from "./texturePromptTemplate";
import type { GeneratedPrompts, PromptContext } from "./promptTypes";

export function contextFromDraft(draft: AssetDraft): PromptContext {
  const weapon = isWeapon(draft.type);
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
  };
}

export function buildPrompts(draft: AssetDraft): GeneratedPrompts {
  const ctx = contextFromDraft(draft);
  return { model: buildModelPrompt(ctx), texture: buildTexturePrompt(ctx) };
}
