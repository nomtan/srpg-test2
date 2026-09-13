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
import * as THREE from "three";
import { readFileSync } from "node:fs";
import { applyGripAlignment, gripAlignmentFor } from "../src/viewer/equipment/gripAlignment.ts";

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
  check("package ships a ready-to-copy asset.json", names.includes("asset.json"));

  const deliveryJson = JSON.parse(files.find((f) => f.name === "asset.json").content);
  check("delivery asset.json declares the required .bbmodel source",
    deliveryJson.source?.format === "bbmodel" && deliveryJson.source.path === "source/hair_001.bbmodel",
    JSON.stringify(deliveryJson.source));
  check("delivery asset.json names the runtime files",
    deliveryJson.model === "model.glb" && deliveryJson.texture === "texture.png");

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

console.log("\n# Deliverables (folder structure + required .bbmodel)");
{
  for (const type of ["weapon", "hair"]) {
    const job = jobFor(type);
    const id = `${type}_001`;
    const prompt = buildProductionPackage(job).find((f) => f.name === "model-prompt.md").content;
    check(`${type}: DELIVERABLES section exists`, prompt.includes("## DELIVERABLES"));
    check(`${type}: .bbmodel is required, not optional`,
      prompt.includes(`\`source/${id}.bbmodel\` is REQUIRED, not optional`));
    check(`${type}: glb must be exported from the .bbmodel`,
      prompt.includes("`model.glb` must be exported *from it*"));
    check(`${type}: folder tree is spelled out`, [
      `${id}/`, "├─ source/", `│   └─ ${id}.bbmodel`, "├─ model.glb", "├─ texture.png", "└─ asset.json",
    ].every((line) => prompt.includes(line)));
    check(`${type}: fixed file names are stated`,
      prompt.includes("File names are fixed.") && prompt.includes("downloadable archive"));
    check(`${type}: glb-only delivery is forbidden`,
      prompt.includes("Do not deliver only a `.glb`"));
    check(`${type}: asset.json is embedded verbatim`,
      prompt.includes("## ASSET.JSON") && prompt.includes(`"id": "${id}"`)
      && prompt.includes(`"path": "source/${id}.bbmodel"`));
    check(`${type}: validation target lists the delivery folder`,
      prompt.includes(`Delivery folder \`${id}/\` contains source/${id}.bbmodel`));
  }
  const weaponPrompt = buildProductionPackage(jobFor("weapon")).find((f) => f.name === "model-prompt.md").content;
  check("grip nodes are demanded in both the .bbmodel and the .glb",
    weaponPrompt.includes("in BOTH the .bbmodel and the .glb"));
  const readme = buildProductionPackage(jobFor("weapon")).find((f) => f.name === "README.md").content;
  check("package README repeats the delivery tree",
    readme.includes("weapon_001/") && readme.includes("└─ asset.json"));
  const techSpec = buildProductionPackage(jobFor("weapon")).find((f) => f.name === "technical-spec.md").content;
  check("technical spec lists the required source", techSpec.includes("Source (required)")
    && techSpec.includes("source/weapon_001.bbmodel"));
}

