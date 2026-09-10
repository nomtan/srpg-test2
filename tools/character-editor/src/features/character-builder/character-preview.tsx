"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import type { CharacterRecipe } from "@/domain/character-recipe";
import type { AssetLibrary } from "@/features/asset-library/library";
import { AnimationController } from "@/viewer/animation/AnimationController";
import { resolveAnimation } from "@/viewer/animation/animationMapping";
import { buildCharacterScene, type BuiltCharacter } from "./character-scene";

export interface CharacterPreviewProps {
  recipe: CharacterRecipe;
  library: AssetLibrary;
  animationSet: string;
  animationRole: string;
  playing: boolean;
  speed: number;
  loop: boolean;
  captureSignal: number;
  onThumbnail?: (dataUrl: string) => void;
  onWarnings?: (warnings: string[]) => void;
  onRestSize?: (size: [number, number, number]) => void;
}

export function CharacterPreview(props: CharacterPreviewProps) {
  const host = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState("キャラクターを組み立て中…");
  const [failed, setFailed] = useState(false);

  const latest = useRef(props);
  useEffect(() => { latest.current = props; });

  const api = useRef<{
    renderer: THREE.WebGLRenderer;
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    thumbCam: THREE.PerspectiveCamera;
    controls: OrbitControls;
    built: BuiltCharacter | null;
    anim: AnimationController | null;
    helpers: THREE.Object3D[];
    reset: () => void;
  } | null>(null);
  const captureRef = useRef(props.captureSignal);

  function configureAnimation() {
    const state = api.current;
    const p = latest.current;
    if (!state?.anim) return;
    const resolved = resolveAnimation(p.animationSet, p.animationRole, state.built?.clips.map((c) => c.name) ?? []);
    state.anim.configure({
      clip: resolved.name,
      playing: p.playing && !!resolved.name,
      speed: p.speed,
      loop: p.loop,
      revision: 0,
    });
    if (resolved.warnings.length && p.playing) setStatus(resolved.warnings.join(" / "));
    else setStatus("");
  }

  // Scene lifecycle -------------------------------------------------------
  useEffect(() => {
    const container = host.current!;
    let alive = true;

    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    } catch {
      queueMicrotask(() => { if (alive) { setFailed(true); setStatus("3D Preview を開始できません。WebGL 対応ブラウザが必要です。"); } });
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
      camera.position.copy(target).add(new THREE.Vector3(1, 0.5, 1.6).normalize().multiplyScalar(distance));
      camera.near = Math.max(radius / 100, 0.001);
      camera.far = distance + radius * 100;
      camera.updateProjectionMatrix();
      controls.target.copy(target);
      controls.minDistance = radius * 0.5;
      controls.maxDistance = distance * 5;
      controls.update();
      thumbCam.position.copy(target).add(new THREE.Vector3(0.7, 0.35, 1).normalize().multiplyScalar(distance * 0.95));
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
      reset();
    });
    observer.observe(container);
    const onLost = (e: Event) => { e.preventDefault(); setFailed(true); setStatus("WebGL 接続が失われました。ページを再読み込みしてください。"); };
    renderer.domElement.addEventListener("webglcontextlost", onLost);

    const state = { renderer, scene, camera, thumbCam, controls, built: null as BuiltCharacter | null, anim: null as AnimationController | null, helpers, reset };
    api.current = state;

    buildCharacterScene(latest.current.recipe, latest.current.library)
      .then((built) => {
        if (!alive) { built.dispose(); return; }
        state.built = built;
        scene.add(built.root);
        state.anim = built.clips.length ? new AnimationController(built.baseRoot, built.clips) : null;

        built.root.updateWorldMatrix(true, true);
        const box = new THREE.Box3().setFromObject(built.root);
        box.getCenter(target);
        radius = Math.max(box.getBoundingSphere(new THREE.Sphere()).radius, 0.01);
        const gridSpan = Math.max(2, Math.ceil(radius * 4));
        const grid = new THREE.GridHelper(gridSpan, gridSpan, 0x466074, 0x293c4b);
        grid.position.set(target.x, box.min.y - 0.002, target.z);
        const axes = new THREE.AxesHelper(Math.max(radius * 0.5, 0.2));
        scene.add(grid, axes);
        helpers.push(grid, axes);

        reset();
        configureAnimation();
        latest.current.onWarnings?.(built.warnings);
        latest.current.onRestSize?.(built.restBox.size);
        if (!built.warnings.length) setStatus("");
        else setStatus(`警告 ${built.warnings.length} 件（詳細は下部）`);
      })
      .catch((e) => {
        if (!alive) return;
        setFailed(true);
        setStatus(e instanceof Error ? `組み立てに失敗しました: ${e.message}` : "組み立てに失敗しました。");
      });

    const clock = new THREE.Clock();
    renderer.setAnimationLoop(() => {
      state.anim?.update(clock.getDelta());
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
      if (state.built) { scene.remove(state.built.root); state.built.dispose(); }
      for (const h of helpers) { scene.remove(h); (h as THREE.GridHelper).geometry?.dispose?.(); }
      renderer.dispose();
      renderer.domElement.remove();
      api.current = null;
    };
  }, []);

  useEffect(() => { configureAnimation(); }, [props.animationSet, props.animationRole, props.playing, props.speed, props.loop]);

  // Thumbnail capture --------------------------------------------------------
  useEffect(() => {
    if (props.captureSignal === captureRef.current) return;
    captureRef.current = props.captureSignal;
    const state = api.current;
    if (!state || props.captureSignal < 0) return;
    const { renderer, scene, thumbCam, helpers } = state;
    const size = renderer.getSize(new THREE.Vector2());
    const vis = helpers.map((h) => h.visible);
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
    helpers.forEach((h, i) => (h.visible = vis[i]));
    props.onThumbnail?.(dataUrl);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.captureSignal]);

  return (
    <div className="preview">
      <div ref={host} className="viewport" />
      <span className="preview-tag">CHARACTER · PALETTE / SCALE / EQUIP / ANIM · X赤 / Y緑 / Z青</span>
      {status && <div className="preview-message" role={failed ? "alert" : "status"}>{status}</div>}
      <div className="preview-toolbar">
        <span>ドラッグで回転 · スクロールでズーム</span>
        <button type="button" onClick={() => api.current?.reset()}>視点をリセット</button>
      </div>
    </div>
  );
}
