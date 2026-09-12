// Phase 9 Revision Prompt generation (spec section 46-47).
//
// Every validation issue code maps to an Issue / Revision pair, so a failed import turns straight
// into an instruction an AI agent can act on without the user re-describing the problem.
import type { ProductionIssue, ProductionJob, ProductionValidation } from "./production-job";
import type { ValidationSpec } from "./production-package";

export interface RevisionInstruction {
  code: string;
  issue: string;
  revision: string;
}

type Detail = Record<string, string | number> | undefined;

const n = (detail: Detail, key: string, fallback = 0): number => {
  const value = detail?.[key];
  return typeof value === "number" ? value : fallback;
};
const s = (detail: Detail, key: string, fallback = ""): string => {
  const value = detail?.[key];
  return value === undefined ? fallback : String(value);
};

/** Issue code -> revision instruction. Unknown codes fall back to the validation message. */
export function instructionFor(issue: ProductionIssue, spec: ValidationSpec): RevisionInstruction | null {
  const d = issue.detail;
  switch (issue.code) {
    case "scale_too_large":
      return {
        code: issue.code,
        issue: `The asset is approximately ${n(d, "ratio", 1).toFixed(2)}x too large (longest axis ${n(d, "actual")} m, expected at most ${n(d, "expectedMax")} m).`,
        revision:
          `Reduce the overall dimensions to fit within ${spec.model.longestAxis.min} - ${spec.model.longestAxis.max} m on the longest axis` +
          (spec.model.requiredNodes.length
            ? `, while preserving the ${spec.model.requiredNodes.join(" / ")} position relative to the mesh.`
            : ", scaling uniformly around the asset origin."),
      };
    case "scale_too_small":
      return {
        code: issue.code,
        issue: `The asset is approximately ${n(d, "ratio", 1).toFixed(2)}x too small (longest axis ${n(d, "actual")} m, expected at least ${n(d, "expectedMin")} m).`,
        revision: `Scale the asset up uniformly so the longest axis falls within ${spec.model.longestAxis.min} - ${spec.model.longestAxis.max} m. Do not change the proportions.`,
      };
    case "origin_offset":
      return {
        code: issue.code,
        issue: `The mesh centre sits ${n(d, "offset")} m away from the model origin (limit ${n(d, "max")} m).`,
        revision:
          "Move the geometry so the attachment point is at the model origin (0,0,0). Do not compensate with a node transform; re-centre the mesh itself.",
      };
    case "grip_missing":
      return {
        code: issue.code,
        issue: `The required node \`${s(d, "node")}\` is missing.`,
        revision:
          `Add an empty node named exactly \`${s(d, "node")}\` at the hand contact point. ` +
          `It aligns to ${spec.attachment.gripAlignment[s(d, "node")] ?? "the hand socket"}; its origin is where the hand closes around the asset.`,
      };
    case "socket_unknown":
      return {
        code: issue.code,
        issue: `The declared socket \`${s(d, "socket")}\` is not part of the character rig.`,
        revision: "Use one of the project's defined character sockets from validation-spec.json (attachment.socket).",
      };
    case "polygon_over_budget":
      return {
        code: issue.code,
        issue: `Polygon count is ${n(d, "actual")} triangles, over the budget of ${n(d, "max")}.`,
        revision:
          `Rebuild the asset at around ${n(d, "target")} triangles: remove bevels and subdivisions, merge coplanar faces, and keep the silhouette as blocky as the base character.`,
      };
    case "material_over_budget":
      return {
        code: issue.code,
        issue: `The model uses ${n(d, "actual")} materials, over the limit of ${n(d, "max")}.`,
        revision: `Merge the materials down to at most ${n(d, "max")}; separate colour regions with UV islands and the texture, not with extra materials.`,
      };
    case "uv_missing":
      return {
        code: issue.code,
        issue: `${n(d, "meshesWithoutUv")} mesh(es) have no UV set.`,
        revision:
          `Unwrap every mesh into a single non-overlapping UV set laid out for a ${spec.texture.width}x${spec.texture.height} texture, aligned to the pixel grid with 1px island padding.`,
      };
    case "texture_wrong_size":
      return {
        code: issue.code,
        issue: `The texture is ${n(d, "actualWidth")}x${n(d, "actualHeight")}, but the specification requires ${n(d, "expectedWidth")}x${n(d, "expectedHeight")}.`,
        revision:
          `Repaint the texture at ${n(d, "expectedWidth")}x${n(d, "expectedHeight")} at native resolution. Do not upscale or downscale an existing image — hard pixel boundaries must survive.`,
      };
    case "texture_not_square":
      return {
        code: issue.code,
        issue: "The texture is not square.",
        revision: `Deliver a square ${spec.texture.width}x${spec.texture.height} PNG.`,
      };
    case "texture_missing":
      return {
        code: issue.code,
        issue: "No texture was delivered.",
        revision: `Produce the ${spec.texture.width}x${spec.texture.height} PNG described in texture-prompt.md, painted to the model's UV islands.`,
      };
    case "alpha_not_allowed":
      return {
        code: issue.code,
        issue: "The texture contains transparency, but this asset type forbids alpha.",
        revision: "Deliver a fully opaque texture; replace any cutout with real geometry.",
      };
    case "alpha_required":
      return {
        code: issue.code,
        issue: "This asset type requires alpha, but the texture is fully opaque.",
        revision: "Use 1-bit alpha (fully opaque or fully transparent, no soft edges) for the silhouette edges.",
      };
    case "palette_slot_missing":
      return {
        code: issue.code,
        issue: `The palette slot \`${s(d, "slot")}\` is missing from the asset definition / texture regions.`,
        revision:
          `Assign a contiguous set of UV islands to the \`${s(d, "slot")}\` palette slot and keep its colours flat so the runtime can recolour it.`,
      };
    case "palette_missing":
      return {
        code: issue.code,
        issue: "No palette slots are declared, so the asset cannot be recoloured.",
        revision: `Group the texture into flat regions for these palette slots: ${spec.palette.slots.join(", ") || "primary, secondary"}.`,
      };
    case "possible_clipping":
      return {
        code: issue.code,
        issue: `Possible clipping with ${s(d, "region")} (bounding-box overlap ${n(d, "overlapVolume")} m³).`,
        revision:
          `Trim or reshape the asset so it keeps clearance from ${s(d, "region")}. Check the measured region box in technical-spec.md before re-exporting.`,
      };
    case "bounding_box_invalid":
      return {
        code: issue.code,
        issue: "The model bounding box is degenerate (a zero or NaN axis).",
        revision: "Re-export the model with real geometry on all three axes; remove empty or zero-scale meshes.",
      };
    case "model_unreadable":
      return {
        code: issue.code,
        issue: "The model could not be read as a GLB with visible geometry.",
        revision: "Re-export as glTF 2.0 binary (.glb) with at least one visible mesh, +Y up, metres, no compression extensions.",
      };
    case "animation_unavailable":
      return {
        code: issue.code,
        issue: issue.message,
        revision: `Confirm the asset targets the ${spec.animation.set} animation set; the base character only provides the clips listed in validation-spec.json.`,
      };
    case "bodytype_missing":
      return {
        code: issue.code,
        issue: "No body type is declared.",
        revision: "Declare at least one supported body type (adult / child) in the asset definition.",
      };
    default:
      return null;
  }
}

