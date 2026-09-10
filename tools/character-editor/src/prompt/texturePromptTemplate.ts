import type { AssetType } from "@/domain/asset-spec";
import { BASE_MODEL_PATH, type PromptContext } from "./promptTypes";

export const TEXTURE_STYLE_LINES: string[] = [
  "pixel-art-friendly texture, authored at native resolution",
  "nearest-neighbor rendering (no bilinear filtering, no mipmaps)",
  "UV-aware design: paint to the model's UV islands, not a generic sheet",
  "no unnecessary gradients; use flat colour blocks with at most light 1-2 step shading",
  "readable from an isometric camera at gameplay distance",
  "consistent light direction (top-left) with existing base assets",
];

export const TYPE_TEXTURE_FRAGMENTS: Record<AssetType, string[]> = {
  hair: ["one dominant hair tone + one shadow step", "keep strand detail implied, not drawn per-pixel noisy"],
  headgear: ["metal / cloth blocks separated cleanly for palette slots", "small rivets or trim at most 1px"],
  head_accessory: ["tiny readable shapes; avoid fine detail that vanishes at distance"],
  chest_armor: ["separate primary / secondary / metal / leather regions by UV island"],
  shoulder_left: ["match the chest armor palette regions"],
  shoulder_right: ["match the chest armor palette regions"],
  arm_armor: ["plate vs strap regions clearly separated"],
  gloves: ["leather grain implied with a single shadow step"],
  waist: ["belt vs cloth regions separated for palette slots"],
  boots: ["sole darker; leather body one tone + one shadow"],
  weapon: ["blade / haft / grip regions separated by UV island", "edge highlight at most 1px"],
  shield: ["face vs rim vs boss regions separated", "optional emblem area kept simple and centred"],
  back: ["large flat regions; minimal internal detail"],
};

const bullet = (lines: string[]) => lines.map((l) => `- ${l}`).join("\n");

export function buildTexturePrompt(ctx: PromptContext): string {
  const res = `${ctx.textureResolution} x ${ctx.textureResolution}`;
  return [
    `# Texture Prompt — ${ctx.name || "(unnamed asset)"}`,
    "",
    `Asset: ${ctx.name || "(unnamed)"} (${ctx.type}${ctx.weaponType ? ` / ${ctx.weaponType}` : ""}), id ${ctx.id || "(unset)"}`,
    `For the model produced from the 3D Model Prompt, fitting ${BASE_MODEL_PATH}.`,
    "",
    `Texture Resolution: ${res}` +
      (ctx.isWeapon ? "  (weapons may use 16/32/48/64; keep square, power-of-two preferred)" : "  (base standard; armor / hair must match base spec)"),
    "",
    "## Style",
    bullet(TEXTURE_STYLE_LINES),
    "",
    "## Palette Slots",
    ctx.paletteSlots.length
      ? bullet([
          `paint these regions as flat, separable colour blocks: ${ctx.paletteSlots.join(", ")}`,
          "each palette slot region must be a contiguous set of UV islands (recoloured at runtime)",
          "do not bake final colours in — provide neutral mid-tones per slot",
        ])
      : "- no palette slots declared; use fixed flat colours",
    "",
    "## Type-specific",
    bullet(TYPE_TEXTURE_FRAGMENTS[ctx.type]),
    "",
    "## Transparency",
    ctx.type === "hair" || ctx.type === "head_accessory" || ctx.type === "back"
      ? "- alpha allowed for silhouette edges; use 1-bit alpha (no soft edges), premultiplied off"
      : "- no alpha; fully opaque",
    "",
    "## Output Format",
    bullet([
      `PNG, ${res}, 8-bit, sRGB`,
      "no metadata layers; single flattened image",
      "1px padding around UV islands; background fill = nearest island colour (avoid black bleed)",
    ]),
    "",
  ].join("\n");
}
