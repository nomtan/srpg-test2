// Weapon prompt rules (spec section 16, 17, 30).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

export const weaponTemplate: TypeTemplate = {
  geometry: (ctx) => {
    const lines = [
      `Weapon type: ${ctx.weaponType ?? "sword"}`,
      `Handling: ${ctx.handling ?? "one_hand"}`,
      `Animation set it must work with: ${ctx.animationSet ?? "onehand_sword"}`,
      "Fit the existing hand scale: the grip cross-section must be small enough for the base character's hand.",
    ];
    if (ctx.weaponLength) {
      lines.push(`Overall length: ${ctx.weaponLength.min} - ${ctx.weaponLength.max} m, measured against the base character height.`);
    }
    for (const grip of ctx.attachment.gripPoints) {
      lines.push(
        grip === "grip_main"
          ? "Define `grip_main`: an empty node at the primary hand contact point. This is the asset's anchor."
          : "Define `grip_sub`: an empty node at the support hand contact point, on the same axis as grip_main.",
      );
    }
    if (!ctx.attachment.gripPoints.includes("grip_sub") && ctx.handling === "two_hand") {
      lines.push("Two-hand handling requires `grip_sub` in addition to `grip_main`.");
    }
    lines.push("Blade / head points along local +Y from the grip; the grip end is toward local -Y.");
    return lines;
  },
  negatives: () => [
    ...onlyThisAsset("sword / weapon", ["hand", "arm", "character", "environment", "effects", "trails", "scabbard"]),
    "Do not include a hand or any part of the character holding it.",
    "Do not rotate the weapon to compensate for a hand pose — the character hand is never rotated to fit the weapon.",
  ],
  texture: () => [
    "Blade / haft / grip regions separated by UV island so metal and leather palette slots stay independent.",
    "Edge highlight at most 1px along the cutting edge.",
    "No reflections, no specular streaks, no engraved text.",
  ],
  extraSections: (ctx) => [
    {
      title: "## WEAPON ORIENTATION",
      lines: [
        "The weapon must use the project's standard weapon orientation.",
        "Do not manually rotate the character hand to fit the weapon.",
        `The asset is aligned by its grip node to ${ctx.attachment.gripAlignment.grip_main ?? "socket_hand_right"}; the character's hand pose is fixed.`,
        "Standard orientation: grip axis along local Y, blade / head toward +Y, the weapon's flat face toward local Z.",
        "The socket alignment implemented in Phase 2-5 is authoritative; author to it rather than pre-rotating the mesh.",
      ],
    },
  ],
};
