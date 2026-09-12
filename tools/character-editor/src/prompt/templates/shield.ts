// Shield prompt rules (spec section 31).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

export const shieldTemplate: TypeTemplate = {
  geometry: (ctx) => [
    "Carried in the off hand (off_hand slot).",
    "Define `grip_main`: an empty node at the handle, on the inner face, where the hand closes around it.",
    `grip_main aligns to ${ctx.attachment.gripAlignment.grip_main ?? "socket_hand_left"}.`,
    "The front-facing shield surface points away from the character along the character's forward axis.",
    "Hand clearance: leave space between the handle and the inner face for the hand volume.",
    "Body clearance: the inner face must not intersect the forearm or torso in idle pose.",
    "Keep the outline a single strong shape; the shield is a major silhouette element.",
  ],
  negatives: () => [
    ...onlyThisAsset("shield", ["hand", "arm", "character", "environment", "straps rigged to the arm"]),
    "Do not model a forearm inside the shield.",
    "Do not add a heraldic logo or text; an emblem area may be blocked out but left generic.",
  ],
  texture: () => [
    "Face / rim / boss regions separated by UV island.",
    "Optional emblem area kept simple, centred, and on its own palette slot.",
    "Inner face may be a single flat leather tone.",
  ],
};
