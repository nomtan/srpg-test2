// Hair prompt rules (spec section 27).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

export const hairTemplate: TypeTemplate = {
  geometry: () => [
    "Fit the existing head volume; the hair shell sits on and around the head, never replacing it.",
    "Do not generate the face: the base head mesh stays visible under / around the hair.",
    "Avoid excessive clipping into the head, ears and neck; a small intentional overlap is fine.",
    "Maintain a readable silhouette — the hair shape is what identifies the character at distance.",
    "Attach at socket_hair; the hair cap must be centred on the socket.",
    "Headgear compatibility: keep the top of the skull close to the head surface so a helmet can sit over it.",
    "Keep strands as a few chunky blocks, not many thin ones.",
  ],
  negatives: () => [
    ...onlyThisAsset("hair", ["face", "body", "armor", "weapon", "head or skull geometry"]),
    "Do not sculpt facial features into the hair.",
    "Do not add hair physics bones or long dangling geometry that cannot follow the rigid socket.",
  ],
  texture: () => [
    "One dominant hair tone plus one shadow step.",
    "Imply strand direction with flat bands; do not draw per-pixel noise.",
    "Keep the whole asset on the `hair` palette slot so hair colour variation works.",
  ],
};
