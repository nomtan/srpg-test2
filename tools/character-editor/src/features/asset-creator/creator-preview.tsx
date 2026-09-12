"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { AnimationController } from "@/viewer/animation/AnimationController";
import type { CharacterSocket } from "@/domain/constants";
import type { GlbStats } from "@/domain/asset-validation";
import { socketNodeName } from "./base-parts";
import { inspectGlb } from "./inspect";

const BASE_MODEL_URL = "/generated-assets/base_body/model.glb";

export interface CreatorPreviewProps {
  assetModelUrl: string | null;
  assetTextureUrl: string | null;
  mode: "asset" | "base";
  socket: CharacterSocket;
  paletteColor: string | null;
  hideParts: string[];
  animationClip: string | null;
  animationPlaying: boolean;
  animationSpeed: number;
  animationLoop: boolean;
  /** Reference hair block at socket_hair to demo hairPolicy (spec section 13). */
  referenceHair: "none" | "shown" | "hidden";
  /** Standard weapon orientation (Blockbench ZYX degrees) for grip-attached assets. */
  gripRotationDeg?: readonly [number, number, number] | null;
  captureSignal: number;
  onThumbnail?: (dataUrl: string) => void;
  onModelStats?: (stats: GlbStats | null) => void;
}

function disposeObject(root: THREE.Object3D) {
  root.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (mesh.isMesh || (object as THREE.Line).isLine) {
      (mesh.geometry as THREE.BufferGeometry | undefined)?.dispose?.();
      const material = (mesh as THREE.Mesh).material;
      for (const m of Array.isArray(material) ? material : material ? [material] : []) m.dispose();
    }
    if ((object as THREE.SkinnedMesh).isSkinnedMesh) (object as THREE.SkinnedMesh).skeleton?.dispose();
  });
}

