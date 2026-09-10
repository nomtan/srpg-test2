import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { Box3, Matrix4, Vector3, Quaternion } from "three";
import { BASE_COORDINATES, baseRigMapping, baseSocketDefinitions, equipmentRootClassification } from "../src/domain/base-rig.ts";
import { createGlbWriter, meshTriangles, quaternion } from "./base-model-geometry.mjs";

const root = new URL("../../../", import.meta.url);
const sourceUrl = new URL(BASE_COORDINATES.source, root);
const bytes = await readFile(sourceUrl);
const sha256 = createHash("sha256").update(bytes).digest("hex");
const data = JSON.parse(bytes);
if (data.meta.model_format !== "free" || data.meta.format_version !== "5.0") throw new Error("Re-analyse new source format before converting");
if (data.textures.length) throw new Error("Textured source requires a reviewed material conversion");
const groups = new Map(data.groups.map((g) => [g.uuid, g]));
const elements = new Map(data.elements.map((e) => [e.uuid, e]));
const records = [], worlds = new Map(), visited = new Set();
function visit(entry, parent = null, parentOrigin = [0, 0, 0], parentWorld = new Matrix4(), classification = "body", visible = true, exported = true) {
  const uuid = typeof entry === "string" ? entry : entry.uuid;
  const object = groups.get(uuid) ?? elements.get(uuid);
  if (!object || visited.has(uuid)) throw new Error(`Unknown/duplicate Outliner UUID: ${uuid}`);
  visited.add(uuid);
  const origin = object.origin ?? [0, 0, 0], rotation = object.rotation ?? [0, 0, 0];
  const category = groups.has(uuid) && equipmentRootClassification[object.name] ? `equipment:${equipmentRootClassification[object.name]}` : classification;
  const translation = origin.map((v, i) => v - parentOrigin[i]);
  const world = parentWorld.clone().multiply(new Matrix4().compose(new Vector3(...translation), new Quaternion(...quaternion(rotation)), new Vector3(1, 1, 1)));
  worlds.set(uuid, world);
  const record = { uuid, name: object.name, parent, origin, rotation, translation, classification: category,
    visible: visible && object.visibility !== false, exported: exported && object.export !== false,
    sourceVisibility: object.visibility ?? true, sourceExport: object.export ?? true, kind: object.type ?? "group" };
  records.push(record);
  if (groups.has(uuid)) for (const child of entry.children ?? []) visit(child, uuid, origin, world, category, record.visible, record.exported);
}
for (const entry of data.outliner) visit(entry);
if (visited.size !== groups.size + elements.size) throw new Error("Unattached source elements/groups require review");
for (const name of [...Object.keys(baseRigMapping), ...Object.keys(equipmentRootClassification)]) {
  if (data.groups.filter((g) => g.name === name).length !== 1) throw new Error(`Mapping requires unique existing group: ${name}`);
}
const bodyParts = records.filter((r) => r.kind !== "group" && r.classification === "body");
const previewParts = bodyParts.filter((r) => r.visible && r.exported);
const bounds = new Box3();
const { gltf, accessor, finish } = createGlbWriter();
gltf.asset.extras = { source: BASE_COORDINATES.source, sourceSha256: sha256, coordinates: BASE_COORDINATES, animationPolicy: "Preview-only node TRS bake of source clips (rest + keyframe, ZYX); source unchanged; full tracks in analysis.json" };
const nodeMap = new Map();
// Retain ALL existing group nodes, even hidden/non-exported equipment groups.
// Meshes respect visibility/export flags; source is never modified.
for (const record of records) {
  if (record.kind !== "group" && !previewParts.includes(record)) continue;
  const node = { name: record.name, translation: record.translation.map((v) => v * BASE_COORDINATES.metersPerSourceUnit), rotation: quaternion(record.rotation), extras: { sourceUuid: record.uuid, classification: record.classification, sourceVisibility: record.sourceVisibility, sourceExport: record.sourceExport } };
  const index = gltf.nodes.length; gltf.nodes.push(node); nodeMap.set(record.uuid, index);
  if (record.parent) gltf.nodes[nodeMap.get(record.parent)].children = [...(gltf.nodes[nodeMap.get(record.parent)].children ?? []), index];
  else gltf.scenes[0].nodes.push(index);
  if (record.kind === "group") continue;
  const element = elements.get(record.uuid);
  const mesh = meshTriangles(element, data.resolution, BASE_COORDINATES.metersPerSourceUnit);
  node.mesh = gltf.meshes.length;
  gltf.meshes.push({ name: element.name, primitives: [{ attributes: { POSITION: accessor(mesh.positions, 3), NORMAL: accessor(mesh.normals, 3), TEXCOORD_0: accessor(mesh.uvs, 2) }, material: 0 }] });
  for (const vertex of Object.values(element.vertices)) bounds.expandByPoint(new Vector3(...vertex).applyMatrix4(worlds.get(record.uuid)));
}
const animations = data.animations.map((animation) => ({
  uuid: animation.uuid, name: animation.name, length: animation.length, loop: animation.loop,
  keyframeCount: Object.values(animation.animators).reduce((n, a) => n + (a.keyframes?.length ?? 0), 0),
  targets: Object.entries(animation.animators).filter(([, a]) => a.keyframes?.length).map(([uuid, a]) => ({ uuid, name: groups.get(uuid)?.name ?? a.name, type: a.type, rotationGlobal: a.rotation_global ?? false, keyframes: a.keyframes })),
}));
const groupRecords = records.filter((r) => r.kind === "group").map((r) => ({ ...r, role: baseRigMapping[r.name] ?? null, animatedBy: animations.filter((a) => a.targets.some((t) => t.uuid === r.uuid)).map((a) => a.name) }));
const analysis = {
  source: { path: BASE_COORDINATES.source, sha256, format: data.meta.model_format }, coordinates: BASE_COORDINATES,
  counts: { groups: groups.size, elements: elements.size, meshes: data.elements.filter((e) => e.type === "mesh").length, cubes: data.elements.filter((e) => e.type === "cube").length, bodyParts: bodyParts.length, previewMeshes: previewParts.length, animations: animations.length, textures: data.textures.length },
  outliner: data.outliner, groups: groupRecords, bodyParts,
  equipmentGroups: groupRecords.filter((g) => g.classification.startsWith("equipment:")),
  // Preserve vertices/faces/UVs, flags and pivots for BOTH body and equipment.
  elements: data.elements, animations, rawAnimations: data.animations,
  texture: { resolution: data.resolution, textures: data.textures, note: "UVs exist; no image or face texture assignment. Neutral material is preview-only." },
  bounds: { min: bounds.min.toArray(), max: bounds.max.toArray(), size: bounds.getSize(new Vector3()).toArray(), units: "Blockbench units; visible exported body rest pose" },
  sockets: baseSocketDefinitions.map((s) => ({ ...s, parentUuid: data.groups.find((g) => g.name === s.parent).uuid })),
};
// Bake source animation tracks as node-local TRS channels for preview playback.
// Source rest pose, geometry and hierarchy are unchanged; clip names are kept verbatim
// so the app's animationMapping continues to resolve them. Rotation follows Blockbench's
// additive Euler model (rest + keyframe, ZYX order); non-linear interpolation is treated as linear.
const recordByUuid = new Map(records.map((r) => [r.uuid, r]));
const animNumber = (value) => { const n = typeof value === "number" ? value : parseFloat(value); return Number.isFinite(n) ? n : 0; };
const bakedAnimations = [];
const animationBakeWarnings = [];
for (const animation of data.animations) {
  if (!animation.name || animation.name === "animation") continue;
  const channels = [], samplers = [];
  for (const [uuid, animator] of Object.entries(animation.animators ?? {})) {
    if (!animator.keyframes?.length) continue;
    const nodeIndex = nodeMap.get(uuid), rec = recordByUuid.get(uuid);
    if (nodeIndex === undefined || !rec) { animationBakeWarnings.push(`${animation.name}: ${animator.name ?? uuid} は出力ノードなし`); continue; }
    const grouped = { rotation: [], position: [], scale: [] };
    for (const keyframe of animator.keyframes) if (grouped[keyframe.channel]) grouped[keyframe.channel].push(keyframe);
    for (const [channel, keyframes] of Object.entries(grouped)) {
      if (!keyframes.length) continue;
      const ordered = [...new Map(keyframes.map((k) => [k.time, k])).values()].sort((a, b) => a.time - b.time);
      const path = channel === "rotation" ? "rotation" : channel === "position" ? "translation" : "scale";
      const interpolation = ordered.every((k) => k.interpolation === "step") ? "STEP" : "LINEAR";
      const output = [];
      for (const keyframe of ordered) {
        const point = keyframe.data_points?.[0] ?? {};
        if (channel === "rotation") {
          const q = new Quaternion(...quaternion([
            (rec.rotation?.[0] ?? 0) + animNumber(point.x),
            (rec.rotation?.[1] ?? 0) + animNumber(point.y),
            (rec.rotation?.[2] ?? 0) + animNumber(point.z),
          ]));
          output.push(q.x, q.y, q.z, q.w);
        } else if (channel === "position") {
          output.push(
            rec.translation[0] * BASE_COORDINATES.metersPerSourceUnit + animNumber(point.x) * BASE_COORDINATES.metersPerSourceUnit,
            rec.translation[1] * BASE_COORDINATES.metersPerSourceUnit + animNumber(point.y) * BASE_COORDINATES.metersPerSourceUnit,
            rec.translation[2] * BASE_COORDINATES.metersPerSourceUnit + animNumber(point.z) * BASE_COORDINATES.metersPerSourceUnit,
          );
        } else {
          output.push(animNumber(point.x ?? 1) || 1, animNumber(point.y ?? 1) || 1, animNumber(point.z ?? 1) || 1);
        }
      }
      samplers.push({ input: accessor(ordered.map((k) => k.time), 1), output: accessor(output, channel === "rotation" ? 4 : 3), interpolation });
      channels.push({ sampler: samplers.length - 1, target: { node: nodeIndex, path } });
    }
  }
  if (channels.length) bakedAnimations.push({ name: animation.name, channels, samplers });
}
if (bakedAnimations.length) gltf.animations = bakedAnimations;

