// Back equipment prompt rules (spec section 33).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

export const backTemplate: TypeTemplate = {
  geometry: () => [
    "Mounted on the upper back at socket_back; follows the body bone.",
    "Body clearance: the mounting face sits against the torso without intersecting it.",
    "Weapon clearance: leave room for a main-hand weapon and its swing; do not occupy the hand-side volume.",
    "Head and shoulder clearance: the top of the piece must stay below the head and inboard of the shoulders.",
    "Silhouette first: a back item is read almost entirely as an outline from the isometric camera.",
  ],
  negatives: () => [
    ...onlyThisAsset("back equipment", ["body", "head", "arms", "weapon in hand", "cloth simulation"]),
    "Do not add a cape that would need physics; a rigid shape only.",
  ],
  texture: () => [
    "Large flat regions; minimal internal detail.",
    "Strap regions on the leather palette slot, body on primary / secondary.",
  ],
};
