// Phase 9 Production Package (spec section 4-5, 51).
//
// The package — not any AI provider — is the source of truth for how an asset gets made
// (spec section 57). It carries the machine-readable Asset Definition and Validation Spec next to
// the human/agent-readable prompts, so the same asset can be re-produced later from the package
// alone.
import type { AssetType } from "./asset-spec";
import { ASSET_CATEGORY_DIR, draftToAssetJson, isWeapon } from "./asset-spec";
import type { PaletteSlot } from "./constants";
import { COORDINATE_SYSTEM } from "./constants";
import { DEFAULT_PALETTE } from "./phase3";
import {
  BASE_CHARACTER, BASE_COORDINATE_INFO, BASE_SOURCE_PATH, CLEARANCE_REGIONS, FIT_REGIONS,
  baseRegion, baseSocket, recommendedWeaponLength, type MeasuredBox,
} from "./base-measurements";
import {
  ALPHA_POLICY_LABEL, BUDGET_DEFINITION, TYPE_ANIMATION_TEST, attachmentSpecFor,
} from "./production-profile";
import { PROMPT_VERSION, type ProductionJob } from "./production-job";
import { TYPE_TEMPLATE_FILE } from "@/prompt/templates";
import { buildPrompts } from "@/prompt/promptBuilder";

/**
 * Plausible overall size per asset type, as a fraction of the measured character height.
 * Inside the range = fine, outside = warning, far outside = error (spec section 22 / 39).
 */
export const TYPE_LONGEST_AXIS_RATIO: Record<AssetType, [number, number]> = {
  hair: [0.22, 0.52],
  headgear: [0.22, 0.55],
  head_accessory: [0.04, 0.35],
  chest_armor: [0.18, 0.5],
  shoulder_left: [0.06, 0.3],
  shoulder_right: [0.06, 0.3],
  arm_armor: [0.06, 0.3],
  gloves: [0.04, 0.2],
  waist: [0.1, 0.45],
  boots: [0.08, 0.4],
  weapon: [0.15, 1.2],
  shield: [0.18, 0.55],
  back: [0.18, 0.6],
};

/** Beyond this multiple of the plausible range the size is reported as an error, not a warning. */
export const SIZE_ERROR_MARGIN = 1.5;

export interface ValidationSpec {
  specVersion: 1;
  assetId: string;
  assetType: AssetType;
  promptVersion: number;
  bodyTypes: string[];
  model: {
    formats: string[];
    requireMesh: boolean;
    requireUv: boolean;
    maxTriangles: number;
    targetTriangles: number;
    maxMaterials: number;
    requiredNodes: string[];
    /** Max distance from the model origin to the bounding-box centre, in metres. */
    maxOriginOffset: number;
    longestAxis: { min: number; max: number; errorMargin: number };
  };
  texture: {
    width: number;
    height: number;
    requireSquare: boolean;
    alphaPolicy: string;
  };
  palette: { slots: PaletteSlot[] };
  attachment: {
    socket: string;
    assetPoint: string;
    gripAlignment: Record<string, string>;
    socketTransform: {
      name: string;
      parent: string;
      position: number[];
      rotation: number[];
      scale: number[];
      worldPosition: number[];
      space: string;
      status: string;
    } | null;
  };
  fit: { region: string; box: MeasuredBox }[];
  clearance: { region: string; box: MeasuredBox }[];
  animation: { set: string; roles: string[] };
  coordinates: {
    up: string;
    forward: string;
    left: string;
    metersPerFieldCell: number;
    godotScale: number;
    metersPerSourceUnit: number;
    baseModel: string;
  };
}