const destination = new URL("../public/generated-assets/base_body/", import.meta.url);
await mkdir(destination, { recursive: true });
await writeFile(new URL("model.glb", destination), finish());
await writeFile(new URL("analysis.json", destination), JSON.stringify(analysis, null, 2) + "\n");
await writeFile(new URL("asset.json", destination), JSON.stringify({ specVersion: 1, assetVersion: 1, id: "base_body", name: "Base Body · base_1.bbmodel", type: "base", bodyTypes: ["adult"], appearance: { paletteSlots: [] }, hairPolicy: null, hideParts: [], model: "model.glb", source: { format: "bbmodel", path: BASE_COORDINATES.source } }, null, 2) + "\n");
const report = ["# Base Model Analysis", "", `Source: \`${BASE_COORDINATES.source}\``, `SHA-256: \`${sha256}\``, "", "Generated by `npm run build:base`. Do not edit generated results.", "", "## Counts and bounds", "", "```json", JSON.stringify({ counts: analysis.counts, bounds: analysis.bounds, coordinates: BASE_COORDINATES }, null, 2), "```", "", "## Existing groups → semantic roles", "", "Group | UUID | Parent UUID | Pivot (BB units) | Role | Classification", "--- | --- | --- | --- | --- | ---", ...groupRecords.map((g) => `${g.name} | ${g.uuid} | ${g.parent ?? "root"} | ${g.origin.join(", ")} | ${g.role ?? "—"} | ${g.classification}`), "", "## Base Body Parts", "", "Name | UUID | Parent UUID | Visible | Exported", "--- | --- | --- | --- | ---", ...bodyParts.map((p) => `${p.name} | ${p.uuid} | ${p.parent} | ${p.visible} | ${p.exported}`), "", "## Source animations (not played or converted in this phase)", "", "Name | Duration (seconds) | Loop | Keyframes", "--- | --- | --- | ---", ...animations.map((a) => `${a.name} | ${a.length} | ${a.loop} | ${a.keyframeCount}`), "", "## Interpretation", "", "- `hand_left/right` contain upper arms; actual hand pivots are `hand_left_te/right_te`.", "- `foot_left/right` are thigh parents; `ashi_left/right` contain ankle and foot meshes. There is no independent foot bone.", "- `kubi`, `kata_*`, `mimi_*` are meshes, not separate animation groups. No synthetic skeleton is created.", "- `ganmenn` is the visible head. The source has 20 body meshes; there is no beveled_cuboid replacement.", "- `gread_sword` and `allow` are unchanged source spellings. `allow` is a projectile candidate, not a renamed arrow.", "- Weapon placement follows original hierarchy (sword/spear left, bow/shield right), without enforcing new handedness rules.", "- Texture images: 0. UV resolution: 32×32. Full per-face UVs are in analysis.json; GLB includes normalized UVs and a neutral material.", "- Socket definitions are app-only, at existing group pivots, uncalibrated. They do not imply validated grip or equipment fit.", "- Runtime uses 1/12 scale and unchanged +X forward / +Y up, matching the Explorer export pipeline. No automatic centering or normalization.", "- Preview exports 20 visible body meshes and preserves all 46 group nodes. Hidden/equipment meshes are excluded only from the derived preview, never deleted from source.", "- See phase-2.md and comparison.json for the game parity gate. Equipment assembly remains blocked until parity is resolved.", ""];
await mkdir(new URL("../docs/", import.meta.url), { recursive: true });
await writeFile(new URL("../docs/base-model-analysis.md", import.meta.url), report.join("\n"));
if (createHash("sha256").update(await readFile(sourceUrl)).digest("hex") !== sha256) throw new Error("Source changed during generation");
console.log(JSON.stringify({ output: fileURLToPath(destination), ...analysis.counts, bakedAnimations: bakedAnimations.map((a) => a.name), animationBakeWarnings, bounds: analysis.bounds, sha256 }, null, 2));
