// Phase 9 shared prompt fragments (spec section 9, 10, 13, 17, 34, 35).
//
// Every block here is reused by all asset types. Type-specific rules live in their own template
// file next to this one, so no single giant prompt string exists (spec section 26).
import type { AssetType } from "@/domain/asset-spec";
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
  // The measured base is the authority: quoting a fixed "2.5-3 heads" band alongside it goes stale
  // the moment the artist edits base_1.bbmodel, and a prompt that contradicts its own numbers is
  // worse than no guidance.
  `SRPG character proportion: this base measures ${BASE_CHARACTER.headsTall} heads tall — match that, ` +
    "not realistic human proportions (~7.5 heads)",
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
  "Do not deliver only a `.glb`: the editable `.bbmodel` source is part of the deliverable, not a bonus.",
  "Do not rename the delivered files or change the folder structure.",
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
      `Body region \`${region}\` measures ${box.size.join(" x ")} m (bounding box), centre ${box.center.join(", ")} m, Y range ${box.min[1]} - ${box.max[1]} m`,
  );
  if (!lines.length) lines.push("No measured fit region for this asset type; keep proportions consistent with the character height above.");

  const target = ctx.targetSize;
  if (target && target.coverage !== 1) {
    // The body measurement alone produces a piece the same size as the limb, which reads as too
    // small for anything worn over it. State the size the asset itself should be.
    lines.push(
      `**Target asset size: about ${target.size.join(" x ")} m** — roughly ${target.coverage}x the ` +
      `\`${target.region}\` region, because this piece is worn OVER that body part and has to overhang it.`,
    );
    lines.push(
      `An asset that merely matches the ${target.region} measurement (${ctx.fitRegions[0]?.box.size.join(" x ")} m) ` +
      "is too small and will be sent back for revision.",
    );
  } else if (target) {
    lines.push(`Target asset size: about ${target.size.join(" x ")} m, following the \`${target.region}\` region closely.`);
  }

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
    lines.push(
      ctx.socketInfo.status === "calibrated_to_region_centre"
        ? `Socket calibration: centred on the measured \`${ctx.socketInfo.region}\` region, so the asset's ` +
          "attachment point and the fit region above share one anchor."
        : `Socket calibration status: ${ctx.socketInfo.status} — treat the position as an anchor, not a validated grip pose.`,
    );
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
    `${COORD_SYSTEM.up} up, ${COORD_SYSTEM.forward} forward, ${COORD_SYSTEM.left} left, ${COORD_SYSTEM.right} right — same as the base character.`,
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
  const id = ctx.id || "<asset_id>";
  return bullet([
    `**\`source/${id}.bbmodel\` is REQUIRED, not optional.** Author the asset in Blockbench format ` +
      "and ship the editable source; a delivery without it is incomplete and will be sent back for revision.",
    "The `.bbmodel` is the master: `model.glb` must be exported *from it*, not modelled separately.",
    "Blockbench source format: `\"meta\": { \"model_format\": \"free\", \"format_version\": \"5.0\" }`, " +
      "elements as `mesh` or `cube`, one root group named after the asset id.",
    "Runtime: `model.glb` (glTF 2.0 binary), +Y up, metres.",
    `Texture: \`texture.png\`, ${ctx.textureResolution}x${ctx.textureResolution} (see the Texture Prompt).`,
    "Metadata: `asset.json`, copied verbatim from the block below.",
    "Mesh and named empty nodes only: no cameras, no lights, no animation, no skin/armature.",
    ctx.attachment.gripPoints.length
      ? `Include empty nodes named exactly: ${ctx.attachment.gripPoints.join(", ")} (in BOTH the .bbmodel and the .glb)`
      : "A single root node at the asset origin.",
  ]);
}

/**
 * Spec section 35 + the repository asset directory convention (Phase 4 section 9). The AI agent
 * must hand back one folder in exactly this shape, so the Import step can pick the files up
 * without the user renaming anything.
 */
export function deliverablesBlock(ctx: PromptContext): string {
  const id = ctx.id || "<asset_id>";
  const rows: [string, string][] = [
    ["├─ source/", ""],
    [`│   └─ ${id}.bbmodel`, "editable Blockbench source (REQUIRED — the master file)"],
    ["├─ model.glb", "runtime mesh, exported from the .bbmodel"],
    ["├─ texture.png", `${ctx.textureResolution}x${ctx.textureResolution}, nearest-neighbor`],
    ["└─ asset.json", "metadata, copied verbatim from this prompt"],
  ];
  const width = Math.max(...rows.map(([left]) => left.length)) + 4;
  return [
    "Deliver ONE folder, named after the asset id, with exactly this structure:",
    "",
    "```",
    `${id}/`,
    ...rows.map(([left, note]) => (note ? `${left.padEnd(width)}${note}` : left)),
    "```",
    "",
    bullet([
      "File names are fixed. Do not add a version suffix, a timestamp or your own naming.",
      "Provide the folder as a downloadable archive (zip) or as those exact paths — one asset per folder.",
      "Do not nest the folder inside another directory level, and do not flatten `source/` away.",
      "Do not include extra files: no previews, no screenshots, no .blend, no README, no license headers.",
      "`asset.json` names a `thumbnail.png`: that one is generated by the Character Workshop after import, " +
        "so do NOT produce it — keep the reference in asset.json as it is.",
      `In the repository this folder lands at \`assets/character-assets/${ctx.categoryDir}/${id}/\`; ` +
        "keep the internal layout identical so it can be dropped in as-is.",
    ]),
    "",
    "Checklist before you hand the folder back:",
    "",
    bullet([
      `\`source/${id}.bbmodel\` exists and opens in Blockbench`,
      "`model.glb` was exported from that .bbmodel and matches it",
      `\`texture.png\` is exactly ${ctx.textureResolution}x${ctx.textureResolution}`,
      "`asset.json` is byte-identical to the block below",
      ...ctx.attachment.gripPoints.map((g) => `node \`${g}\` is present in both the .bbmodel and the .glb`),
    ]),
  ].join("\n");
}