export function buildValidationSpec(job: ProductionJob): ValidationSpec {
  const { draft } = job;
  const budget = BUDGET_DEFINITION[job.budgetProfile];
  const attachment = attachmentSpecFor(draft.type, draft.socket, draft.handling);
  const socketInfo = baseSocket(draft.socket);
  const weaponRange = isWeapon(draft.type) ? recommendedWeaponLength(draft.weaponType) : null;
  const [lo, hi] = TYPE_LONGEST_AXIS_RATIO[draft.type];
  const animation = TYPE_ANIMATION_TEST[draft.type];

  const box = (region: string) => ({ region, box: baseRegion(region as never) });
  return {
    specVersion: 1,
    assetId: draft.id,
    assetType: draft.type,
    promptVersion: job.promptVersion,
    bodyTypes: [...draft.bodyTypes],
    model: {
      formats: ["glb"],
      requireMesh: true,
      requireUv: true,
      maxTriangles: budget.maxTriangles,
      targetTriangles: budget.targetTriangles,
      maxMaterials: budget.maxMaterials,
      requiredNodes: [...attachment.gripPoints],
      maxOriginOffset: Math.max(0.2, BASE_CHARACTER.height * 0.25),
      longestAxis: weaponRange
        ? { min: weaponRange.min, max: weaponRange.max, errorMargin: SIZE_ERROR_MARGIN }
        : {
            min: Math.round(BASE_CHARACTER.height * lo * 1e4) / 1e4,
            max: Math.round(BASE_CHARACTER.height * hi * 1e4) / 1e4,
            errorMargin: SIZE_ERROR_MARGIN,
          },
    },
    texture: {
      width: draft.textureResolution,
      height: draft.textureResolution,
      requireSquare: true,
      alphaPolicy: job.alphaPolicy,
    },
    palette: { slots: [...draft.paletteSlots] },
    attachment: {
      socket: attachment.socket,
      assetPoint: attachment.assetPoint,
      gripAlignment: Object.fromEntries(
        Object.entries(attachment.gripAlignment).map(([grip, socket]) => [grip, socket as string]),
      ),
      socketTransform: socketInfo
        ? {
            name: draft.socket,
            parent: socketInfo.parent,
            position: socketInfo.position,
            rotation: socketInfo.rotation,
            scale: socketInfo.scale,
            worldPosition: socketInfo.worldPosition,
            space: socketInfo.space,
            status: socketInfo.status,
          }
        : null,
    },
    fit: FIT_REGIONS[draft.type].map(box).filter((entry) => !!entry.box),
    clearance: CLEARANCE_REGIONS[draft.type].map(box).filter((entry) => !!entry.box),
    animation: isWeapon(draft.type)
      ? { set: draft.animationSet, roles: [...animation.roles] }
      : { set: animation.set, roles: [...animation.roles] },
    coordinates: {
      up: BASE_COORDINATE_INFO.up,
      forward: BASE_COORDINATE_INFO.forward,
      left: BASE_COORDINATE_INFO.left,
      metersPerFieldCell: COORDINATE_SYSTEM.metersPerFieldCell,
      godotScale: COORDINATE_SYSTEM.godotScale,
      metersPerSourceUnit: BASE_COORDINATE_INFO.metersPerSourceUnit,
      baseModel: BASE_SOURCE_PATH,
    },
  };
}

/** spec section 5: the structured Asset Definition. Keys 1-4 follow the spec example exactly. */
export function buildAssetDefinition(job: ProductionJob): Record<string, unknown> {
  const { draft } = job;
  const metadata = draftToAssetJson(draft);
  const attachment = attachmentSpecFor(draft.type, draft.socket, draft.handling);
  return {
    specVersion: 1,
    asset: {
      id: draft.id,
      name: draft.name,
      type: draft.type,
      description: draft.description,
    },
    target: {
      bodyTypes: [...draft.bodyTypes],
      baseModel: BASE_SOURCE_PATH,
      socket: draft.socket,
    },
    appearance: {
      paletteSlots: [...draft.paletteSlots],
    },
    // ---- beyond the spec example, still machine readable ----
    attachment: {
      assetPoint: attachment.assetPoint,
      gripPoints: attachment.gripPoints,
      gripAlignment: attachment.gripAlignment,
      socket: buildValidationSpec(job).attachment.socketTransform,
    },
    equipment: metadata.equipment ?? null,
    hairPolicy: draft.hairPolicy,
    hideParts: [...draft.hideParts],
    texture: {
      resolution: draft.textureResolution,
      alphaPolicy: job.alphaPolicy,
    },
    geometry: {
      budgetProfile: job.budgetProfile,
      ...BUDGET_DEFINITION[job.budgetProfile],
    },
    paletteReference: Object.fromEntries(
      draft.paletteSlots.map((slot) => [slot, DEFAULT_PALETTE[slot]]),
    ),
    references: job.references.map((r) => ({ file: r.file, role: r.role, view: r.view, note: r.note })),
    production: {
      method: "ai_assisted",
      promptVersion: job.promptVersion,
      status: job.status,
      revision: job.revisions.length,
    },
    tags: [...job.tags],
    outputDirectory: `assets/character-assets/${ASSET_CATEGORY_DIR[draft.type]}/${draft.id || "<id>"}`,
    assetMetadata: metadata,
  };
}

