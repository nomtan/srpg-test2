// Phase 9 Model Prompt. The section list is fixed by spec section 6 so every generated prompt
// has the same shape regardless of asset type; the type-specific content comes from
// prompt/templates/<type>.ts (spec section 26).
import { PROMPT_VERSION } from "@/domain/production-job";
import { TYPE_TEMPLATES } from "./templates";
import {
  ISOMETRIC_LINES, NEGATIVE_LINES, STYLE_LINES, attachmentBlock, bullet, materialBlock,
  namingBlock, orientationBlock, originBlock, outputBlock, polygonBlock, proportionBlock,
  purposeBlock, referenceBlock, referenceModelBlock, scaleBlock, uvBlock, validationTargetBlock,
} from "./templates/common";
import type { PromptContext } from "./promptTypes";

export { STYLE_LINES };

export function buildModelPrompt(ctx: PromptContext): string {
  const template = TYPE_TEMPLATES[ctx.type];
  const parts: string[] = [
    `# Model Prompt — ${ctx.name || "(unnamed asset)"}`,
    `<!-- promptVersion: ${ctx.promptVersion ?? PROMPT_VERSION} · assetType: ${ctx.type} · assetId: ${ctx.id || "(unset)"} -->`,
    "",
    "## PURPOSE",
    purposeBlock(ctx),
    "",
    "## REFERENCE MODEL",
    referenceModelBlock(),
    "",
    "## ASSET TYPE",
    bullet([
      `Type: ${ctx.type}${ctx.weaponType ? ` (${ctx.weaponType})` : ""}`,
      `Body types: ${ctx.bodyTypes.join(", ") || "adult"}`,
      `Equipment behaviour: ${ctx.isWeapon ? `weapon, ${ctx.handling}` : ctx.type === "shield" ? "off-hand shield" : "rigid attachment"}`,
      ctx.hairPolicy ? `hairPolicy: ${ctx.hairPolicy}` : "",
    ]),
    "",
    "## STYLE",
    bullet(STYLE_LINES),
    "",
    "## ISOMETRIC READABILITY",
    bullet(ISOMETRIC_LINES),
    "",
    "## SCALE",
    scaleBlock(ctx),
    "",
    "## PROPORTION",
    proportionBlock(ctx),
    "",
    "## ATTACHMENT",
    attachmentBlock(ctx),
    "",
    "## ORIGIN / PIVOT",
    originBlock(ctx),
    "",
    "## ORIENTATION",
    orientationBlock(),
    "",
    "## GEOMETRY",
    bullet(template.geometry(ctx)),
    "",
    "## POLYGON REQUIREMENTS",
    polygonBlock(ctx),
    "",
    "## MATERIAL",
    materialBlock(ctx),
    "",
    "## UV",
    uvBlock(ctx),
    "",
    "## NAMING",
    namingBlock(ctx),
    "",
    "## REFERENCE INFORMATION",
    referenceBlock(ctx),
    "",
    "## OUTPUT FORMAT",
    outputBlock(ctx),
    "",
    "## DO NOT",
    bullet([...template.negatives(ctx), ...NEGATIVE_LINES]),
    "",
    "## VALIDATION TARGET",
    validationTargetBlock(ctx),
    "",
  ];

  for (const extra of template.extraSections?.(ctx) ?? []) {
    parts.push(extra.title, bullet(extra.lines), "");
  }
  return parts.join("\n");
}
