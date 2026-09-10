"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

function disposeObject(root: THREE.Object3D) {
  const geometries = new Set<THREE.BufferGeometry>();
  const materials = new Set<THREE.Material>();
  const textures = new Set<THREE.Texture>();
  root.traverse((object) => {
    if (object instanceof THREE.Mesh || object instanceof THREE.Line) {
      geometries.add(object.geometry);
      for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
        materials.add(material);
        for (const value of Object.values(material)) if (value instanceof THREE.Texture) textures.add(value);
      }
    }
    if (object instanceof THREE.SkinnedMesh) object.skeleton.dispose();
  });
  geometries.forEach((geometry) => geometry.dispose());
  materials.forEach((material) => material.dispose());
  textures.forEach((texture) => { texture.dispose(); if (typeof ImageBitmap !== "undefined" && texture.image instanceof ImageBitmap) texture.image.close(); });
}

/** Each URL gets its own lifecycle so a late load cannot replace a newer selection. */
function PreviewScene({ url, name }: { url: string; name: string }) {
  const host = useRef<HTMLDivElement>(null);
  const reset = useRef<() => void>(() => {});
  const [status, setStatus] = useState("GLBを読み込み中…");
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    const container = host.current!;
    let alive = true;
    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ antialias: true }); }
    catch { queueMicrotask(() => { if (alive) { setFailed(true); setStatus("3D Previewを開始できません。WebGL対応ブラウザを使用してください。"); } }); return () => { alive = false; }; }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x121d28);
    container.appendChild(renderer.domElement);
    renderer.domElement.setAttribute("aria-label", `${name} の3D Preview`);
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 1000);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.enablePan = false;
    scene.add(new THREE.HemisphereLight(0xd5edff, 0x746653, 2.4));
    const light = new THREE.DirectionalLight(0xffffff, 3);
    light.position.set(3, 5, 4);
    scene.add(light);
    let radius = 1;
    const target = new THREE.Vector3();
    reset.current = () => {
      const fov = THREE.MathUtils.degToRad(camera.fov);
      const limitingFov = Math.min(fov, 2 * Math.atan(Math.tan(fov / 2) * camera.aspect));
      const distance = radius / Math.sin(limitingFov / 2) * 1.2;
      camera.position.copy(target).add(new THREE.Vector3(1, 0.65, 1.5).normalize().multiplyScalar(distance));
      camera.near = Math.max(radius / 100, 0.001);
      camera.far = distance + radius * 100;
      camera.updateProjectionMatrix();
      controls.target.copy(target);
      controls.minDistance = radius * 1.2;
      controls.maxDistance = distance * 5;
      controls.update();
    };
    const observer = new ResizeObserver(() => {
      const { width, height } = container.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      reset.current();
    });
    observer.observe(container);
    const onLost = (event: Event) => { event.preventDefault(); setFailed(true); setStatus("WebGL接続が失われました。ページを再読み込みしてください。"); };
    renderer.domElement.addEventListener("webglcontextlost", onLost);
    new GLTFLoader().load(url, (gltf) => {
      if (!alive) { gltf.scenes.forEach(disposeObject); return; }
      const box = new THREE.Box3().setFromObject(gltf.scene);
      if (box.isEmpty()) { gltf.scenes.forEach(disposeObject); setFailed(true); setStatus("このGLBには表示可能なモデルがありません。"); return; }
      scene.add(gltf.scene);
      box.getCenter(target);
      radius = Math.max(box.getBoundingSphere(new THREE.Sphere()).radius, 0.01);
      const gridSize = Math.max(4, Math.ceil(radius * 6));
      const grid = new THREE.GridHelper(gridSize, gridSize, 0x466074, 0x293c4b);
      grid.position.set(target.x, box.min.y - 0.002, target.z);
      scene.add(grid);
      scene.add(new THREE.AxesHelper(1));
      reset.current();
      setStatus("");
    }, undefined, () => { if (alive) { setFailed(true); setStatus("GLBを読み込めませんでした。ファイルの場所と形式を確認してください。"); } });
    renderer.setAnimationLoop(() => { controls.update(); renderer.render(scene, camera); });
    return () => {
      alive = false;
      observer.disconnect();
      renderer.setAnimationLoop(null);
      renderer.domElement.removeEventListener("webglcontextlost", onLost);
      controls.dispose();
      disposeObject(scene);
      renderer.dispose();
      renderer.domElement.remove();
      reset.current = () => {};
    };
  }, [url, name]);
  return <div className="preview">
    <div ref={host} className="viewport" />
    <span className="preview-tag">GLB / REST POSE · GRID 1m · X赤 / Y緑 / Z青</span>
    {status && <div className="preview-message" role={failed ? "alert" : "status"}>{status}</div>}
    <div className="preview-toolbar"><span>ドラッグで回転 · スクロールでズーム</span><button onClick={() => reset.current()}>視点をリセット</button></div>
  </div>;
}

export function AssetPreview({ url, name }: { url: string | null; name: string }) {
  return url ? <PreviewScene key={url} url={url} name={name} /> : <div className="preview empty">PreviewするGLBがありません。</div>;
}