const line = (label: string, value: unknown) => `- **${label}**: ${value}`;

export function buildTechnicalSpec(job: ProductionJob): string {
  const spec = buildValidationSpec(job);
  const { draft } = job;
  const rows: string[] = [
    `# Technical Specification — ${draft.name || draft.id}`,
    "",
    `Asset id: \`${draft.id}\` · type: \`${draft.type}\` · promptVersion: ${job.promptVersion}`,
    "",
    "## Coordinate system",
    "",
    line("Up axis", spec.coordinates.up),
    line("Forward axis", spec.coordinates.forward),
    line("Left axis", spec.coordinates.left),
    line("Unit", "1 unit = 1 metre; Godot import scale = 1.0; 1 field cell = 1 metre"),
    line("Source normalization", `${spec.coordinates.metersPerSourceUnit} m per Blockbench unit (established in Phase 2/5; unchanged here)`),
    line("Base model", spec.coordinates.baseModel),
    "",
    "## Measured base body",
    "",
    line("Character height", `${BASE_CHARACTER.height} m`),
    line("Character bounds (X/Y/Z)", `${BASE_CHARACTER.size.join(" x ")} m`),
    line("Head size", `${BASE_CHARACTER.headHeight} m (~${BASE_CHARACTER.headsTall} heads tall)`),
    "",
    "### Fit regions",
    "",
    ...(spec.fit.length
      ? spec.fit.map((f) => line(f.region, `size ${f.box.size.join(" x ")} m, centre ${f.box.center.join(", ")} m`))
      : ["- (no measured fit region for this asset type)"]),
    "",
    "### Clearance regions",
    "",
    ...(spec.clearance.length
      ? spec.clearance.map((c) => line(c.region, `size ${c.box.size.join(" x ")} m, centre ${c.box.center.join(", ")} m`))
      : ["- (none)"]),
    "",
    "## Attachment",
    "",
    line("Character socket", spec.attachment.socket),
    line("Asset attachment point", spec.attachment.assetPoint),
    ...Object.entries(spec.attachment.gripAlignment).map(([grip, socket]) => line(grip, `-> ${socket}`)),
  ];

  if (spec.attachment.socketTransform) {
    const t = spec.attachment.socketTransform;
    rows.push(
      "",
      "### Socket transform",
      "",
      "```json",
      JSON.stringify(
        { socket: { name: t.name, position: t.position, rotation: t.rotation, scale: t.scale } },
        null,
        2,
      ),
      "```",
      "",
      line("Parent node", `\`${t.parent}\` (${t.space})`),
      line("Rest-pose world position", `${JSON.stringify(t.worldPosition)} m`),
      line("Calibration", `${t.status} — an anchor at the existing group pivot, not a validated grip pose`),
    );
  }

  rows.push(
    "",
    "## Geometry budget",
    "",
    line("Profile", job.budgetProfile),
    line("Target triangles", spec.model.targetTriangles),
    line("Max triangles", spec.model.maxTriangles),
    line("Max materials", spec.model.maxMaterials),
    line("Plausible longest axis", `${spec.model.longestAxis.min} - ${spec.model.longestAxis.max} m`),
    line("Max origin offset", `${spec.model.maxOriginOffset} m`),
    "",
    "## Texture",
    "",
    line("Resolution", `${spec.texture.width} x ${spec.texture.height}`),
    line("Format", "PNG, 8-bit, sRGB, nearest-neighbor sampling"),
    line("Transparency", ALPHA_POLICY_LABEL[job.alphaPolicy]),
    line("Palette slots", spec.palette.slots.join(", ") || "(none)"),
    "",
    "## Naming / output",
    "",
    line("Root node", `\`${draft.id}\``),
    line("Required nodes", spec.model.requiredNodes.join(", ") || "(none)"),
    line("Preferred source", "`.bbmodel` (editable Blockbench source)"),
    line("Runtime", "`model.glb`"),
    line("Texture file", "`texture.png`"),
    line("Target directory", `\`assets/character-assets/${ASSET_CATEGORY_DIR[draft.type]}/${draft.id}/\``),
    "",
    "## Animation compatibility",
    "",
    line("Animation set", spec.animation.set),
    line("Test clips", spec.animation.roles.join(", ")),
    line("Rigging", "None. The asset is attached rigidly to a socket; the base character owns the rig."),
    "",
    "## Prompt templates used",
    "",
    line("Common", "prompt/templates/common.ts"),
    line("Type", TYPE_TEMPLATE_FILE[draft.type]),
    line("promptVersion", job.promptVersion),
    "",
  );
  return rows.join("\n");
}

