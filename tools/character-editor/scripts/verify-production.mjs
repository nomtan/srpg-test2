// Headless checks for the Phase 9 AI Production pipeline: package contents, per-type prompt
// templates, measured numbers reaching the prompt, the validation spec contract, the validation
// verdict/score rules, and revision-prompt generation.
//
// Run: npm run verify:production
import { emptyDraft, applyTypeDefaults, ASSET_TYPES } from "../src/domain/asset-spec.ts";
import { newProductionJob, PROMPT_VERSION } from "../src/domain/production-job.ts";
import { buildProductionPackage, buildValidationSpec } from "../src/domain/production-package.ts";
import { validateProduction } from "../src/domain/production-validation.ts";
import { buildRevisionPrompt, revisionInstructions } from "../src/domain/production-revision.ts";
import { BASE_CHARACTER, baseRegion, baseSocket } from "../src/domain/base-measurements.ts";
import { TYPE_TEMPLATE_FILE } from "../src/prompt/templates/index.ts";

let failures = 0;
const check = (name, condition, detail = "") => {
  if (condition) { console.log(`  ok   ${name}`); return; }
  failures += 1;
  console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ""}`);
};

function jobFor(type, patch = {}) {
  const draft = { ...applyTypeDefaults(emptyDraft(type), type), id: `${type}_001`, name: `${type} 01`, ...patch };
  return newProductionJob(draft, ["kingdom"]);
}

console.log("# Production Package");
{
  const job = jobFor("hair");
  const files = buildProductionPackage(job);
  const names = files.map((f) => f.name);
  check("package has the six spec files", [
    "asset-definition.json", "model-prompt.md", "texture-prompt.md",
    "technical-spec.md", "validation-spec.json", "README.md",
  ].every((n) => names.includes(n)), names.join(", "));

  const definition = JSON.parse(files.find((f) => f.name === "asset-definition.json").content);
  check("asset-definition keeps the spec shape", definition.specVersion === 1
    && definition.asset.id === "hair_001"
    && definition.target.baseModel === "assets/characters/base/base_1.bbmodel"
    && definition.target.socket === "socket_hair"
    && Array.isArray(definition.appearance.paletteSlots));
  check("asset-definition carries a machine-readable socket transform",
    definition.attachment.socket && Array.isArray(definition.attachment.socket.position));
  check("asset-definition records promptVersion", definition.production.promptVersion === PROMPT_VERSION);
}

console.log("\n# Model Prompt sections");
{
  const job = jobFor("weapon");
  const prompt = buildProductionPackage(job).find((f) => f.name === "model-prompt.md").content;
  const required = [
    "## PURPOSE", "## REFERENCE MODEL", "## ASSET TYPE", "## STYLE", "## SCALE", "## PROPORTION",
    "## ATTACHMENT", "## ORIGIN / PIVOT", "## ORIENTATION", "## GEOMETRY",
    "## POLYGON REQUIREMENTS", "## MATERIAL", "## UV", "## NAMING", "## OUTPUT FORMAT",
    "## DO NOT", "## VALIDATION TARGET",
  ];
  const missing = required.filter((s) => !prompt.includes(s));
  check("all spec section 6 headings are present", missing.length === 0, missing.join(", "));
  check("base model path is quoted", prompt.includes("assets/characters/base/base_1.bbmodel"));
  check("base model must not be modified", prompt.includes("Do not modify the base model."));
  check("measured character height reaches the prompt", prompt.includes(String(BASE_CHARACTER.height)));
  check("grip_main is requested", prompt.includes("grip_main"));
  check("weapon orientation section exists", prompt.includes("WEAPON ORIENTATION")
    && prompt.includes("Do not manually rotate the character hand to fit the weapon."));
  check("asset-only isolation is stated", prompt.includes("Generate only the sword / weapon asset."));
  check("promptVersion marker", prompt.includes(`promptVersion: ${PROMPT_VERSION}`));
}

console.log("\n# Per-type templates");
{
  check("every asset type maps to a template file",
    ASSET_TYPES.every((t) => typeof TYPE_TEMPLATE_FILE[t] === "string"));
  const prompts = Object.fromEntries(ASSET_TYPES.map((t) => {
    const job = jobFor(t);
    return [t, buildProductionPackage(job).find((f) => f.name === "model-prompt.md").content];
  }));
  check("hair rules", prompts.hair.includes("Do not generate the face")
    && prompts.hair.includes("socket_hair")
    && prompts.hair.includes("Headgear compatibility"));
  check("headgear rules", prompts.headgear.includes("hairPolicy")
    && prompts.headgear.includes("Face visibility")
    && prompts.headgear.includes("Head clearance"));
  check("armor rules", prompts.chest_armor.includes("Fit the existing torso")
    && prompts.chest_armor.includes("hideParts")
    && prompts.chest_armor.includes("Preserve limb articulation"));
  check("shoulder rules", prompts.shoulder_left.includes("LEFT shoulder piece")
    && prompts.shoulder_left.includes("Avoid head collision")
    && prompts.shoulder_left.includes("Avoid chest collision"));
  check("shield rules", prompts.shield.includes("off hand")
    && prompts.shield.includes("grip_main")
    && prompts.shield.includes("Hand clearance")
    && prompts.shield.includes("Body clearance"));
  check("back rules", prompts.back.includes("socket_back")
    && prompts.back.includes("Weapon clearance")
    && prompts.back.includes("Silhouette first"));
  check("style + isometric readability everywhere", ASSET_TYPES.every((t) =>
    prompts[t].includes("voxel-inspired") && prompts[t].includes("isometric")));
  check("negative requirements everywhere", ASSET_TYPES.every((t) =>
    prompts[t].includes("Do not modify the base character.")
    && prompts[t].includes("Do not add text or logos.")));
}

console.log("\n# Texture Prompt");
{
  const weapon = jobFor("weapon", { textureResolution: 64 });
  const hair = jobFor("hair");
  const wt = buildProductionPackage(weapon).find((f) => f.name === "texture-prompt.md").content;
  const ht = buildProductionPackage(hair).find((f) => f.name === "texture-prompt.md").content;
  check("weapon texture resolution is honoured", wt.includes("64 x 64"));
  check("base texture resolution is 32", ht.includes("32 x 32"));
  check("palette slots are listed", ht.includes("Usable palette slots: hair"));
  check("palette reference colours are guidance only", ht.includes("hair=#36251c")
    && ht.includes("Do not treat those hex values as final"));
  check("gradient rule", ht.includes("Avoid photographic gradients."));
  check("transparency policy differs per type",
    ht.includes("Alpha is ALLOWED") && wt.includes("Alpha is FORBIDDEN"));
}

console.log("\n# Validation Spec");
{
  const spec = buildValidationSpec(jobFor("weapon"));
  check("grip node required for a one-hand weapon", spec.model.requiredNodes.includes("grip_main"));
  check("grip alignment recorded", spec.attachment.gripAlignment.grip_main === "socket_hand_right");
  check("socket transform included", !!spec.attachment.socketTransform);
  check("coordinate system is the Phase 2/5 one",
    spec.coordinates.up === "+Y" && spec.coordinates.godotScale === 1
    && Math.abs(spec.coordinates.metersPerSourceUnit - 1 / 12) < 1e-9);
  const hairSpec = buildValidationSpec(jobFor("hair"));
  check("hair fit region is the measured head",
    hairSpec.fit[0]?.region === "head"
    && hairSpec.fit[0].box.size.join() === baseRegion("head").size.join());
  check("socket_hair matches the Phase 2 mapping",
    hairSpec.attachment.socketTransform.parent === baseSocket("socket_hair").parent);
}

console.log("\n# Validation Pipeline");
const goodModel = {
  hasMesh: true, meshCount: 1, materialCount: 1, triangleCount: 260,
  boundingBox: { min: [-0.3, -0.05, -0.3], max: [0.3, 0.3, 0.3], size: [0.6, 0.35, 0.6] },
  nodeNames: ["hair_001"], hasUv: true, meshesWithoutUv: 0,
};
{
  const job = jobFor("hair");
  const spec = buildValidationSpec(job);
  const pass = validateProduction(spec, { model: goodModel, texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: "source.bbmodel" });
  check("a conforming hair asset passes", pass.verdict === "pass", JSON.stringify(pass.issues.filter((i) => i.level !== "info")));
  check("score is 100 for a clean pass", pass.score === 100);

  const wrongTexture = validateProduction(spec, { model: goodModel, texture: { width: 64, height: 64, hasAlpha: false }, sourceFileName: null });
  check("wrong texture size is an error", wrongTexture.verdict === "fail"
    && wrongTexture.issues.some((i) => i.code === "texture_wrong_size"));

  const noUv = validateProduction(spec, { model: { ...goodModel, hasUv: false, meshesWithoutUv: 1 }, texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: null });
  check("missing UV is an error", noUv.issues.some((i) => i.code === "uv_missing" && i.level === "error"));

  const overBudget = validateProduction(spec, { model: { ...goodModel, triangleCount: 9000 }, texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: null });
  check("polygon over budget warns", overBudget.verdict === "warning"
    && overBudget.issues.some((i) => i.code === "polygon_over_budget"));
  check("score drops below 100 on a warning", overBudget.score < 100);

  const noPaletteSpec = buildValidationSpec(jobFor("hair", { paletteSlots: ["primary"] }));
  const paletteFail = validateProduction(noPaletteSpec, { model: goodModel, texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: null });
  check("hair without the hair palette slot fails",
    paletteFail.issues.some((i) => i.code === "palette_slot_missing" && i.level === "error"));
}
{
  // Spec section 46: "Sword is approximately 1.8x too large" must be an error, not a warning.
  const job = jobFor("weapon");
  const spec = buildValidationSpec(job);
  const big = spec.model.longestAxis.max * 1.8;
  const oversize = validateProduction(spec, {
    model: {
      ...goodModel,
      nodeNames: ["sword", "grip_main"],
      boundingBox: { min: [-0.05, 0, -0.05], max: [0.05, big, 0.05], size: [0.1, big, 0.1] },
    },
    texture: { width: 32, height: 32, hasAlpha: false },
    sourceFileName: null,
  });
  check("1.8x oversize is a scale error", oversize.verdict === "fail"
    && oversize.issues.some((i) => i.code === "scale_too_large" && i.level === "error"));

  const missingGrip = validateProduction(spec, {
    model: { ...goodModel, nodeNames: ["sword"], boundingBox: { min: [-0.05, 0, -0.05], max: [0.05, 0.9, 0.05], size: [0.1, 0.9, 0.1] } },
    texture: { width: 32, height: 32, hasAlpha: false },
    sourceFileName: null,
  });
  check("missing grip_main is an error", missingGrip.issues.some((i) => i.code === "grip_missing" && i.level === "error"));

  const staffSpec = buildValidationSpec(jobFor("weapon", { weaponType: "staff", animationSet: "staff", handling: "two_hand", gripPoints: ["grip_main", "grip_sub"] }));
  const staff = validateProduction(staffSpec, {
    model: { ...goodModel, nodeNames: ["staff", "grip_main", "grip_sub"], boundingBox: { min: [-0.05, 0, -0.05], max: [0.05, 1.6, 0.05], size: [0.1, 1.6, 0.1] } },
    texture: { width: 32, height: 32, hasAlpha: false },
    sourceFileName: null,
  });
  check("an animation set the base cannot play warns",
    staff.issues.some((i) => i.code === "animation_set_unsupported" && i.level === "warning"));

  console.log("\n# Revision Prompt");
  const instructions = revisionInstructions({ job, spec, validation: oversize, includeWarnings: false });
  check("oversize produces a revision instruction", instructions.some((i) => i.code === "scale_too_large"));
  const prompt = buildRevisionPrompt({ job, spec, validation: oversize, includeWarnings: false });
  check("revision prompt states the issue and the fix",
    prompt.includes("too large") && prompt.includes("Revision:") && prompt.includes("preserving the grip_main"));
  check("revision prompt keeps the unchanged contract",
    prompt.includes("Do not modify the base character.") && prompt.includes("socket_hand_right"));

  const gripPrompt = buildRevisionPrompt({ job, spec, validation: missingGrip, includeWarnings: false });
  check("missing grip produces an actionable revision", gripPrompt.includes("`grip_main`")
    && gripPrompt.includes("socket_hand_right"));
}

console.log("\n# Measurements");
{
  check("head box is measured, not guessed", baseRegion("head").size[0] > 0);
  check("hand socket has a rest-pose world position",
    baseSocket("socket_hand_right").worldPosition.some((v) => v !== 0));
  check("socket stays flagged as uncalibrated",
    baseSocket("socket_hand_right").status === "pivot_only_uncalibrated");
  check("character is ~2.5-3 heads tall", BASE_CHARACTER.headsTall > 2.4 && BASE_CHARACTER.headsTall < 3.4,
    String(BASE_CHARACTER.headsTall));
}

console.log(failures === 0 ? "\nAll production checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