console.log("\n# Attached whole-character illustration");
{
  const cases = [
    ["shoulder_left", "the shoulder pauldron on the character's LEFT side", "LEFT"],
    ["shoulder_right", "the shoulder pauldron on the character's RIGHT side", "RIGHT"],
    ["hair", "the hairstyle", null],
    ["weapon", "the weapon held in the character's hand", null],
  ];
  for (const [type, part, side] of cases) {
    const files = buildProductionPackage(jobFor(type));
    const model = files.find((f) => f.name === "model-prompt.md").content;
    const texture = files.find((f) => f.name === "texture-prompt.md").content;
    check(`${type}: the prompt names the part to crop to`,
      model.includes(`design authority for **${part} only**`), part);
    check(`${type}: whole-character art is expected`,
      model.includes("The image will usually show the whole character."));
    check(`${type}: the document still wins over the illustration`,
      model.includes("The SCALE and PROPORTION sections win over the illustration.")
      && model.includes("never overrides the attachment contract"));
    check(`${type}: the texture prompt gets the colour-region variant`,
      texture.includes("how the colour and material regions divide")
      && texture.includes("PALETTE SLOTS and GRADIENT RULE sections win"));
    if (side) {
      check(`${type}: the correct side is called out`, model.includes(`Model only the ${side} one`));
    }
  }
  check("the instruction is present even with no registered reference",
    buildProductionPackage(jobFor("hair")).find((f) => f.name === "model-prompt.md").content
      .includes("If an image is attached to this request"));
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
  for (const side of ["shoulder_left", "shoulder_right"]) {
    check(`${side}: a target asset size is stated, not just the body region`,
      prompts[side].includes("Target asset size: about 0.3126 x 0.3125 x 0.1875 m")
      && prompts[side].includes("worn OVER that body part"));
    check(`${side}: the pauldron must overhang the shoulder`,
      prompts[side].includes("roughly 1.5x the bare shoulder")
      && prompts[side].includes("Do not build it flush"));
  }
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
  // A pauldron built flush to the bare shoulder is what "too small" looked like in practice.
  const shoulderSpec = buildValidationSpec(jobFor("shoulder_left"));
  const pauldron = (longest) => ({
    ...goodModel,
    nodeNames: ["shoulder_left_001"],
    boundingBox: { min: [-longest / 2, -longest / 2, -0.09], max: [longest / 2, longest / 2, 0.09], size: [longest, longest, 0.18] },
  });
  const flush = validateProduction(shoulderSpec, { model: pauldron(0.2084), texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: "s.bbmodel" });
  check("a shoulder built flush to the bare shoulder is flagged as too small",
    flush.issues.some((i) => i.code === "scale_too_small"));
  const sized = validateProduction(shoulderSpec, { model: pauldron(0.3126), texture: { width: 32, height: 32, hasAlpha: false }, sourceFileName: "s.bbmodel" });
  check("a shoulder at the 1.5x target passes", sized.verdict === "pass",
    JSON.stringify(sized.issues.filter((i) => i.level !== "info")));

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

  const noSource = validateProduction(spec, {
    model: { ...goodModel, nodeNames: ["sword", "grip_main"], boundingBox: { min: [-0.05, 0, -0.05], max: [0.05, 0.9, 0.05], size: [0.1, 0.9, 0.1] } },
    texture: { width: 32, height: 32, hasAlpha: false },
    sourceFileName: null,
  });
  check("a delivery without .bbmodel is flagged",
    noSource.issues.some((i) => i.code === "source_missing" && i.level === "warning"));
  const sourcePrompt = buildRevisionPrompt({ job, spec, validation: noSource, includeWarnings: true });
  check("missing source produces a revision asking for the .bbmodel",
    sourcePrompt.includes("weapon_001/source/weapon_001.bbmodel")
    && sourcePrompt.includes("The .bbmodel is the master file"));
}

console.log("\n# Measurements");
{
  check("head box is measured, not guessed", baseRegion("head").size[0] > 0);
  check("hand socket has a rest-pose world position",
    baseSocket("socket_hand_right").worldPosition.some((v) => v !== 0));
  check("socket stays flagged as uncalibrated",
    baseSocket("socket_hand_right").status === "pivot_only_uncalibrated");
  // Regression guard: the source spells the +Z side "_left", but +X forward / +Y up makes +Z the
  // character's RIGHT (forward x left = up). Main Hand must land on +Z.
  check("socket_hand_right is on the character's right (+Z)",
    baseSocket("socket_hand_right").worldPosition[2] > 0,
    JSON.stringify(baseSocket("socket_hand_right").worldPosition));
  check("socket_hand_left is on the character's left (-Z)",
    baseSocket("socket_hand_left").worldPosition[2] < 0,
    JSON.stringify(baseSocket("socket_hand_left").worldPosition));
  check("main hand resolves to the source node that holds the sword",
    baseSocket("socket_hand_right").parent === "hand_left_te",
    baseSocket("socket_hand_right").parent);
  check("shoulders follow the same physical sides",
    baseSocket("socket_shoulder_right").worldPosition[2] > 0
    && baseSocket("socket_shoulder_left").worldPosition[2] < 0);
  check("character is ~2.5-3 heads tall", BASE_CHARACTER.headsTall > 2.4 && BASE_CHARACTER.headsTall < 3.4,
    String(BASE_CHARACTER.headsTall));
}

