// Shoulder armor prompt rules (spec section 29).
import type { TypeTemplate } from "./types";
import { onlyThisAsset } from "./types";

function build(side: "left" | "right"): TypeTemplate {
  const other = side === "left" ? "right" : "left";
  return {
    geometry: (ctx) => [
      `This is the ${side.toUpperCase()} shoulder piece only. The ${other} shoulder is a separate asset.`,
      `Fit the ${side} shoulder socket (${ctx.attachment.socket}) and move with the ${side} upper arm.`,
      "Sits over the shoulder joint; the inner face follows the arm, not the torso.",
      "Avoid head collision: keep clearance above and inboard so the piece never intersects the head or neck.",
      "Avoid chest collision: the inboard edge must not push into the torso when the arm swings forward.",
      "Test mentally against idle / run / attack — the piece rotates with the arm, not with the body.",
    ],
    negatives: () => [
      ...onlyThisAsset(`${side} shoulder armor`, ["arm", "chest armor", "head", "body", "weapon", `the ${other} shoulder`]),
      "Do not bridge the two shoulders with a single connected piece.",
      "Do not model a neck guard here; that belongs to chest armor or headgear.",
    ],
    texture: () => [
      "Match the chest armor palette regions so a set reads as one set.",
      "Keep the outer plate as one large flat area with a single rim step.",
    ],
  };
}

export const shoulderLeftTemplate = build("left");
export const shoulderRightTemplate = build("right");
