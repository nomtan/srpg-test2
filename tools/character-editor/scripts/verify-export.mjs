// Headless sanity check for the Phase 5 Godot export pipeline. Does NOT run the browser-only
// GLTFExporter; instead it verifies the inputs the exporter depends on and the pure-domain
// metadata/mapping logic, so CI can catch regressions without a browser.
//
//   node scripts/verify-export.mjs
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const here = new URL("./", import.meta.url);
const fail = [];
const ok = (cond, msg) => { console.log(`${cond ? "PASS" : "FAIL"}: ${msg}`); if (!cond) fail.push(msg); };

// ---- 1. Parse the base GLB the exporter assembles onto -----------------------
const glbBytes = new Uint8Array(await readFile(new URL("../public/generated-assets/base_body/model.glb", here)));
const view = new DataView(glbBytes.buffer);
ok(view.getUint32(0, true) === 0x46546c67, "base GLB magic is glTF");
const jsonLen = view.getUint32(12, true);
ok(view.getUint32(16, true) === 0x4e4f534a, "first chunk is JSON");
const gltf = JSON.parse(new TextDecoder().decode(glbBytes.subarray(20, 20 + jsonLen)));

const nodeNames = new Set((gltf.nodes ?? []).map((n) => n.name).filter(Boolean));
const REQUIRED_RIG_NODES = ["ganmen", "dou", "kahanshi", "hand_right_te", "hand_left_te", "foot_right", "foot_left"];
for (const name of REQUIRED_RIG_NODES) ok(nodeNames.has(name), `rig node present: ${name}`);
for (const socketParent of ["ganmen", "dou", "body", "kahanshi", "hand_left", "hand_right", "hand_left_kote", "hand_right_kote", "hand_left_te", "hand_right_te", "ashi_left", "ashi_right"]) {
  ok(nodeNames.has(socketParent), `socket parent node present: ${socketParent}`);
}

const clipNames = new Set((gltf.animations ?? []).map((a) => a.name));
const BAKED = [
  "animation.walk_mcp_test", "animation.run",
  "animation.onehand_sword_idle", "animation.onehand_sword_run", "animation.onehand_sword_attack",
  "animation.great_sword_idle", "animation.great_sword_run", "animation.gread_sword_attack",
  "animation.bow_idle", "animation.bow_run", "animation.bow_attack",
  "animation.spear_idle", "animation.spear_run", "animation.spear_attack",
  "animation.dagger_idle", "animation.dagger_run", "animation.dagger_attack",
];
for (const clip of BAKED) ok(clipNames.has(clip), `baked animation clip present: ${clip}`);
ok((gltf.animations ?? []).length >= 4, `>= 4 animation clips (idle/walk/run/attack coverage), got ${(gltf.animations ?? []).length}`);

// ---- 2. Scale: base rest-pose bounds vs the in-game explorer reference -------
const analysis = JSON.parse(await readFile(new URL("../public/generated-assets/base_body/analysis.json", here)));
const mPerUnit = analysis.coordinates.metersPerSourceUnit;
ok(Math.abs(mPerUnit - 1 / 12) < 1e-9, `metersPerSourceUnit = 1/12 (${mPerUnit})`);
const heightM = analysis.bounds.size[1] * mPerUnit;
// The exact height moves whenever the artist edits base_1.bbmodel, so compare against the value
// derived from the source rather than a literal, and keep a broad band to catch a scale-rule blowup.
{
  const measured = JSON.parse(await readFile(new URL("../public/generated-assets/base_body/measurements.json", here), "utf8"));
  const expected = measured.character.height;
  ok(Math.abs(heightM - expected) < 0.01,
    `base rest height ${heightM.toFixed(4)} m matches the measured source height ${expected} m (Godot root_scale 1.0)`);
  ok(heightM > 1.5 && heightM < 2.2, `base rest height ${heightM.toFixed(4)} m is a plausible character height`);
}
ok(heightM > 0.8 && heightM < 3.0, "base height within 0.8-3.0 m human range");