console.log("\n# Grip alignment (attachment point lands on the socket)");
{
  /** Rebuild a GLB's node tree as plain Object3D + Box meshes, so the math can run headless. */
  function loadAsObject3D(file) {
    const buf = readFileSync(file);
    const json = JSON.parse(buf.subarray(20, 20 + buf.readUInt32LE(12)).toString("utf8"));
    const objects = json.nodes.map((n) => {
      let object;
      if (n.mesh !== undefined) {
        const a = json.accessors[json.meshes[n.mesh].primitives[0].attributes.POSITION];
        const size = a.min.map((v, i) => Math.max(a.max[i] - v, 1e-6));
        object = new THREE.Mesh(new THREE.BoxGeometry(...size));
        object.geometry.translate(...a.min.map((v, i) => v + size[i] / 2));
      } else {
        object = new THREE.Object3D();
      }
      object.name = n.name ?? "";
      object.position.fromArray(n.translation ?? [0, 0, 0]);
      return object;
    });
    json.nodes.forEach((n, i) => { for (const c of n.children ?? []) objects[i].add(objects[c]); });
    const root = new THREE.Object3D();
    root.name = "asset_root";
    for (const i of json.scenes[json.scene ?? 0].nodes) root.add(objects[i]);
    return root;
  }

  const shield = loadAsObject3D("public/demo-assets/demo_shield_001/model.glb");
  const beforeCentre = new THREE.Box3().setFromObject(shield).getCenter(new THREE.Vector3());
  const shieldPlaced = applyGripAlignment(shield, gripAlignmentFor("shield"));
  const socket = new THREE.Object3D();
  socket.add(shield);
  socket.updateMatrixWorld(true);
  const afterCentre = new THREE.Box3().setFromObject(shield).getCenter(new THREE.Vector3());

  check("a shield without a grip node is centred on the socket", shieldPlaced.placedBy === "center");
  check("the shield centre was off the socket before", beforeCentre.length() > 0.1, String(beforeCentre.length()));
  check("the shield centre now sits on the socket", afterCentre.length() < 1e-6,
    afterCentre.toArray().map((v) => v.toFixed(4)).join(", "));

  const sword = loadAsObject3D("library-data/assets/sword_iron_001/model.glb");
  const swordPlaced = applyGripAlignment(sword, gripAlignmentFor("weapon"));
  const grip = sword.getObjectByName("grip_main");
  const socket2 = new THREE.Object3D();
  socket2.add(sword);
  socket2.updateMatrixWorld(true);
  const gripWorld = grip.getWorldPosition(new THREE.Vector3());
  check("a weapon is placed by its grip_main node", swordPlaced.placedBy === "node");
  check("grip_main sits exactly on the socket", gripWorld.length() < 1e-6,
    gripWorld.toArray().map((v) => v.toFixed(4)).join(", "));
  const bladeDir = new THREE.Vector3(0, 1, 0).applyQuaternion(sword.quaternion);
  check("the standard grip rotation points the blade forward (+X)", bladeDir.x > 0.99,
    bladeDir.toArray().map((v) => v.toFixed(3)).join(", "));
}

console.log(failures === 0 ? "\nAll production checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
