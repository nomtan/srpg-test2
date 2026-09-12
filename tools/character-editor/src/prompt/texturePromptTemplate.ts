// Phase 9 Texture Prompt (spec section 18-23). Palette slots, resolution and the transparency
// policy all come from the Asset Definition, so the texture stays palette-swap compatible.
import { PROMPT_VERSION } from "@/domain/production-job";
import { TYPE_TEMPLATES } from "./templates";
import { ISOMETRIC_LINES, bullet, referenceBlock } from "./templates/common";
import { BASE_MODEL_PATH, type PromptContext } from "./promptTypes";

/** Spec section 18. */
export const TEXTURE_STYLE_LINES: string[] = [
  "pixel-art-friendly",
  "low resolution — paint at the native texture size, never downscale a large painting",
  "hard colour boundaries",
  "minimal gradient",
  "minimal noise",
  "nearest-neighbor friendly (no bilinear filtering, no mipmaps)",
  "readable from isometric distance",
  "UV-aware: paint to the model's UV islands, not a generic sheet",
  "consistent light direction (top-left) with the existing base assets",
];

/** Spec section 22. */
export const GRADIENT_RULE_LINES: string[] = [
  "Avoid photographic gradients.",
  "Use clear clustered colors suitable for palette replacement.",
  "At most one shadow step and one highlight step per region.",
];

function alphaLines(ctx: PromptContext): string[] {
  switch (ctx.alphaPolicy) {
    case "alpha_required":
      return [
        "Alpha is REQUIRED for this asset type.",
        "1-bit alpha only (fully opaque or fully transparent); no soft edges, no partial alpha.",
        "Keep the alpha shape aligned to the pixel grid.",
      ];
    case "alpha_allowed":
      return [
        "Alpha is ALLOWED but not required; prefer solid geometry over an alpha cutout where possible.",
        "If used: 1-bit alpha only (no soft edges), premultiplied off.",
      ];
    default:
      return ["Alpha is FORBIDDEN for this asset type. Deliver a fully opaque texture."];
  }
}

function paletteLines(ctx: PromptContext): string[] {
  if (!ctx.paletteSlots.length) return ["No palette slots declared; use fixed flat colours."];
  const lines = [
    `Usable palette slots: ${ctx.paletteSlots.join(", ")}`,
    "Paint each slot's area as a flat, separable colour block; one slot must never bleed into another.",
    "Each palette slot region must be a contiguous set of UV islands so it can be recoloured at runtime.",
    "Which region belongs to which palette slot matters more than the exact colour you pick.",
  ];
  const reference = Object.entries(ctx.paletteReference).filter(([slot]) => ctx.paletteSlots.includes(slot));
  if (reference.length) {
    lines.push(`Reference colours (guidance only, the runtime replaces them): ${reference.map(([slot, hex]) => `${slot}=${hex}`).join(", ")}`);
    lines.push("Do not treat those hex values as final: deliver neutral mid-tones that recolour cleanly.");
  }
  return lines;
}

export function buildTexturePrompt(ctx: PromptContext): string {
  const res = `${ctx.textureResolution} x ${ctx.textureResolution}`;
  const template = TYPE_TEMPLATES[ctx.type];
  return [
    `# Texture Prompt — ${ctx.name || "(unnamed asset)"}`,
    `<!-- promptVersion: ${ctx.promptVersion ?? PROMPT_VERSION} · assetType: ${ctx.type} · assetId: ${ctx.id || "(unset)"} -->`,
    "",
    `Asset: ${ctx.name || "(unnamed)"} (${ctx.type}${ctx.weaponType ? ` / ${ctx.weaponType}` : ""}), id \`${ctx.id || "(unset)"}\``,
    `For the model produced from the Model Prompt, fitting ${BASE_MODEL_PATH}.`,
    "",
    "## RESOLUTION",
    bullet([
      `Texture resolution: ${res}`,
      ctx.isWeapon
        ? "Weapons may use a per-asset resolution; this value comes from the Asset Definition and is the one to use."
        : "Base standard resolution; armor / hair must match it.",
      "Square, power-of-two preferred, 8-bit PNG, sRGB.",
    ]),
    "",
    "## STYLE",
    bullet(TEXTURE_STYLE_LINES),
    "",
    "## ISOMETRIC READABILITY",
    bullet(ISOMETRIC_LINES),
    "",
    "## PALETTE SLOTS",
    bullet(paletteLines(ctx)),
    "",
    "## GRADIENT RULE",
    bullet(GRADIENT_RULE_LINES),
    "",
    "## TRANSPARENCY",
    bullet(alphaLines(ctx)),
    "",
    "## TYPE-SPECIFIC",
    bullet(template.texture(ctx)),
    "",
    "## REFERENCE INFORMATION",
    referenceBlock(ctx),
    "",
    "## OUTPUT FORMAT",
    bullet([
      `PNG, ${res}, 8-bit, sRGB`,
      "Single flattened image; no layers, no metadata.",
      "1px padding around UV islands; background fill = nearest island colour (avoid black bleed).",
      `File name and location: \`${ctx.id || "<asset_id>"}/texture.png\` (see DELIVERABLES in the Model Prompt).`,
      "Assign the texture inside the `.bbmodel` too, so the Blockbench source renders the same as the GLB.",
    ]),
    "",
    "## DO NOT",
    bullet([
      "Do not bake lighting, shadows or ambient occlusion.",
      "Do not add text, logos or signatures.",
      "Do not paint at a high resolution and downscale.",
      "Do not use photographic textures or noise filters.",
    ]),
    "",
  ].join("\n");
}
