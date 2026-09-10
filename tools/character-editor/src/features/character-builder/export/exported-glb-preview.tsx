"use client";

// Re-import the baked GLB into a fresh Three.js scene and play it back (spec section 22): this is
// the visual half of round-trip validation — scale, weapon position, textures, animation.
import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

const IDLE_HINTS = ["idle", "walk_mcp_test", "run"];

export function ExportedGlbPreview({ url }: { url: string }) {
  const host = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState("Exported GLB を読み込み中…");
  const [failed, setFailed] = useState(false);
  const [clips, setClips] = useState<string[]>([]);
  const [current, setCurrent] = useState<string>("");
  const ctrl = useRef<{ mixer: THREE.AnimationMixer | null; animations: THREE.AnimationClip[]; play: (name: string) => void; reset: () => void } | null>(null);

  useEffect(() => {
    const container = host.current!;
    let alive = true;
    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ antialias: true }); }
    catch { queueMicrotask(() => { if (alive) { setFailed(true); setStatus("WebGL 対応ブラウザが必要です。"); } }); return () => { alive = false; }; }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0x101a24);
    container.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(40, 1, 0.01, 1000);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    scene.add(new THREE.HemisphereLight(0xd5edff, 0x746653, 2.4));
    const dir = new THREE.DirectionalLight(0xffffff, 3);
    dir.position.set(3, 5, 4);
    scene.add(dir);

    let radius = 1;
    const target = new THREE.Vector3();
    const reset = () => {
      const fov = THREE.MathUtils.degToRad(camera.fov);
      const limiting = Math.min(fov, 2 * Math.atan(Math.tan(fov / 2) * camera.aspect));
      const distance = (radius / Math.sin(limiting / 2)) * 1.2;
      camera.position.copy(target).add(new THREE.Vector3(1, 0.5, 1.6).normalize().multiplyScalar(distance));
      camera.near = Math.max(radius / 100, 0.001);
      camera.far = distance + radius * 100;
      camera.updateProjectionMatrix();
      controls.target.copy(target);
      controls.update();
    };
    const observer = new ResizeObserver(() => {
      const { width, height } = container.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      reset();
    });
    observer.observe(container);

    let mixer: THREE.AnimationMixer | null = null;
    new GLTFLoader().load(url, (gltf) => {
      if (!alive) return;
      scene.add(gltf.scene);
      gltf.scene.updateWorldMatrix(true, true);
      const box = new THREE.Box3().setFromObject(gltf.scene);
      box.getCenter(target);
      const size = box.getSize(new THREE.Vector3());
      radius = Math.max(box.getBoundingSphere(new THREE.Sphere()).radius, 0.01);
      const grid = new THREE.GridHelper(Math.max(2, Math.ceil(radius * 4)), Math.max(2, Math.ceil(radius * 4)), 0x466074, 0x293c4b);
      grid.position.set(target.x, box.min.y - 0.002, target.z);
      scene.add(grid);

      gltf.scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        if (!mesh.isMesh) return;
        for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
          for (const v of Object.values(m ?? {})) {
            if (v instanceof THREE.Texture) { v.magFilter = THREE.NearestFilter; v.minFilter = THREE.NearestFilter; v.generateMipmaps = false; v.needsUpdate = true; }
          }
        }
      });

      const names = gltf.animations.map((c) => c.name);
      setClips(names);
      if (gltf.animations.length) {
        mixer = new THREE.AnimationMixer(gltf.scene);
        const pick = names.find((n) => IDLE_HINTS.some((h) => n.includes(h))) ?? names[0];
        const play = (name: string) => {
          if (!mixer) return;
          const clip = gltf.animations.find((c) => c.name === name);
          if (!clip) return;
          mixer.stopAllAction();
          mixer.clipAction(clip).reset().play();
          setCurrent(name);
        };
        ctrl.current = { mixer, animations: gltf.animations, play, reset };
        play(pick);
      }
      reset();
      setStatus(`Mesh OK · Y=${size.y.toFixed(3)} m · ${names.length} clips`);
    }, undefined, () => { if (alive) { setFailed(true); setStatus("Exported GLB を再読み込みできませんでした。"); } });

    const clock = new THREE.Clock();
    renderer.setAnimationLoop(() => { mixer?.update(clock.getDelta()); controls.update(); renderer.render(scene, camera); });

    return () => {
      alive = false;
      observer.disconnect();
      renderer.setAnimationLoop(null);
      mixer?.stopAllAction();
      controls.dispose();
      scene.traverse((o) => {
        const mesh = o as THREE.Mesh;
        if (mesh.isMesh) { mesh.geometry?.dispose(); for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) m?.dispose(); }
      });
      renderer.dispose();
      renderer.domElement.remove();
      ctrl.current = null;
    };
  }, [url]);

  return (
    <div className="preview export-reimport">
      <div ref={host} className="viewport" />
      <span className="preview-tag">EXPORTED GLB · RE-IMPORT</span>
      {status && <div className="preview-message" role={failed ? "alert" : "status"}>{status}</div>}
      <div className="preview-toolbar">
        <span>{clips.length ? `clip: ${current || "—"}` : "animation なし"}</span>
        <span className="clip-buttons">
          {clips.map((name) => (
            <button key={name} type="button" className={name === current ? "on mini" : "mini"} onClick={() => ctrl.current?.play(name)}>{name.replace("animation.", "")}</button>
          ))}
        </span>
      </div>
    </div>
  );
}
