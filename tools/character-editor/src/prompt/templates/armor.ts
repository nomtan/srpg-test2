// Body armor prompt rules (spec section 28) plus the limb pieces that follow the same contract.
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

const hidePartsLine = (hideParts: string[]) =>
  hideParts.length
    ? `This asset hides the following base meshes when equipped: ${hideParts.join(", ")}. Model enough coverage to replace them.`
    : "This asset declares no hideParts, so the base body stays visible underneath: keep it as an overlay, not a replacement.";

export const chestArmorTemplate: TypeTemplate = {
  geometry: (ctx) => [
    "Fit the existing torso; the piece overlays the chest and follows the chest bone.",
    "Do not replace the entire body unless the design genuinely requires it.",
    hidePartsLine(ctx.hideParts),
    "Avoid excessive clipping into the neck, shoulders, arms and waist.",
    "Preserve limb articulation: the shoulder and waist openings must not lock the arms or legs.",
    "Keep the back as readable as the front; the isometric camera sees both.",
  ],
  negatives: () => [
    ...onlyThisAsset("chest armor", ["head", "face", "hair", "arms", "legs", "weapon", "shield"]),
    "Do not model a body inside the armor.",
    "Do not attach shoulder pauldrons here — shoulders are separate assets.",
  ],
  texture: () => [
    "Separate primary / secondary / metal / leather regions by UV island.",
    "Plate edges get at most a 1px lighter rim; no gradient shading.",
  ],
};

export const armArmorTemplate: TypeTemplate = {
  geometry: () => [
    "Wraps the forearm and follows the forearm bone.",
    "Leave the elbow and wrist free enough to bend during the attack animation.",
    "Model one side only; the opposite side is mirrored by the Character Builder if required.",
  ],
  negatives: () => [
    ...onlyThisAsset("arm armor", ["hand", "shoulder", "body", "weapon"]),
    "Do not close the sleeve around a modelled arm.",
  ],
  texture: () => ["Plate vs strap regions clearly separated for palette slots."],
};

export const glovesTemplate: TypeTemplate = {
  geometry: () => [
    "Fits the existing hand scale and follows the hand bone.",
    "Keep finger geometry blocky and minimal — a mitten silhouette reads better than fingers at this scale.",
    "Leave the grip area unobstructed so a weapon can sit at the hand socket.",
  ],
  negatives: () => [
    ...onlyThisAsset("gloves", ["arm", "body", "weapon"]),
    "Do not model individual finger joints.",
  ],
  texture: () => ["Leather grain implied with a single shadow step; cuff separated for a second palette slot."],
};

export const waistTemplate: TypeTemplate = {
  geometry: () => [
    "Belt / skirt piece around the pelvis, following the pelvis bone.",
    "Must not lock the upper legs: keep the walk and run motion possible.",
    "If the piece is a skirt, keep the hem above the knee or split it so the legs can swing.",
  ],
  negatives: () => [
    ...onlyThisAsset("waist piece", ["legs", "torso", "weapon"]),
    "Do not model the pelvis underneath.",
  ],
  texture: () => ["Belt vs cloth regions separated for palette slots; buckle on the metal slot."],
};

export const bootsTemplate: TypeTemplate = {
  geometry: () => [
    "Covers the lower leg and foot, following the lower-leg bone.",
    "The sole should sit near the ground plane in rest pose; do not float the character.",
    "Keep the ankle able to rotate for the run cycle.",
  ],
  negatives: () => [
    ...onlyThisAsset("boots", ["legs above the knee", "body", "ground", "shadow plane"]),
    "Do not model toes.",
  ],
  texture: () => ["Sole darker; leather body one tone plus one shadow step."],
};