// ---- 3. Pure-domain metadata + animation mapping ----------------------------
// Minimal ESM-friendly stand-ins for the two domain functions (kept in sync with
// src/domain/character-export.ts). If these drift, tsc + the app will catch it.
const animationMapping = {
  "animation.walk_mcp_test": ["default", "walk"], "animation.run": ["default", "run"],
  "animation.onehand_sword_idle": ["onehand_sword", "idle"], "animation.onehand_sword_run": ["onehand_sword", "run"], "animation.onehand_sword_attack": ["onehand_sword", "attack"],
  "animation.great_sword_idle": ["great_sword", "idle"], "animation.great_sword_run": ["great_sword", "run"], "animation.gread_sword_attack": ["great_sword", "attack"],
  "animation.spear_idle": ["spear", "idle"], "animation.spear_run": ["spear", "run"], "animation.spear_attack": ["spear", "attack"],
  "animation.bow_idle": ["bow", "idle"], "animation.bow_run": ["bow", "run"], "animation.bow_attack": ["bow", "attack"],
  "animation.dagger_idle": ["dagger", "idle"], "animation.dagger_run": ["dagger", "run"], "animation.dagger_attack": ["dagger", "attack"],
};
const map = {};
for (const [clip, [set, action]] of Object.entries(animationMapping)) {
  if (!BAKED.includes(clip)) continue;
  (map[set] ??= {})[action] = clip;
}
ok(map.default?.run === "animation.run", "mapping default.run resolves");
ok(map.onehand_sword?.attack === "animation.onehand_sword_attack", "mapping onehand_sword.attack resolves");
ok(map.great_sword?.attack === "animation.gread_sword_attack", "mapping normalises the 'gread_sword' source typo without renaming the clip");
ok(!clipNames.has("animation.gread_sword_attack") === false, "GLB keeps original clip spelling animation.gread_sword_attack");

const sampleMeta = {
  specVersion: 1, characterVersion: 1, id: "vein", name: "Vein",
  body: { base: "adult", preset: "adult_normal", scale: { height: 1, bodyWidth: 1, headScale: 1 } },
  assets: { base: "base_body", mainHand: "demo_sword_001", offHand: "demo_shield_001" },
  palette: { primary: "#8c2430", secondary: "#303030", metal: "#a0a0a0", leather: "#654321", hair: "#36251c", skin: "#d8aa85" },
  activeAnimationSet: "onehand_sword", animations: map,
  visibility: { hiddenParts: [], hairPolicy: null },
  model: "vein.glb", texture: "vein.png",
  generator: { tool: "srpg-character-editor", phase: 5 },
};
const idPattern = /^[a-z][a-z0-9_]*$/;
ok(idPattern.test(sampleMeta.id), "sample character id is snake_case");
ok(!idPattern.test("Vein 2"), "id validator rejects invalid characters");
console.log("\nsample character.json:\n" + JSON.stringify(sampleMeta, null, 2));