export interface RevisionPromptInput {
  job: ProductionJob;
  spec: ValidationSpec;
  validation: ProductionValidation;
  /** Only errors by default; include warnings when the user asks for a stricter revision. */
  includeWarnings?: boolean;
}

export function revisionInstructions(input: RevisionPromptInput): RevisionInstruction[] {
  const levels = input.includeWarnings ? ["error", "warning"] : ["error"];
  return input.validation.issues
    .filter((i) => levels.includes(i.level))
    .map((issue) => instructionFor(issue, input.spec) ?? { code: issue.code, issue: issue.message, revision: "Address the issue above and re-export." })
    .filter((v, i, all) => all.findIndex((o) => o.code === v.code && o.issue === v.issue) === i);
}

/** Spec section 46: an Issue / Revision pair per problem, ready to hand back to the AI agent. */
export function buildRevisionPrompt(input: RevisionPromptInput): string {
  const { job, spec } = input;
  const instructions = revisionInstructions(input);
  const revisionNumber = job.revisions.length;
  const header = [
    `# Revision Prompt — ${job.name || job.id} (revision ${revisionNumber} -> ${revisionNumber + 1})`,
    `<!-- promptVersion: ${job.promptVersion} · assetType: ${spec.assetType} · assetId: ${spec.assetId} -->`,
    "",
    "The previous delivery did not pass validation. Fix the points below and re-export.",
    "Everything not listed here was accepted: do not redesign the asset, do not change its style,",
    "and do not regenerate it from scratch unless an instruction says so.",
    "",
    `Validation verdict: ${input.validation.verdict.toUpperCase()} · score ${input.validation.score}/100`,
    "",
  ];
  if (!instructions.length) {
    return [...header, "No blocking issues were recorded. Re-check the asset against validation-spec.json.", ""].join("\n");
  }
  const body = instructions.flatMap((item, index) => [
    `## ${index + 1}. ${item.code}`,
    "",
    "Issue:",
    item.issue,
    "",
    "Revision:",
    item.revision,
    "",
  ]);
  return [
    ...header,
    ...body,
    "## Unchanged requirements",
    "",
    "- Keep the same asset identity, silhouette direction and palette slot layout.",
    `- Keep the attachment contract: socket ${spec.attachment.socket}, attachment point ${spec.attachment.assetPoint}.`,
    `- Keep the output format: .bbmodel source if available, model.glb, ${spec.texture.width}x${spec.texture.height} texture.png.`,
    "- Do not modify the base character.",
    "",
  ].join("\n");
}
