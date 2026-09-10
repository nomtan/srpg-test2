import { Quaternion, Euler, Vector3 } from "three";

export const quaternion = (degrees = [0, 0, 0]) => new Quaternion().setFromEuler(new Euler(...degrees.map((v) => v * Math.PI / 180), "ZYX")).toArray();

// Blockbench 5 saves sorted mesh face vertices (MeshFace.getSaveCopy).
// Reject unsupported shapes rather than silently approximate a changed source.
export function meshTriangles(element, resolution, scale) {
  if (element.type !== "mesh") throw new Error(`Preview requires mesh conversion: ${element.name}`);
  const positions = [], normals = [], uvs = [];
  for (const face of Object.values(element.faces)) {
    if (face.texture === null) continue;
    const keys = face.vertices;
    if (![3, 4].includes(keys.length)) throw new Error(`Unsupported face in ${element.name}`);
    for (let i = 1; i < keys.length - 1; i++) {
      const triangle = [keys[0], keys[i], keys[i + 1]];
      const points = triangle.map((key) => new Vector3(...element.vertices[key]).multiplyScalar(scale));
      const normal = points[1].clone().sub(points[0]).cross(points[2].clone().sub(points[0]));
      if (normal.lengthSq() < 1e-20) throw new Error(`Degenerate face in ${element.name}`);
      normal.normalize();
      for (let j = 0; j < 3; j++) {
        positions.push(...points[j].toArray()); normals.push(...normal.toArray());
        const uv = face.uv[triangle[j]];
        if (!uv) throw new Error(`Missing UV in ${element.name}`);
        // glTF UV origin is upper-left, same as source pixel coordinates.
        uvs.push(uv[0] / resolution.width, uv[1] / resolution.height);
      }
    }
  }
  return { positions, normals, uvs };
}

export function createGlbWriter() {
  const gltf = { asset: { version: "2.0", generator: "Character Workshop source-preserving base converter v1" }, scene: 0, scenes: [{ nodes: [] }], nodes: [], meshes: [], materials: [{ name: "Untextured source", doubleSided: true, pbrMetallicRoughness: { baseColorFactor: [0.72, 0.72, 0.72, 1], metallicFactor: 0, roughnessFactor: 1 } }], accessors: [], bufferViews: [] };
  const chunks = [];
  let length = 0;
  function accessor(values, width) {
    const array = new Float32Array(values);
    const data = Buffer.from(array.buffer);
    const view = gltf.bufferViews.length;
    gltf.bufferViews.push({ buffer: 0, byteOffset: length, byteLength: data.length });
    chunks.push(data); length += data.length;
    const index = gltf.accessors.length;
    gltf.accessors.push({ bufferView: view, componentType: 5126, count: values.length / width, type: width === 1 ? "SCALAR" : `VEC${width}`,
      min: Array.from({ length: width }, (_, axis) => Math.min(...values.filter((_, i) => i % width === axis))),
      max: Array.from({ length: width }, (_, axis) => Math.max(...values.filter((_, i) => i % width === axis))),
    });
    return index;
  }
  function finish() {
    gltf.buffers = [{ byteLength: length }];
    const json = Buffer.from(JSON.stringify(gltf));
    const padded = Buffer.concat([json, Buffer.alloc((4 - json.length % 4) % 4, 32)]);
    const header = Buffer.alloc(20);
    header.writeUInt32LE(0x46546c67); header.writeUInt32LE(2, 4); header.writeUInt32LE(28 + padded.length + length, 8);
    header.writeUInt32LE(padded.length, 12); header.writeUInt32LE(0x4e4f534a, 16);
    const binHeader = Buffer.alloc(8); binHeader.writeUInt32LE(length); binHeader.writeUInt32LE(0x004e4942, 4);
    return Buffer.concat([header, padded, binHeader, ...chunks]);
  }
  return { gltf, accessor, finish };
}