export function buildPackageReadme(job: ProductionJob): string {
  const { draft } = job;
  return [
    `# AI Production Package — ${draft.name || draft.id}`,
    "",
    `Generated by the SRPG Character Workshop (Phase 9) for asset \`${draft.id}\`.`,
    `Prompt template version: **${job.promptVersion}**.`,
    "",
    "## Contents",
    "",
    "| File | Purpose |",
    "| --- | --- |",
    "| `asset-definition.json` | Machine-readable Asset Definition (identity, target, attachment, palette, texture). |",
    "| `model-prompt.md` | Prompt for producing the 3D model. |",
    "| `texture-prompt.md` | Prompt for producing the texture. |",
    "| `technical-spec.md` | Human-readable technical specification: coordinates, measured dimensions, budgets. |",
    "| `validation-spec.json` | The checks the asset is validated against on import. |",
    job.references.some((r) => r.file) ? "| `reference/` | Reference images, with role and view recorded in `asset-definition.json`. |" : "",
    "",
    "## How to use this package",
    "",
    "1. Read `model-prompt.md` and `technical-spec.md`. They are self-contained; you do not need the repository.",
    `2. Produce **only** the ${draft.type} asset. The base character (\`${BASE_SOURCE_PATH}\`) must not be modified or re-exported.`,
    "3. Deliver an editable `.bbmodel` if possible, plus `model.glb` and `texture.png`.",
    "4. Return the files to the Character Workshop AI Production screen. They are validated against `validation-spec.json` automatically.",
    "5. If validation fails, the tool generates a Revision Prompt describing exactly what to change.",
    "",
    "## Non-goals",
    "",
    "- Do not generate a whole character; assets are combined by the Character Builder.",
    "- Do not invent a new scale or axis convention; `validation-spec.json` carries the project's.",
    "- Do not bake lighting or add branding of any kind.",
    "",
    "## Reproducibility",
    "",
    "This package contains everything needed to re-run production later: asset definition, prompt",
    "version, both prompts, the technical specification, reference information and the validation",
    "spec (spec section 51).",
    "",
  ].filter((l) => l !== "").join("\n");
}

export interface PackageTextFile {
  name: string;
  content: string;
}

/** The text side of the package. Binary references are added by the caller (spec section 4). */
export function buildProductionPackage(job: ProductionJob): PackageTextFile[] {
  const prompts = buildPrompts(job.draft, {
    budgetProfile: job.budgetProfile,
    alphaPolicy: job.alphaPolicy,
    references: job.references,
    promptVersion: job.promptVersion,
  });
  return [
    { name: "asset-definition.json", content: JSON.stringify(buildAssetDefinition(job), null, 2) + "\n" },
    { name: "model-prompt.md", content: prompts.model },
    { name: "texture-prompt.md", content: prompts.texture },
    { name: "technical-spec.md", content: buildTechnicalSpec(job) },
    { name: "validation-spec.json", content: JSON.stringify(buildValidationSpec(job), null, 2) + "\n" },
    { name: "README.md", content: buildPackageReadme(job) },
  ];
}

export const packageDirName = (job: ProductionJob) => `${job.id || "asset"}-ai-package`;
export { PROMPT_VERSION };
