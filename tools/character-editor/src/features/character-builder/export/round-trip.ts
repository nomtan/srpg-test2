// Round-trip validation (spec section 23 / prompt 22-23): re-import the baked GLB into Three.js
// and confirm the character survived the Bake -> GLB Export -> Re-import path.
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { REQUIRED_RIG_NODES } from "../character-scene";
import type { ExportIssue } from "./export-validation";
import type { EquipmentPlacement } from "../character-scene";

export interface RoundTripStats {
  meshCount: number;
  materialCount: number;
  textureCount: number;
  animationNames: string[];
  boundingBox: { min: [number, number, number]; max: [number, number, number]; size: [number, number, number] };
  missingRigNodes: string[];
}

export interface RoundTripReport {
  ok: boolean;
  issues: ExportIssue[];
  stats: RoundTripStats;
}

export interface RoundTripExpectation {
  restSize: [number, number, number];
  equipment: EquipmentPlacement[];
  requiredClips: string[];
}

const SIZE_TOLERANCE = 0.05; // 5%
const EQUIP_TOLERANCE = 0.15; // metres

export async function roundTrip(buffer: ArrayBuffer, expect: RoundTripExpectation): Promise<RoundTripReport> {
  const gltf = await new Promise<Awaited<ReturnType<GLTFLoader["loadAsync"]>>>((resolve, reject) => {
    new GLTFLoader().parse(buffer.slice(0), "", resolve, reject);
  });
  const scene = gltf.scene;
  scene.updateWorldMatrix(true, true);

  const materials = new Set<THREE.Material>();
  const textures = new Set<THREE.Texture>();
  let meshCount = 0;
  scene.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh || !mesh.geometry) return;
    meshCount += 1;
    for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
      if (!m) continue;
      materials.add(m);
      for (const v of Object.values(m)) if (v instanceof THREE.Texture) textures.add(v);
    }
  });

  const box = new THREE.Box3().setFromObject(scene);
  const size = box.getSize(new THREE.Vector3());
  const missingRigNodes = REQUIRED_RIG_NODES.filter((n) => !scene.getObjectByName(n));
  const animationNames = gltf.animations.map((c) => c.name);

  const issues: ExportIssue[] = [];
  const add = (level: ExportIssue["level"], section: ExportIssue["section"], message: string) => issues.push({ level, section, message });

  if (meshCount === 0) add("error", "assets", "Re-import: Mesh がありません。");
  if (materials.size === 0) add("error", "texture", "Re-import: Material がありません。");
  if (textures.size === 0) add("warning", "texture", "Re-import: 埋め込みテクスチャがありません（パレットは baseColorFactor に焼き込み済み）。");
  if (missingRigNodes.length) add("warning", "rig", `Re-import: rig ノード欠落: ${missingRigNodes.join(", ")}`);

  for (const axis of [0, 1, 2] as const) {
    const v = size.getComponent(axis);
    if (!Number.isFinite(v) || v <= 0) add("error", "scale", `Re-import: Bounding Box の軸 ${"XYZ"[axis]} が不正です (${v}).`);
  }
  const sy = size.y;
  if (sy < 0.8 || sy > 3.0) add("warning", "scale", `Re-import: 身長 ${sy.toFixed(3)} m が想定 (0.8–3.0 m) 外です。`);
  for (const axis of [0, 1, 2] as const) {
    const got = size.getComponent(axis);
    const want = expect.restSize[axis];
    if (want > 1e-4) {
      const drift = Math.abs(got - want) / want;
      if (drift > SIZE_TOLERANCE) add("warning", "scale", `Re-import: ${"XYZ"[axis]} 寸法が ${(drift * 100).toFixed(1)}% ずれています (bake ${want.toFixed(3)} → re-import ${got.toFixed(3)} m)。`);
    }
  }

  if (gltf.animations.length === 0) add("error", "rig", "Re-import: Animation がありません。");
  for (const clip of expect.requiredClips) {
    if (!animationNames.includes(clip)) add("warning", "rig", `Re-import: Animation clip がありません: ${clip}`);
  }

  for (const eq of expect.equipment) {
    if (!eq.visible) continue;
    const node = scene.getObjectByName(eq.nodeName);
    if (!node) { add("warning", "assets", `Re-import: 装備ノードがありません: ${eq.nodeName} (${eq.slot})`); continue; }
    node.updateWorldMatrix(true, true);
    const wp = node.getWorldPosition(new THREE.Vector3());
    const d = Math.hypot(wp.x - eq.worldPosition[0], wp.y - eq.worldPosition[1], wp.z - eq.worldPosition[2]);
    if (d > EQUIP_TOLERANCE) add("warning", "assets", `Re-import: ${eq.slot} (${eq.nodeName}) の位置が ${(d * 100).toFixed(1)} cm ずれています。`);
    else add("info", "assets", `Re-import: ${eq.slot} 位置一致 (Δ ${(d * 1000).toFixed(1)} mm)。`);
  }

  scene.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (mesh.isMesh) mesh.geometry?.dispose();
  });
  materials.forEach((m) => m.dispose());
  textures.forEach((t) => t.dispose());

  return {
    ok: !issues.some((i) => i.level === "error"),
    issues,
    stats: {
      meshCount,
      materialCount: materials.size,
      textureCount: textures.size,
      animationNames,
      boundingBox: {
        min: box.min.toArray() as [number, number, number],
        max: box.max.toArray() as [number, number, number],
        size: size.toArray() as [number, number, number],
      },
      missingRigNodes,
    },
  };
}
