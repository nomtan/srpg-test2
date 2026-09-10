// Original, deliberately unrigged fixtures. No game assets or external downloads.
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { BoxGeometry } from "three";

const geometry = new BoxGeometry(1, 1, 1);
const chunks = [];
const bufferViews = [];
const accessors = [];
let byteLength = 0;
function add(array, componentType, type, target, bounds = {}) {
  const data = Buffer.from(array.buffer, array.byteOffset, array.byteLength);
  bufferViews.push({ buffer: 0, byteOffset: byteLength, byteLength: data.length, target });
  chunks.push(data);
  const padding = (4 - data.length % 4) % 4;
  if (padding) chunks.push(Buffer.alloc(padding));
  byteLength += data.length + padding;
  accessors.push({ bufferView: bufferViews.length - 1, componentType, count: array.length / (type === "VEC3" ? 3 : 1), type, ...bounds });
  return accessors.length - 1;
}
const position = add(geometry.attributes.position.array, 5126, "VEC3", 34962, { min: [-.5, -.5, -.5], max: [.5, .5, .5] });
const normal = add(geometry.attributes.normal.array, 5126, "VEC3", 34962);
const indices = add(geometry.index.array, 5123, "SCALAR", 34963);
const binary = Buffer.concat(chunks);
const colors = [[.62,.72,.76,1],[.32,.47,.48,1],[.76,.49,.22,1],[.28,.16,.09,1]];
// [name, translation, scale, material]
const fixtures = {
  demo_adult_001: [
    ["body",[0,1.05,0],[.5,.65,.28],1], ["head",[0,1.58,0],[.4,.4,.4],0],
    ["arm_left",[-.36,1.05,0],[.18,.6,.22],0], ["arm_right",[.36,1.05,0],[.18,.6,.22],0],
    ["leg_left",[-.14,.36,0],[.22,.72,.25],1], ["leg_right",[.14,.36,0],[.22,.72,.25],1],
  ],
  demo_sword_001: [["blade",[0,.95,0],[.12,1.05,.055],0],["guard",[0,.4,0],[.4,.08,.1],2],["grip",[0,.22,0],[.085,.3,.085],3],["pommel",[0,.045,0],[.12,.09,.12],2]],
  demo_shield_001: [["shield",[0,.55,0],[.66,1,.13],3],["rim_top",[0,1.02,0],[.72,.075,.17],2],["rim_bottom",[0,.08,0],[.72,.075,.17],2],["rim_left",[-.33,.55,0],[.075,1,.17],2],["rim_right",[.33,.55,0],[.075,1,.17],2],["boss",[0,.55,.12],[.2,.2,.12],0]],
};
for (const [id, parts] of Object.entries(fixtures)) {
  const nodes = parts.map(([name, translation, scale, material]) => ({ name, translation, scale, mesh: material }));
  if (id === "demo_sword_001") nodes.push({ name: "grip_main", translation: [0,.22,0] });
  const gltf = {
    asset: { version: "2.0", generator: "SRPG Character Workshop demo fixture" },
    scene: 0, scenes: [{ nodes: nodes.map((_, index) => index) }], nodes,
    meshes: colors.map((_, material) => ({ primitives: [{ attributes: { POSITION: position, NORMAL: normal }, indices, material }] })),
    materials: colors.map((baseColorFactor) => ({ pbrMetallicRoughness: { baseColorFactor, metallicFactor: .1, roughnessFactor: .8 } })),
    buffers: [{ byteLength }], bufferViews, accessors,
  };
  const json = Buffer.from(JSON.stringify(gltf));
  const paddedJson = Buffer.concat([json, Buffer.alloc((4 - json.length % 4) % 4, 0x20)]);
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(12 + 8 + paddedJson.length + 8 + binary.length, 8);
  const jsonHeader = Buffer.alloc(8); jsonHeader.writeUInt32LE(paddedJson.length); jsonHeader.writeUInt32LE(0x4e4f534a,4);
  const binHeader = Buffer.alloc(8); binHeader.writeUInt32LE(binary.length); binHeader.writeUInt32LE(0x004e4942,4);
  const directory = fileURLToPath(new URL(`../public/demo-assets/${id}/`, import.meta.url));
  await mkdir(directory, { recursive: true });
  await writeFile(`${directory}/model.glb`, Buffer.concat([header,jsonHeader,paddedJson,binHeader,binary]));
  console.log(`Generated ${id}/model.glb`);
}
geometry.dispose();
