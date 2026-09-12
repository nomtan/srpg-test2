// Phase 9 shared prompt fragments (spec section 9, 10, 13, 17, 34, 35).
//
// Every block here is reused by all asset types. Type-specific rules live in their own template
// file next to this one, so no single giant prompt string exists (spec section 26).
import { BASE_CHARACTER, BASE_COORDINATE_INFO } from "@/domain/base-measurements";
import { ALPHA_POLICY_LABEL } from "@/domain/production-profile";
import { REFERENCE_ROLE_LABEL } from "@/domain/production-job";
import { BASE_MODEL_PATH, COORD_SYSTEM, TARGET_GAME, type PromptContext } from "../promptTypes";

export const bullet = (lines: readonly string[]) => lines.filter(Boolean).map((l) => `- ${l}`).join("\n");

export const section = (title: string, body: string) => `${title}\n\n${body}`;

/** Spec section 9. Deliberately describes the project's own blocky look, not another game's. */
export const STYLE_LINES: string[] = [
  "low-poly",
  "blocky",
  "voxel-inspired",
  "simple geometry",
  `SRPG character scale: roughly 2.5-3 heads tall (this base measures ${BASE_CHARACTER.headsTall} heads)`,
  "readable from an isometric camera",
  "strong silhouette",
  "minimal tiny details",
  "flat / simple surfaces",
  "this project's own blocky low-poly look — do not copy any existing game's assets or trade dress",
];

/** Spec section 10. */
export const ISOMETRIC_LINES: string[] = [
  "The asset must remain visually readable from a distant isometric SRPG camera.",
  "Avoid important details that are only visible from extremely close range.",
  "Silhouette carries the read; internal detail is secondary.",
];

/** Spec section 34. */
export const NEGATIVE_LINES: string[] = [
  "Do not modify the base character.",
  "Do not add unrelated equipment.",
  "Do not add environment geometry.",
  "Do not add text or logos.",
  "Do not add unnecessary subdivision.",
  "Do not use photorealistic materials.",
  "Do not create excessive tiny geometry.",
  "Do not bake lighting, shadows or ambient occlusion into the texture.",
  "Do not rig, skin or animate the asset; the base character owns the rig.",
];

export function purposeBlock(ctx: PromptContext): string {
  return [
    `Produce ONE equippable ${ctx.type} asset for ${TARGET_GAME}.`,
    `Asset: ${ctx.name || "(unnamed)"} (id \`${ctx.id || "(unset)"}\`)`,
    ctx.description ? `Intent: ${ctx.description}` : "Intent: (no description given)",
    "The asset is combined with the base character by the project's Character Builder; you are not building a character.",
  ].join("\n");
}

/** Spec section 7. */
export function referenceModelBlock(): string {
  return [
    "The asset must fit the existing SRPG character base.",
    "",
    "Reference source model:",
    BASE_MODEL_PATH,
    "",
    "Do not modify the base model.",
    "Create only the requested asset.",
    "Assume you cannot open that file: design against the measurements below, which were taken from it.",
  ].join("\n");
}

export function scaleBlock(ctx: PromptContext): string {
  const lines = [
    `Character height: ${BASE_CHARACTER.height} m (rest pose, measured)`,
    `Character bounds (X/Y/Z): ${BASE_CHARACTER.size.join(" x ")} m`,
    `Head size: ${BASE_CHARACTER.headHeight} m tall — the character is ~${BASE_CHARACTER.headsTall} heads tall`,
    `Unit / scale: ${COORD_SYSTEM.unit}`,
    `1 field cell = 1 metre; Godot import scale = 1.0`,
  ];
  if (ctx.weaponLength) {
    lines.push(`Recommended overall weapon length: ${ctx.weaponLength.min} - ${ctx.weaponLength.max} m`);
  }
  return bullet(lines);
}

export function proportionBlock(ctx: PromptContext): string {
  const lines = ctx.fitRegions.map(
    ({ region, box }) =>
      `${region}: ${box.size.join(" x ")} m (bounding box), centre ${box.center.join(", ")} m, Y range ${box.min[1]} - ${box.max[1]} m`,
  );
  if (!lines.length) lines.push("No measured fit region for this asset type; keep proportions consistent with the character height above.");
  if (ctx.clearanceRegions.length) {
    lines.push(`Keep clearance from: ${ctx.clearanceRegions.join(", ")}`);
  }
  return bullet(lines);
}

export function attachmentBlock(ctx: PromptContext): string {
  const a = ctx.attachment;
  const lines = [
    `Character socket: ${a.socket}`,
    `Asset attachment point: ${a.assetPoint}`,
  ];
  for (const grip of a.gripPoints) {
    lines.push(`${grip} -> ${a.gripAlignment[grip]}`);
  }
  if (!a.gripPoints.length) {
    lines.push("Rigid attachment: the asset's local origin is placed at the socket, no grip node needed.");
  }
  if (ctx.socketInfo) {
    lines.push(
      `Socket transform (parent \`${ctx.socketInfo.parent}\`, ${ctx.socketInfo.space}): ` +
      `position ${JSON.stringify(ctx.socketInfo.position)}, rotation ${JSON.stringify(ctx.socketInfo.rotation)}, scale ${JSON.stringify(ctx.socketInfo.scale)}`,
    );
    lines.push(`Socket rest-pose world position: ${JSON.stringify(ctx.socketInfo.worldPosition)} m`);
    lines.push(`Socket calibration status: ${ctx.socketInfo.status} — treat the position as an anchor, not a validated grip pose.`);
  }
  return bullet(lines);
}