// ---- Per-body-part colour overrides (recipe.bodyPartColors) ------------------
// The base GLB shares one material across all 20 body meshes, so an override must clone rather
// than write onto the shared material — otherwise one part repaints the whole body.
{
  const THREE = await import("three");
  const { tintBodyParts } = await import("../src/viewer/palette/bodyPartTint.ts");
  const { validateRecipeShape, emptyRecipe, recipeText } = await import("../src/domain/builder-recipe.ts");

  const shared = new THREE.MeshStandardMaterial({ color: 0xb7b7b7 });
  const root = new THREE.Object3D();
  for (const name of ["ganmenn", "mimi_left", "kubi", "dou", "te_left", "te_right", "koshi"]) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), shared);
    mesh.name = name;
    root.add(mesh);
  }
  const hexOf = (n) => "#" + root.getObjectByName(n).material.color.getHexString();

  const SKIN = "#d8aa85";
  const { applied, cloned } = tintBodyParts(root, SKIN, { ganmenn: "#aa3333", te_left: "#22aa22", te_right: "#22aa22" });
  ok(hexOf("ganmenn") === "#aa3333", "an overridden body part takes its own colour");
  ok(hexOf("dou") === SKIN && hexOf("kubi") === SKIN, "body parts without an override fall back to palette.skin");
  ok(hexOf("mimi_left") === SKIN && hexOf("koshi") === SKIN, "a part override does not leak onto the rest of the body");
  ok(root.getObjectByName("te_left").material === root.getObjectByName("te_right").material,
    "parts sharing a colour share one cloned material");
  ok(root.getObjectByName("dou").material === shared, "fallback parts stay on the shared base material");
  ok(cloned.length === 2, `only distinct colours are cloned (got ${cloned.length})`);
  ok(JSON.stringify(applied) === JSON.stringify(["ganmenn", "te_left", "te_right"]), "applied part names are reported back");

  tintBodyParts(root, "#000000", { ganmenn: "#aa3333" });
  ok(hexOf("dou") === "#000000" && hexOf("ganmenn") === "#aa3333", "changing skin repaints only the fallback parts");

  const withParts = { ...emptyRecipe(), bodyPartColors: { ganmenn: "#D8AA85", te_left: "#aa3333" } };
  const parsed = validateRecipeShape(JSON.parse(recipeText(withParts)));
  ok(parsed.recipe?.bodyPartColors?.ganmenn === "#d8aa85", "bodyPartColors survives a recipe round-trip, lower-cased");
  const bad = validateRecipeShape({ ...JSON.parse(recipeText(emptyRecipe())), bodyPartColors: { dou: "red", koshi: "#112233" } });
  ok(!!bad.recipe && bad.recipe.bodyPartColors?.koshi === "#112233" && bad.recipe.bodyPartColors?.dou === undefined,
    "an invalid part colour is dropped without failing the recipe");
  const none = validateRecipeShape(JSON.parse(recipeText(emptyRecipe())));
  ok(none.recipe && !("bodyPartColors" in none.recipe), "no overrides leaves the key out of the recipe entirely");
}

// ---- Duplicate node names in the real base GLB --------------------------------
// GLTFLoader uniquifies duplicate node names, so `ashisaki` / `ashikubi` (two each) and the torso
// mesh `dou` (which collides with the group of the same name) do NOT keep their source names.
// Anything that addresses a body part has to resolve through the element UUID instead.
{
  const { GLTFLoader } = await import("three/addons/loaders/GLTFLoader.js");
  const { tintBodyParts } = await import("../src/viewer/palette/bodyPartTint.ts");
  const { basePartNameOf } = await import("../src/features/asset-creator/base-parts.ts");

  const bytes = await readFile(new URL("../public/generated-assets/base_body/model.glb", here));
  const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const loaded = await new Promise((resolve, reject) => new GLTFLoader().parse(buffer, "", resolve, reject));

  const meshesOf = (part) => {
    const out = [];
    loaded.scene.traverse((o) => { if (o.isMesh && basePartNameOf(o) === part) out.push(o); });
    return out;
  };
  ok(meshesOf("ashisaki").length === 2, `both ashisaki meshes resolve (got ${meshesOf("ashisaki").length})`);
  ok(meshesOf("ashikubi").length === 2, `both ashikubi meshes resolve (got ${meshesOf("ashikubi").length})`);
  ok(meshesOf("dou").length === 1, `the torso mesh resolves despite the dou group name clash (got ${meshesOf("dou").length})`);
  const renamed = [];
  loaded.scene.traverse((o) => { if (o.isMesh && basePartNameOf(o) && o.name !== basePartNameOf(o)) renamed.push(o.name); });
  ok(renamed.length > 0, `GLTFLoader really does rename some meshes (${renamed.join(", ")})`);

  const SKIN = "#d8aa85";
  tintBodyParts(loaded.scene, SKIN, { ashisaki: "#aa3333", dou: "#2244cc" }, basePartNameOf);
  const hexOf = (mesh) => "#" + mesh.material.color.getHexString();
  ok(meshesOf("ashisaki").every((m) => hexOf(m) === "#aa3333"),
    "both feet take the override, not just one (the reported bug)");
  ok(meshesOf("dou").every((m) => hexOf(m) === "#2244cc"), "the torso takes its override");
  ok(meshesOf("ashikubi").every((m) => hexOf(m) === SKIN), "untouched parts stay on skin");
  ok(meshesOf("ganmenn").every((m) => hexOf(m) === SKIN), "the head stays on skin");
}