/** The exact asset.json the delivery must contain, so nothing has to be re-typed by hand. */
export function assetJsonBlock(ctx: PromptContext): string {
  return [
    "Copy this file into the delivery folder as `asset.json`, unchanged:",
    "",
    "```json",
    ctx.assetJson.trimEnd(),
    "```",
  ].join("\n");
}

export function validationTargetBlock(ctx: PromptContext): string {
  const id = ctx.id || "<asset_id>";
  const lines = [
    `Delivery folder \`${id}/\` contains source/${id}.bbmodel, model.glb, texture.png and asset.json`,
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
/**
 * What to crop a whole-character illustration down to, per asset type. Concept art is usually one
 * full-body drawing, so the prompt has to name the part instead of leaving the agent to guess.
 */
export const REFERENCE_FOCUS: Record<AssetType, string> = {
  hair: "the hairstyle",
  headgear: "the helmet / headwear",
  head_accessory: "the head accessory (ornament, band, pin)",
  chest_armor: "the torso armour",
  shoulder_left: "the shoulder pauldron on the character's LEFT side",
  shoulder_right: "the shoulder pauldron on the character's RIGHT side",
  arm_armor: "the forearm armour / bracer",
  gloves: "the gloves",
  waist: "the belt / waist piece",
  boots: "the boots",
  weapon: "the weapon held in the character's hand",
  shield: "the shield",
  back: "the equipment mounted on the character's back",
};

/**
 * Spec section 24-25, extended for the common workflow: a single full-body illustration is
 * attached to the request and the agent has to produce ONE part from it.
 *
 * The protocol is stated unconditionally, because the image is usually attached directly to the
 * AI session rather than registered in the tool — the package cannot know it is there.
 */
export function referenceBlock(ctx: PromptContext, focus: "geometry" | "texture" = "geometry"): string {
  const part = REFERENCE_FOCUS[ctx.type];
  const side = ctx.attachment.side;

  const protocol = [
    `Treat any attached illustration as the design authority for **${part} only**.`,
    "The image will usually show the whole character. Everything outside that part is context for " +
      "consistency, never something to model or paint.",
    focus === "texture"
      ? "Take from it: how the colour and material regions divide, trim placement, wear level, motif shapes."
      : "Take from it: silhouette, shape language, proportion within the part, where plates / straps / " +
        "trim divide, decorative motifs.",
    "Do not take from it: overall scale, camera perspective, lighting, painted rendering, line weight, " +
      "or any neighbouring part of the character.",
    focus === "texture"
      ? "The PALETTE SLOTS and GRADIENT RULE sections win over the illustration: reduce painted shading " +
        `to flat blocks that recolour cleanly at ${ctx.textureResolution}x${ctx.textureResolution}.`
      : "The SCALE and PROPORTION sections win over the illustration. Concept art is not to scale: " +
        "reproject the design onto the target size given above rather than copying image proportions.",
    "The STYLE and budget sections win over the illustration. Reduce painted detail to blocky low-poly " +
      "geometry and keep only what still reads at isometric distance; drop the rest.",
    side !== "center"
      ? `The illustration shows both sides. Model only the ${side.toUpperCase()} one — the character's own ` +
        `${side}, which is ${side === "left" ? "-Z" : "+Z"} in this project. Check the side before exporting.`
      : "",
    "If the part is hidden, cropped, or ambiguous in the image, choose the simplest reading consistent " +
      "with what is visible; do not invent unrelated detail.",
    "Keep it consistent with the rest of the character in the image — material, trim colour and wear " +
      "level — so parts produced separately still read as one set.",
    "The illustration never overrides the attachment contract: socket, attachment point and orientation " +
      "come from this document.",
  ];

  const lines = [
    "**If an image is attached to this request:**",
    "",
    bullet(protocol),
  ];

  if (ctx.references.length) {
    const registered = ctx.references.map((ref) => {
      const label = REFERENCE_ROLE_LABEL[ref.role];
      const how =
        ref.role === "shape" ? "match the silhouette and proportions, not the rendering style"
          : ref.role === "style" ? "match the rendering / surface treatment, not the exact shape"
            : ref.role === "color" ? "use only as a hue guide; final colours come from the palette slots"
              : "overall intent only; do not copy verbatim";
      const scope = ref.view === "full_body"
        ? ` · whole-character art: use ${part} from it and ignore the rest`
        : "";
      return `${label} — ${ref.file ?? "(note only)"} [${ref.view}]: ${how}${scope}${ref.note ? ` · ${ref.note}` : ""}`;
    });
    lines.push("", "**Reference files shipped with this package:**", "", bullet(registered));
  } else {
    lines.push("", "No reference file is shipped with this package; the written rules above are the specification.");
  }

  return lines.join("\n");
}
