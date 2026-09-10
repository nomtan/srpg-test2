import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { Box3, Vector3 } from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { BASE_COORDINATES, baseRigMapping, baseSocketDefinitions } from "../src/domain/base-rig.ts";

const root = new URL("../../../", import.meta.url);
const sourceBytes = await readFile(new URL(BASE_COORDINATES.source, root));
const source = JSON.parse(sourceBytes);
const generatedRoot = new URL("../public/generated-assets/base_body/", import.meta.url);
const analysis = JSON.parse(await readFile(new URL("analysis.json", generatedRoot)));
assert.equal(createHash("sha256").update(sourceBytes).digest("hex"), analysis.source.sha256, "Source changed: rebuild required");
async function load(url) {
  const bytes = await readFile(url);
  const gltf = await new GLTFLoader().parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), "");
  gltf.scene.updateMatrixWorld(true);
  return gltf;
}
const generated = await load(new URL("model.glb", generatedRoot));
const nodes = new Map();
generated.scene.traverse((node) => { if (node.userData.sourceUuid) nodes.set(node.userData.sourceUuid, node); });
// Phase 4: preview-only animation bake. Every baked clip must map 1:1 to a named source
// clip and target only original group nodes; geometry/rest parity is still asserted below.
const sourceClipNames = new Set(source.animations.map((a) => a.name).filter((n) => n && n !== "animation"));
for (const clip of generated.animations) {
  assert.ok(sourceClipNames.has(clip.name), `Baked clip not in source: ${clip.name}`);
  for (const track of clip.tracks) {
    const nodeName = track.name.split(".")[0];
    assert.ok([...nodes.values()].some((n) => n.name === nodeName), `Baked clip ${clip.name} targets unknown node ${nodeName}`);
  }
}
assert.ok(generated.animations.length <= sourceClipNames.size, "More baked clips than source clips");
for (const group of source.groups) {
  const node = nodes.get(group.uuid);
  assert.ok(node, `Missing original group ${group.name}`);
  const record = analysis.groups.find((r) => r.uuid === group.uuid);
  assert.equal(node.parent.userData.sourceUuid ?? null, record.parent, `Reparented group ${group.name}`);
  assert.equal(generated.parser.json.nodes[generated.parser.associations.get(node).nodes].name, group.name);
}
for (const name of Object.keys(baseRigMapping)) assert.equal(source.groups.filter((g) => g.name === name).length, 1);
for (const socket of baseSocketDefinitions) assert.ok(source.groups.some((g) => g.name === socket.parent));
let comparedVertices = 0;
const sourceObjects = new Map([...source.groups, ...source.elements].map((o) => [o.uuid, o]));
const parents = new Map();
function indexParents(entry, parent = null) {
  const id = typeof entry === "string" ? entry : entry.uuid;
  parents.set(id, parent);
  if (typeof entry !== "string") for (const child of entry.children ?? []) indexParents(child, id);
}
source.outliner.forEach((entry) => indexParents(entry));
// Independent source-space oracle: rotate X then Y then Z, then add pivot delta,
// walking upward through the original Outliner. No exporter matrices are reused.
function sourceWorldPoint(uuid, local) {
  let point = [...local];
  while (uuid) {
    const object = sourceObjects.get(uuid);
    const [rx, ry, rz] = (object.rotation ?? [0, 0, 0]).map((v) => v * Math.PI / 180);
    let [x, y, z] = point;
    [y, z] = [y * Math.cos(rx) - z * Math.sin(rx), y * Math.sin(rx) + z * Math.cos(rx)];
    [x, z] = [x * Math.cos(ry) + z * Math.sin(ry), -x * Math.sin(ry) + z * Math.cos(ry)];
    [x, y] = [x * Math.cos(rz) - y * Math.sin(rz), x * Math.sin(rz) + y * Math.cos(rz)];
    const parent = parents.get(uuid);
    const origin = object.origin ?? [0, 0, 0];
    const parentOrigin = sourceObjects.get(parent)?.origin ?? [0, 0, 0];
    point = [x, y, z].map((v, i) => v + origin[i] - parentOrigin[i]);
    uuid = parent;
  }
  return new Vector3(...point).multiplyScalar(BASE_COORDINATES.metersPerSourceUnit);
}
for (const part of analysis.bodyParts) {
  const node = nodes.get(part.uuid);
  if (!part.visible || !part.exported) { assert.ok(!node); continue; }
  assert.ok(node?.isMesh, `Missing body mesh ${part.name}`);
  const element = source.elements.find((e) => e.uuid === part.uuid);
  const expected = new Map(Object.entries(element.vertices).map(([key, vertex]) => [key, sourceWorldPoint(element.uuid, vertex)]));
  const actual = node.geometry.attributes.position;
  const actualUV = node.geometry.attributes.uv;
  assert.ok(actualUV && actual.count === actualUV.count);
  const unique = [];
  for (let i = 0; i < actual.count; i++) unique.push(new Vector3().fromBufferAttribute(actual, i).applyMatrix4(node.matrixWorld));
  for (const point of expected.values()) assert.ok(unique.some((p) => p.distanceTo(point) < 1e-6), `Missing/moved vertex ${part.name}`);
  for (const point of unique) assert.ok([...expected.values()].some((p) => p.distanceTo(point) < 1e-6), `Unexpected vertex ${part.name}`);
  let uvIndex = 0;
  for (const face of Object.values(element.faces)) {
    if (face.texture === null) continue;
    for (let i = 1; i < face.vertices.length - 1; i++) for (const key of [face.vertices[0], face.vertices[i], face.vertices[i + 1]]) {
      assert.ok(Math.abs(actualUV.getX(uvIndex) - face.uv[key][0] / source.resolution.width) < 1e-6);
      assert.ok(Math.abs(actualUV.getY(uvIndex) - face.uv[key][1] / source.resolution.height) < 1e-6);
      uvIndex++;
    }
  }
  assert.equal(uvIndex, actual.count);
  comparedVertices += expected.size;
}
function describe(gltf) {
  const box = new Box3().setFromObject(gltf.scene);
  const points = [], meshes = [], pivots = {}, surfaces = {};
  function sourcePath(node) {
    const index = gltf.parser.associations.get(node)?.nodes;
    if (index === undefined) return "";
    return `${sourcePath(node.parent)}/${gltf.parser.json.nodes[index].name}`;
  }
  gltf.scene.traverse((node) => {
    const association = gltf.parser.associations.get(node);
    const original = association?.nodes !== undefined ? gltf.parser.json.nodes[association.nodes] : undefined;
    if (original && original.mesh === undefined) pivots[original.name] = node.getWorldPosition(new Vector3()).toArray();
    if (!node.isMesh) return;
    meshes.push(original?.name ?? node.name);
    const positions = node.geometry.attributes.position;
    const path = sourcePath(node);
    surfaces[path] = [];
    for (let i = 0; i < positions.count; i++) {
      const point = new Vector3().fromBufferAttribute(positions, i).applyMatrix4(node.matrixWorld);
      surfaces[path].push(point);
      if (!points.some((p) => p.distanceTo(point) < 1e-6)) points.push(point);
    }
  });
  return { bounds: { min: box.min.toArray(), max: box.max.toArray(), size: box.getSize(new Vector3()).toArray() }, meshes, points, pivots, surfaces };
}
const current = describe(generated);
const comparisons = [];
for (const path of ["assets/characters/base/base.glb", "assets/world_jrpg/explorer_base_1.glb"]) {
  const reference = describe(await load(new URL(path, root)));
  const commonGroups = Object.keys(baseRigMapping).filter((name) => reference.pivots[name]);
  const maxPivotDelta = Math.max(...commonGroups.map((name) => new Vector3(...current.pivots[name]).distanceTo(new Vector3(...reference.pivots[name]))));
  const identicalTriangles = Object.keys(current.surfaces).length === Object.keys(reference.surfaces).length && Object.entries(current.surfaces).every(([key, positions]) => {
    const other = reference.surfaces[key];
    return other?.length === positions.length && positions.every((p, i) => p.distanceTo(other[i]) < 1e-6);
  });
  comparisons.push({ path, bounds: reference.bounds, meshes: reference.meshes, commonGroupCount: commonGroups.length, maxCommonGroupPivotDeltaMeters: maxPivotDelta,
    identicalTriangles,
    identicalWorldVertexSet: current.points.length === reference.points.length && current.points.every((p) => reference.points.some((q) => p.distanceTo(q) < 1e-6)),
    generatedOnlyWorldPoints: current.points.filter((p) => !reference.points.some((q) => p.distanceTo(q) < 1e-6)).length,
    referenceOnlyWorldPoints: reference.points.filter((p) => !current.points.some((q) => p.distanceTo(q) < 1e-6)).length,
  });
}
const explorer = comparisons.find((c) => c.path === "assets/world_jrpg/explorer_base_1.glb");
const numericParity = explorer.identicalTriangles && explorer.identicalWorldVertexSet && explorer.maxCommonGroupPivotDeltaMeters < 1e-6 && explorer.meshes.length === analysis.counts.previewMeshes;
const report = { sourceSha256: analysis.source.sha256, sourceFidelity: { verified: true, groups: source.groups.length, visibleBodyMeshes: analysis.counts.previewMeshes, comparedSourceVertices: comparedVertices, uvVerified: true, toleranceMeters: 1e-6 }, generated: { bounds: current.bounds, meshes: current.meshes }, comparisons,
  parityGate: { status: numericParity ? "numeric_pass_visual_pending" : "not_passed", numericParity, reason: numericParity ? "Rest-pose geometry, scale and orientation match Explorer within 1e-6 m. Browser/Godot visual review still required; animation and material appearance are outside this comparison." : "Generated model differs from Explorer; resolve before equipment assembly.", equipmentAssemblyAllowed: false } };
await writeFile(new URL("comparison.json", generatedRoot), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
