import type { AssetType } from "@/domain/asset-spec";
import {
  BASE_MODEL_PATH, BASE_MODEL_SIZE_METERS, COORD_SYSTEM, TARGET_GAME, type PromptContext,
} from "./promptTypes";

export const STYLE_LINES: string[] = [
  "low-poly",
  "blocky / voxel-inspired",
  "simple geometry, flat / simple surfaces",
  "SRPG character asset, ~2.5-head-tall character proportion",
  "readable from an isometric camera",
  "minimal unnecessary geometry",
  "must not visually diverge from existing base assets",
];

/** Per-type geometry / fit requirements (spec section 23). */
export const TYPE_MODEL_FRAGMENTS: Record<AssetType, string[]> = {
  hair: [
    "must fit the head volume of the base character",
    "must not cover the face excessively; keep the face readable",
    "sits on / around the head, attaches at socket_hair",
  ],
  headgear: [
    "must fit the existing head dimensions without clipping",
    "respect hairPolicy (hide = replaces hair, overlay = coexists with hair)",
    "attaches at socket_headgear",
  ],
  head_accessory: [
    "small accessory (ornament / band / pin); coexists with hair",
    "must not clip through the head or hair silhouette",
    "attaches at socket_head",
  ],
  chest_armor: [
    "overlays the torso; follows the chest bone",
    "avoid clipping into the neck, arms and waist",
    "may declare hideParts for large plating",
  ],
  shoulder_left: [
    "must fit the left shoulder and move with the left upper arm",
    "avoid clipping into the head, neck and chest during arm swing",
  ],
  shoulder_right: [
    "must fit the right shoulder and move with the right upper arm",
    "avoid clipping into the head, neck and chest during arm swing",
  ],
  arm_armor: [
    "wraps the forearm; follows the forearm bone",
    "leave the elbow and wrist free enough to bend",
  ],
  gloves: [
    "fits the existing hand scale; follows the hand bone",
    "keep finger geometry blocky and minimal",
  ],
  waist: [
    "belt / skirt piece around the pelvis",
    "must not lock the upper legs; allow walk / run motion",
  ],
  boots: [
    "covers the lower leg and foot; follows the lower-leg bone",
    "sole should sit near the ground plane in rest pose",
  ],
  weapon: [
    "define a grip_main node at the hand contact point (origin of the grip)",
    "for two_hand also define grip_sub for the support hand",
    "respect the declared weapon handling and fit the existing hand scale",
    "blade / head points along local +Y (up) in rest orientation",
  ],
  shield: [
    "held in the off hand; define grip_main at the handle",
    "flat inner face toward the forearm; avoid clipping the arm",
  ],
  back: [
    "mounted on the upper back; follows the body bone",
    "keep clearance from the head and shoulders",
  ],
};

const bullet = (lines: string[]) => lines.map((l) => `- ${l}`).join("\n");

export function buildModelPrompt(ctx: PromptContext): string {
  const gripLine = ctx.isWeapon
    ? `Grip Point: ${ctx.gripPoints.join(", ") || "grip_main"} (grip_main -> socket_hand_right${ctx.handling === "two_hand" ? ", grip_sub -> socket_hand_left" : ctx.handling === "off_hand" ? " / off_hand -> socket_hand_left" : ""})`
    : "Grip Point: n/a (rigid attachment at the socket)";

  return [
    `# 3D Model Prompt — ${ctx.name || "(unnamed asset)"}`,
    "",
    `Asset Name: ${ctx.name || "(unnamed)"}`,
    `Asset Id: ${ctx.id || "(unset)"}`,
    `Asset Type: ${ctx.type}${ctx.weaponType ? ` (${ctx.weaponType})` : ""}`,
    ctx.description ? `Description: ${ctx.description}` : "Description: (none)",
    "",
    `Target Game: ${TARGET_GAME}`,
    "Style:",
    bullet(STYLE_LINES),
    "",
    `Body Type: ${ctx.bodyTypes.join(", ") || "adult"}`,
    "",
    "## Base model & fit",
    "This asset must be designed to fit the existing SRPG base character.",
    `Reference base model: ${BASE_MODEL_PATH}`,
    "Do not assume the AI agent can open this file locally. Design to the numbers below.",
    "",
    `Base rest-pose size (metres, X/Y/Z): ${BASE_MODEL_SIZE_METERS.x} / ${BASE_MODEL_SIZE_METERS.y} / ${BASE_MODEL_SIZE_METERS.z}`,
    `Coordinate system: ${COORD_SYSTEM.up} up, ${COORD_SYSTEM.forward} forward, ${COORD_SYSTEM.left} left`,
    `Unit / scale: ${COORD_SYSTEM.unit}`,
    `Attachment Socket: ${ctx.socket}`,
    `Expected attachment point: asset local origin aligns to ${ctx.socket}; keep the asset centred on its attach point.`,
    "Orientation: match the base character facing (+X forward); no extra root rotation.",
    "Pivot / Origin: model origin (0,0,0) = attachment point; do not offset the mesh from its origin.",
    "",
    gripLine,
    "",
    "## Geometry Requirements",
    bullet(TYPE_MODEL_FRAGMENTS[ctx.type]),
    "",
    "## Low-poly Requirement",
    bullet([
      "keep triangle count minimal (target < 4000 tris for this asset)",
      "no bevels, no subdivision, no rounded high-poly detail",
      "silhouette must read at isometric distance",
    ]),
    "",
    "## Material Requirement",
    bullet([
      "single material where possible, at most 4",
      "unlit / simple PBR; flat base colour, roughness ~1, metallic 0 unless metal",
      `colour comes from palette slots at runtime: ${ctx.paletteSlots.join(", ") || "(none)"}`,
      "no baked lighting, no ambient occlusion baked into the texture",
    ]),
    "",
    "## UV Requirement",
    bullet([
      `single UV set, non-overlapping, laid out for a ${ctx.textureResolution}x${ctx.textureResolution} pixel texture`,
      "align UV islands to the pixel grid; no sub-pixel seams",
      "leave 1px padding between islands",
    ]),
    "",
    "## Output Format",
    bullet([
      "GLB (glTF 2.0 binary), +Y up, metres",
      "mesh + named grip nodes only; no camera, no lights",
      ctx.isWeapon ? "include empty nodes named exactly grip_main / grip_sub" : "single root node at the asset origin",
      "separate PNG texture (see Texture Prompt)",
    ]),
    "",
  ].join("\n");
}