export function CreatorPreview(props: CreatorPreviewProps) {
  const { mode, assetModelUrl, assetTextureUrl, captureSignal, onModelStats, onThumbnail } = props;
  const referenceHairEnabled = props.referenceHair !== "none";
  const hidePartsKey = props.hideParts.join("|");
  const host = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState("読み込み中…");
  const [failed, setFailed] = useState(false);

  const latest = useRef(props);
  useEffect(() => { latest.current = props; });

  const api = useRef<{
    renderer: THREE.WebGLRenderer;
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    controls: OrbitControls;
    assetRoot: THREE.Object3D | null;
    baseRoot: THREE.Object3D | null;
    anim: AnimationController | null;
    reset: () => void;
    thumbCam: THREE.PerspectiveCamera;
    helpers: THREE.Object3D[];
    referenceHair: THREE.Mesh | null;
  } | null>(null);
  const texture = useRef<{ url: string; map: THREE.Texture } | null>(null);
  /** The map each material shipped with, so removing the imported texture restores the GLB's own. */
  const originalMaps = useRef(new WeakMap<THREE.Material, THREE.Texture | null>());
  const captureRef = useRef(-1);

  function applyTexture() {
    const state = api.current;
    if (!state?.assetRoot) return;
    let withoutUv = 0;
    state.assetRoot.traverse((object) => {
      const mesh = object as THREE.Mesh;
      if (!mesh.isMesh) return;
      // Without UVs every pixel samples texel (0,0), which turns the asset into one flat colour
      // (usually black). Leave such meshes on their own material instead.
      if (!mesh.geometry?.getAttribute?.("uv")) { withoutUv += 1; return; }
      for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
        const material = m as THREE.MeshStandardMaterial;
        if (!material || !("map" in material)) continue;
        if (!originalMaps.current.has(material)) originalMaps.current.set(material, material.map ?? null);
        material.map = texture.current ? texture.current.map : originalMaps.current.get(material) ?? null;
        material.needsUpdate = true;
      }
    });
    if (withoutUv && texture.current) {
      setStatus(`UV を持たない Mesh が ${withoutUv} 個あるため Texture を適用していません。`);
    }
  }

  /** Metalness with no environment map renders black; this scene is flat-lit like the Builder. */
  function neutraliseMetalness(root: THREE.Object3D) {
    root.traverse((object) => {
      const mesh = object as THREE.Mesh;
      if (!mesh.isMesh) return;
      for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
        const material = m as THREE.MeshStandardMaterial;
        if (material && typeof material.metalness === "number" && material.metalness > 0) {
          material.metalness = 0;
          material.needsUpdate = true;
        }
      }
    });
  }

  function applyDynamic() {
    const state = api.current;
    const p = latest.current;
    if (!state) return;
    if (state.assetRoot) {
      state.assetRoot.traverse((object) => {
        const mesh = object as THREE.Mesh;
        if (!mesh.isMesh) return;
        for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
          const material = m as THREE.MeshStandardMaterial;
          // A base colour tint multiplies the texture, which reads as "my texture was ignored".
          // The palette swatch is an untextured-preview aid, so it only applies when there is no map.
          if (material.color) {
            if (material.map) material.color.set(0xffffff);
            else if (p.paletteColor) material.color.set(p.paletteColor);
          }
          for (const value of Object.values(material)) {
            if (value instanceof THREE.Texture) {
              value.magFilter = THREE.NearestFilter;
              value.minFilter = THREE.NearestFilter;
              value.generateMipmaps = false;
              value.needsUpdate = true;
            }
          }
        }
      });
    }
    if (state.baseRoot) {
      const hidden = new Set(p.hideParts);
      state.baseRoot.traverse((object) => {
        const mesh = object as THREE.Mesh;
        if (mesh.isMesh && object.name) object.visible = !hidden.has(object.name);
      });
    }
    if (state.referenceHair) state.referenceHair.visible = p.referenceHair === "shown";
  }

  function configureAnimation() {
    const state = api.current;
    const p = latest.current;
    if (!state?.anim) return;
    state.anim.configure({
      clip: p.animationClip,
      playing: p.animationPlaying && !!p.animationClip,
      speed: p.animationSpeed,
      loop: p.animationLoop,
      revision: 0,
    });
  }

  // Scene lifecycle: rebuilt when the display mode or the asset model changes.
  useEffect(() => {
    const container = host.current!;
    let alive = true;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    } catch {
      queueMicrotask(() => {
        if (!alive) return;
        setFailed(true);
        setStatus("3D Preview を開始できません。WebGL 対応ブラウザを使用してください。");
      });
      return () => { alive = false; };
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x121d28, 1);
    container.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 1000);
    const thumbCam = new THREE.PerspectiveCamera(35, 1, 0.01, 1000);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.enablePan = false;
    scene.add(new THREE.HemisphereLight(0xd5edff, 0x746653, 2.4));
    const light = new THREE.DirectionalLight(0xffffff, 3);
    light.position.set(3, 5, 4);
    scene.add(light);

    let radius = 1;
    const target = new THREE.Vector3();
    const helpers: THREE.Object3D[] = [];
    const reset = () => {
      const fov = THREE.MathUtils.degToRad(camera.fov);
      const limiting = Math.min(fov, 2 * Math.atan(Math.tan(fov / 2) * camera.aspect));
      const distance = (radius / Math.sin(limiting / 2)) * 1.2;
      camera.position.copy(target).add(new THREE.Vector3(1, 0.65, 1.5).normalize().multiplyScalar(distance));
      camera.near = Math.max(radius / 100, 0.001);
      camera.far = distance + radius * 100;
      camera.updateProjectionMatrix();
      controls.target.copy(target);
      controls.minDistance = radius * 0.6;
      controls.maxDistance = distance * 5;
      controls.update();
      thumbCam.position.copy(target).add(new THREE.Vector3(1, 0.5, 1).normalize().multiplyScalar(distance * 0.95));
      thumbCam.near = camera.near;
      thumbCam.far = camera.far;
      thumbCam.lookAt(target);
      thumbCam.updateProjectionMatrix();
    };

    const observer = new ResizeObserver(() => {
      const { width, height } = container.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      thumbCam.aspect = 1;
      reset();
    });
    observer.observe(container);

    const onLost = (event: Event) => {
      event.preventDefault();
      setFailed(true);
      setStatus("WebGL 接続が失われました。ページを再読み込みしてください。");
    };
    renderer.domElement.addEventListener("webglcontextlost", onLost);

    const state = {
      renderer, scene, camera, controls, thumbCam, helpers,
      assetRoot: null as THREE.Object3D | null,
      baseRoot: null as THREE.Object3D | null,
      anim: null as AnimationController | null,
      referenceHair: null as THREE.Mesh | null,
      reset,
    };
    api.current = state;

    const loader = new GLTFLoader();
    const loads: Promise<void>[] = [];

    if (mode === "base") {
      loads.push(loader.loadAsync(BASE_MODEL_URL).then((gltf) => {
        if (!alive) { disposeObject(gltf.scene); return; }
        state.baseRoot = gltf.scene;
        scene.add(gltf.scene);
        if (gltf.animations.length) state.anim = new AnimationController(gltf.scene, gltf.animations);
      }));
    }

    if (assetModelUrl) {
      loads.push(loader.loadAsync(assetModelUrl).then((gltf) => {
        if (!alive) { disposeObject(gltf.scene); return; }
        neutraliseMetalness(gltf.scene);
        state.assetRoot = gltf.scene;
      }).catch(() => {
        if (alive) { setFailed(true); setStatus("Asset GLB を読み込めませんでした。"); }
      }));
    }

    Promise.all(loads).then(() => {
      if (!alive) return;
      const p = latest.current;

      if (state.assetRoot) {
        if (mode === "base" && state.baseRoot) {
          const parentName = socketNodeName(p.socket);
          const socketNode = parentName
            ? state.baseRoot.getObjectByName(parentName)
            : null;
          (socketNode ?? state.baseRoot).add(state.assetRoot);
          if (!socketNode) {
            setStatus(`Socket 親ノード (${parentName ?? p.socket}) が見つかりません。ルートに取り付けました。`);
          }
          if (p.gripRotationDeg) {
            state.assetRoot.rotation.set(
              THREE.MathUtils.degToRad(p.gripRotationDeg[0]),
              THREE.MathUtils.degToRad(p.gripRotationDeg[1]),
              THREE.MathUtils.degToRad(p.gripRotationDeg[2]),
              "ZYX",
            );
          }
        } else {
          scene.add(state.assetRoot);
        }
      }

      if (mode === "base" && state.baseRoot && p.referenceHair !== "none") {
        const hairParent = state.baseRoot.getObjectByName("ganmen");
        if (hairParent) {
          const hair = new THREE.Mesh(
            new THREE.BoxGeometry(0.62, 0.12, 0.62),
            new THREE.MeshStandardMaterial({ color: 0x36251c, transparent: true, opacity: 0.75 }),
          );
          hair.name = "__reference_hair__";
          hair.position.y = 0.62;
          hairParent.add(hair);
          state.referenceHair = hair;
        }
      }

      const focusRoot = mode === "base" ? state.baseRoot ?? state.assetRoot : state.assetRoot;
      if (!focusRoot) {
        setFailed(true);
        setStatus(mode === "base" ? "Base モデルを読み込めませんでした。" : "表示する GLB がありません。Model を Import してください。");
        return;
      }
      focusRoot.updateWorldMatrix(true, true);
      const box = new THREE.Box3().setFromObject(focusRoot);
      if (box.isEmpty()) {
        setFailed(true);
        setStatus("表示可能なメッシュがありません。");
        return;
      }
      box.getCenter(target);
      radius = Math.max(box.getBoundingSphere(new THREE.Sphere()).radius, 0.01);
      const gridSize = Math.max(2, Math.ceil(radius * 4));
      const grid = new THREE.GridHelper(gridSize, gridSize, 0x466074, 0x293c4b);
      grid.position.set(target.x, box.min.y - 0.002, target.z);
      const axes = new THREE.AxesHelper(Math.max(radius * 0.5, 0.2));
      scene.add(grid, axes);
      helpers.push(grid, axes);

      applyTexture();
      applyDynamic();
      configureAnimation();
      reset();
      setStatus("");
    });

    const clock = new THREE.Clock();
    renderer.setAnimationLoop(() => {
      const delta = clock.getDelta();
      state.anim?.update(delta);
      controls.update();
      renderer.render(scene, camera);
    });

    return () => {
      alive = false;
      observer.disconnect();
      renderer.setAnimationLoop(null);
      renderer.domElement.removeEventListener("webglcontextlost", onLost);
      state.anim?.dispose();
      controls.dispose();
      disposeObject(scene);
      renderer.dispose();
      renderer.domElement.remove();
      api.current = null;
    };
  }, [mode, assetModelUrl, referenceHairEnabled]);

  // Report asset GLB stats for the validation panel.
  useEffect(() => {
    let alive = true;
    if (!assetModelUrl) { onModelStats?.(null); return; }
    inspectGlb(assetModelUrl)
      .then((stats) => { if (alive) onModelStats?.(stats); })
      .catch(() => { if (alive) onModelStats?.(null); });
    return () => { alive = false; };
  }, [assetModelUrl, onModelStats]);

  // Standalone texture load.
  useEffect(() => {
    const url = assetTextureUrl;
    if (texture.current && texture.current.url !== url) {
      texture.current.map.dispose();
      texture.current = null;
    }
    if (!url) { applyTexture(); applyDynamic(); return; }
    let alive = true;
    new THREE.TextureLoader().load(
      url,
      (map) => {
        if (!alive) { map.dispose(); return; }
        map.colorSpace = THREE.SRGBColorSpace;
        map.flipY = false;
        map.magFilter = THREE.NearestFilter;
        map.minFilter = THREE.NearestFilter;
        map.generateMipmaps = false;
        texture.current = { url, map };
        applyTexture();
        // Re-run the dynamic pass so the palette tint releases the freshly applied map.
        applyDynamic();
      },
      undefined,
      () => { if (alive) setStatus("Texture を読み込めませんでした。"); },
    );
    return () => { alive = false; };
  }, [assetTextureUrl]);

  useEffect(() => { applyDynamic(); }, [props.paletteColor, hidePartsKey, props.referenceHair]);
  useEffect(() => { configureAnimation(); }, [props.animationClip, props.animationPlaying, props.animationSpeed, props.animationLoop]);

  // Thumbnail capture (fixed 3/4 iso camera, transparent background).
  useEffect(() => {
    if (captureSignal === captureRef.current) return;
    captureRef.current = captureSignal;
    const state = api.current;
    if (!state || captureSignal < 0) return;
    const { renderer, scene, thumbCam, helpers } = state;
    const size = renderer.getSize(new THREE.Vector2());
    const visibility = helpers.map((h) => h.visible);
    helpers.forEach((h) => (h.visible = false));
    renderer.setClearAlpha(0);
    renderer.setSize(512, 512, false);
    thumbCam.aspect = 1;
    thumbCam.updateProjectionMatrix();
    renderer.render(scene, thumbCam);
    const dataUrl = renderer.domElement.toDataURL("image/png");
    renderer.setClearAlpha(1);
    renderer.setSize(size.x, size.y, false);
    state.camera.aspect = size.x / size.y || 1;
    state.camera.updateProjectionMatrix();
    helpers.forEach((h, i) => (h.visible = visibility[i]));
    onThumbnail?.(dataUrl);
  }, [captureSignal, onThumbnail]);

  return (
    <div className="preview">
      <div ref={host} className="viewport" />
      <span className="preview-tag">
        {mode === "base" ? "BASE + ASSET · " : "ASSET ONLY · "}GRID · X赤 / Y緑 / Z青
      </span>
      {status && <div className="preview-message" role={failed ? "alert" : "status"}>{status}</div>}
      <div className="preview-toolbar">
        <span>ドラッグで回転 · スクロールでズーム</span>
        <button type="button" onClick={() => api.current?.reset()}>視点をリセット</button>
      </div>
    </div>
  );
}
