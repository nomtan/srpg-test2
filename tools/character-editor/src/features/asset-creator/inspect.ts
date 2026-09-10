"use client";

import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import type { GlbStats, TextureStats } from "@/domain/asset-validation";

function disposeScene(root: THREE.Object3D) {
  root.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (mesh.isMesh) {
      mesh.geometry?.dispose();
      for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) m?.dispose();
    }
  });
}

export async function inspectGlb(url: string): Promise<GlbStats> {
  const gltf = await new GLTFLoader().loadAsync(url);
  const scene = gltf.scene;
  const materials = new Set<THREE.Material>();
  const nodeNames: string[] = [];
  let meshCount = 0;
  let triangleCount = 0;
  scene.traverse((object) => {
    if (object.name) nodeNames.push(object.name);
    const mesh = object as THREE.Mesh;
    if (!mesh.isMesh || !mesh.geometry) return;
    meshCount += 1;
    for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) if (m) materials.add(m);
    const geo = mesh.geometry;
    const indexed = geo.getIndex();
    const verts = indexed ? indexed.count : geo.getAttribute("position")?.count ?? 0;
    triangleCount += Math.floor(verts / 3);
  });
  scene.updateWorldMatrix(true, true);
  const box = new THREE.Box3().setFromObject(scene);
  const empty = box.isEmpty();
  const size = empty ? new THREE.Vector3() : box.getSize(new THREE.Vector3());
  const stats: GlbStats = {
    hasMesh: meshCount > 0 && !empty,
    meshCount,
    materialCount: materials.size,
    triangleCount,
    boundingBox: {
      min: empty ? [0, 0, 0] : box.min.toArray() as [number, number, number],
      max: empty ? [0, 0, 0] : box.max.toArray() as [number, number, number],
      size: size.toArray() as [number, number, number],
    },
    nodeNames,
  };
  disposeScene(scene);
  return stats;
}

export async function inspectImage(url: string): Promise<TextureStats> {
  const image = await new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("画像を読み込めませんでした。"));
    img.src = url;
  });
  const width = image.naturalWidth;
  const height = image.naturalHeight;
  let hasAlpha = false;
  try {
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (ctx) {
      ctx.drawImage(image, 0, 0);
      const data = ctx.getImageData(0, 0, width, height).data;
      for (let i = 3; i < data.length; i += 4) {
        if (data[i] < 255) { hasAlpha = true; break; }
      }
    }
  } catch {
    // Canvas read can throw for cross-origin images; object URLs are same-origin so this is best-effort.
  }
  return { width, height, hasAlpha };
}