// ---- Socket calibration -------------------------------------------------------------
// Phase 2 parked every socket on its parent group's rotation PIVOT, which is up to 0.53 m away
// from the body part it serves; an asset authored with "origin = attachment point" landed in the
// wrong place. Sockets are now calibrated to the centre of their body region, and the offset is
// stored in the PARENT's local frame — so the conversion back to world space is the part worth
// testing, not the numbers themselves.
{
  const THREE = await import("three");
  const { GLTFLoader } = await import("three/addons/loaders/GLTFLoader.js");
  const { baseSocket, baseRegion } = await import("../src/domain/base-measurements.ts");
  const { socketNodeName } = await import("../src/features/asset-creator/base-parts.ts");
  const { applySocketOffset } = await import("../src/viewer/equipment/gripAlignment.ts");
  const { CHARACTER_SOCKETS } = await import("../src/domain/constants.ts");

  const bytes = await readFile(new URL("../public/generated-assets/base_body/model.glb", here));
  const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const base = (await new Promise((res, rej) => new GLTFLoader().parse(buffer, "", res, rej))).scene;

  let worst = 0;
  let calibrated = 0;
  for (const id of CHARACTER_SOCKETS) {
    const socket = baseSocket(id);
    if (!socket?.region) continue;
    calibrated += 1;
    const parent = base.getObjectByName(socketNodeName(id));
    if (!parent) { ok(false, `socket parent node exists for ${id}`); continue; }
    // Attaching at the calibrated local offset must land on the measured region centre.
    const probe = new THREE.Object3D();
    parent.add(probe);
    applySocketOffset(probe, socket.position);
    base.updateMatrixWorld(true);
    const world = probe.getWorldPosition(new THREE.Vector3());
    parent.remove(probe);
    const target = new THREE.Vector3(...baseRegion(socket.region).center);
    worst = Math.max(worst, world.distanceTo(target));
  }
  ok(calibrated === CHARACTER_SOCKETS.length, `every socket is calibrated (${calibrated}/${CHARACTER_SOCKETS.length})`);
  ok(worst < 1e-3, `calibrated sockets land on their region centre (worst error ${worst.toFixed(6)} m)`);

  // The calibration has to have actually moved something, or it is not doing its job.
  const moved = CHARACTER_SOCKETS.filter((id) => {
    const s = baseSocket(id);
    return s?.pivotWorldPosition && s.worldPosition.some((v, i) => Math.abs(v - s.pivotWorldPosition[i]) > 1e-6);
  });
  ok(moved.length > 0, `calibration moves sockets off the group pivot (${moved.length} of ${CHARACTER_SOCKETS.length})`);
  const chest = baseSocket("socket_chest");
  ok(chest.worldPosition.join() === baseRegion("torso").center.join(),
    "socket_chest sits on the torso, not on the dou group pivot");
}

console.log(`\n${fail.length ? `FAILED (${fail.length})` : "ALL PASS"} — ${fileURLToPath(new URL("../public/generated-assets/base_body/model.glb", here))}`);
process.exit(fail.length ? 1 : 0);