export function originBlock(ctx: PromptContext): string {
  return bullet([
    ctx.attachment.gripPoints.length
      ? `Model origin (0,0,0) sits at ${ctx.attachment.gripPoints[0]}; the mesh is positioned around it.`
      : "Model origin (0,0,0) = the attachment point. Do not offset the mesh away from its origin.",
    "One root node; no parent transforms baked as node scale or rotation.",
    "No negative or non-uniform scale on any node.",
  ]);
}

export function orientationBlock(): string {
  return bullet([
    `${COORD_SYSTEM.up} up, ${COORD_SYSTEM.forward} forward, ${COORD_SYSTEM.left} left — same as the base character.`,
    "Match the base character facing; do not apply an extra root rotation to compensate.",
    `Axis conversion from the source pipeline: ${BASE_COORDINATE_INFO.axisConversion}.`,
  ]);
}

export function polygonBlock(ctx: PromptContext): string {
  return bullet([
    `Budget profile: ${ctx.budget.profile}`,
    `Target triangles: ~${ctx.budget.targetTriangles}`,
    `Hard ceiling before the asset is flagged: ${ctx.budget.maxTriangles} triangles`,
    "No bevels, no subdivision surfaces, no rounded high-poly detail.",
    "Prefer one extra flat face over a smooth curve.",
  ]);
}

export function materialBlock(ctx: PromptContext): string {
  return bullet([
    `One material where possible; at most ${ctx.budget.maxMaterials}.`,
    "Unlit / simple PBR: flat base colour, roughness ~1, metallic 0 unless the surface is metal.",
    `Runtime colour comes from palette slots: ${ctx.paletteSlots.join(", ") || "(none declared)"}`,
    "No baked lighting and no baked ambient occlusion.",
  ]);
}

export function uvBlock(ctx: PromptContext): string {
  return bullet([
    `Single UV set, non-overlapping, laid out for a ${ctx.textureResolution}x${ctx.textureResolution} pixel texture.`,
    "Align UV islands to the pixel grid; no sub-pixel seams.",
    "Leave 1px padding between islands.",
    "Group each palette slot's faces into contiguous islands so palette swap stays clean.",
  ]);
}

export function namingBlock(ctx: PromptContext): string {
  const lines = [
    `Root node name: ${ctx.id || "<asset_id>"}`,
    "snake_case only; no spaces, no numbering suffixes added by the exporter.",
  ];
  for (const grip of ctx.attachment.gripPoints) {
    lines.push(`Empty node named exactly \`${grip}\` at the corresponding hand contact point.`);
  }
  if (ctx.hideParts.length) {
    lines.push(`This asset declares hideParts: ${ctx.hideParts.join(", ")} — those base meshes are hidden when it is equipped.`);
  }
  return bullet(lines);
}

/** Spec section 35: editable source is preferred, GLB is the runtime format. */
export function outputBlock(ctx: PromptContext): string {
  return bullet([
    "Preferred source: `.bbmodel` (editable Blockbench source) — produce this if you can.",
    "Runtime: `.glb` (glTF 2.0 binary), +Y up, metres.",
    `Texture: separate PNG, ${ctx.textureResolution}x${ctx.textureResolution} (see the Texture Prompt).`,
    "Mesh and named empty nodes only: no cameras, no lights, no animation, no skin/armature.",
    ctx.attachment.gripPoints.length
      ? `Include empty nodes named exactly: ${ctx.attachment.gripPoints.join(", ")}`
      : "A single root node at the asset origin.",
  ]);
}

export function validationTargetBlock(ctx: PromptContext): string {
  const lines = [
    "Model loads as GLB and contains at least one mesh",
    `Triangle count <= ${ctx.budget.maxTriangles}`,
    `Material count <= ${ctx.budget.maxMaterials}`,
    "UV set present on every mesh",
    `Texture is ${ctx.textureResolution}x${ctx.textureResolution} PNG, square`,
    `Transparency policy: ${ALPHA_POLICY_LABEL[ctx.alphaPolicy]}`,
    `Palette slots present: ${ctx.paletteSlots.join(", ") || "(none)"}`,
    `Body types: ${ctx.bodyTypes.join(", ") || "adult"}`,
    "Bounding box is plausible against the measured fit region above",
    "Asset origin near (0,0,0)",
  ];
  for (const grip of ctx.attachment.gripPoints) lines.push(`Node \`${grip}\` exists`);
  lines.push(`Animation test after import: ${ctx.animationTest.set} / ${ctx.animationTest.roles.join(", ")}`);
  return bullet(lines);
}

/** Spec section 24-25: references carry a role so the prompt can use them differently. */
export function referenceBlock(ctx: PromptContext): string {
  if (!ctx.references.length) return "No reference images supplied. Follow the written style rules above.";
  const byRole = ctx.references.map((ref) => {
    const label = REFERENCE_ROLE_LABEL[ref.role];
    const how =
      ref.role === "shape" ? "match the silhouette and proportions, not the rendering style"
        : ref.role === "style" ? "match the rendering / surface treatment, not the exact shape"
          : ref.role === "color" ? "use only as a hue guide; final colours come from the palette slots"
            : "overall intent only; do not copy verbatim";
    return `${label} — ${ref.file ?? "(note only)"} [${ref.view}]: ${how}${ref.note ? ` · ${ref.note}` : ""}`;
  });
  return bullet(byRole);
}
