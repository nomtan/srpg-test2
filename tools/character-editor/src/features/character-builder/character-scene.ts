// Phase 5: assemble the live/bakeable character scene graph from a recipe + the merged library.
// Shared by the Builder preview and the Godot export so what you see is what gets baked.
import * as THREE from "three";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import type { CharacterRecipe } from "@/domain/character-recipe";
import { PALETTE_SLOTS, type PaletteSlot } from "@/domain/constants";
import { EXPORT_ASSET_SLOTS, type ExportAssetSlot } from "@/domain/character-export";
import { SLOT_NODE_NAME, SLOT_SOCKET, clampScale } from "@/domain/builder-recipe";
import { socketNodeName } from "@/features/asset-creator/base-parts";
import type { AssetLibrary, AssetLibraryEntry } from "@/features/asset-library/library";
import { modelUrl, textureUrl } from "@/features/asset-library/library";

export const BASE_MODEL_URL = "/generated-assets/base_body/model.glb";
/** Rig nodes that must survive the round-trip (prompt 23). base_1 is rigid-node animated, no skin. */
export const REQUIRED_RIG_NODES = ["ganmen", "dou", "kahanshi", "hand_right_te", "hand_left_te", "foot_right", "foot_left"] as const;
const HEAD_NODE = "ganmen";

export interface EquipmentPlacement {
  slot: ExportAssetSlot;
  assetId: string;
  nodeName: string;
  socket: string;
  parentNode: string | null;
  parentFound: boolean;
  worldPosition: [number, number, number];
  visible: boolean;
}

export interface BuiltCharacter {
  root: THREE.Group;
  baseRoot: THREE.Object3D;
  clips: THREE.AnimationClip[];
  equipment: EquipmentPlacement[];
  hiddenParts: string[];
  hairPolicy: "hide" | "overlay" | null;
  warnings: string[];
  /** Visible-mesh bounding box in the rest pose (metres). */
  restBox: { min: [number, number, number]; max: [number, number, number]; size: [number, number, number] };
  dispose(): void;
}

function isMesh(o: THREE.Object3D): o is THREE.Mesh {
  return (o as THREE.Mesh).isMesh === true;
}

function eachMaterial(mesh: THREE.Mesh, fn: (m: THREE.Material) => void) {
  const mat = mesh.material;
  for (const m of Array.isArray(mat) ? mat : mat ? [mat] : []) fn(m);
}

function tint(root: THREE.Object3D, hex: string) {
  root.traverse((o) => {
    if (!isMesh(o)) return;
    eachMaterial(o, (m) => {
      const std = m as THREE.MeshStandardMaterial;
      if (std.color) std.color.set(hex);
      std.needsUpdate = true;
    });
  });
}

function pixelSampling(root: THREE.Object3D) {
  root.traverse((o) => {
    if (!isMesh(o)) return;
    eachMaterial(o, (m) => {
      for (const value of Object.values(m)) {
        if (value instanceof THREE.Texture) {
          value.magFilter = THREE.NearestFilter;
          value.minFilter = THREE.NearestFilter;
          value.generateMipmaps = false;
          value.needsUpdate = true;
        }
      }
    });
  });
}

/** Bounding box of visible meshes only (hidden hideParts / hairPolicy meshes excluded). */
function visibleBox(root: THREE.Object3D): THREE.Box3 {
  const box = new THREE.Box3();
  const v = new THREE.Vector3();
  root.updateWorldMatrix(true, true);
  root.traverse((o) => {
    if (!isMesh(o) || !o.visible) return;
    for (let p: THREE.Object3D | null = o; p; p = p.parent) if (!p.visible) return;
    const geo = o.geometry;
    if (!geo.boundingBox) geo.computeBoundingBox();
    const gb = geo.boundingBox!;
    for (const [ix, iy, iz] of CORNERS) {
      v.set(ix ? gb.max.x : gb.min.x, iy ? gb.max.y : gb.min.y, iz ? gb.max.z : gb.min.z);
      box.expandByPoint(o.localToWorld(v.clone()));
    }
  });
  return box;
}
const CORNERS = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0], [1, 0, 1], [0, 1, 1], [1, 1, 1]] as const;

function loadTexture(url: string): Promise<THREE.Texture> {
  return new Promise((resolve, reject) => {
    new THREE.TextureLoader().load(url, (map) => {
      map.colorSpace = THREE.SRGBColorSpace;
      map.flipY = false;
      map.magFilter = THREE.NearestFilter;
      map.minFilter = THREE.NearestFilter;
      map.generateMipmaps = false;
      resolve(map);
    }, undefined, () => reject(new Error(`Texture load failed: ${url}`)));
  });
}

export interface BuildOptions {
  /** Apply palette tint to materials (default true). Set false to inspect raw asset colours. */
  applyPalette?: boolean;
}

export async function buildCharacterScene(
  recipe: CharacterRecipe,
  library: AssetLibrary,
  opts: BuildOptions = {},
): Promise<BuiltCharacter> {
  const warnings: string[] = [];
  const disposables: (() => void)[] = [];
  const loader = new GLTFLoader();

  const baseGltf = await loader.loadAsync(BASE_MODEL_URL);
  const baseRoot = baseGltf.scene;
  baseRoot.name = baseRoot.name || "Base";
  const clips = baseGltf.animations ?? [];

  for (const node of REQUIRED_RIG_NODES) {
    if (!baseRoot.getObjectByName(node)) warnings.push(`Base rig ノードが見つかりません: ${node}`);
  }

  // ---- Body scale (spec section 3.2). Non-uniform on the base root; head is uniform. ----
  const height = clampScale(recipe.body.scale.height);
  const bodyWidth = clampScale(recipe.body.scale.bodyWidth);
  const headScale = clampScale(recipe.body.scale.headScale);
  baseRoot.scale.set(bodyWidth, height, bodyWidth);
  const head = baseRoot.getObjectByName(HEAD_NODE);
  if (head) head.scale.multiplyScalar(headScale);

  const root = new THREE.Group();
  root.name = "CharacterRoot";
  root.add(baseRoot);

  // ---- Palette: base body meshes use the skin slot. ----
  const palette = normalisePalette(recipe.palette);
  if (opts.applyPalette !== false) tint(baseRoot, palette.skin);

  // ---- Equipment ----
  const selected: { slot: ExportAssetSlot; entry: AssetLibraryEntry }[] = [];
  for (const slot of EXPORT_ASSET_SLOTS) {
    const id = recipe.assets[slot];
    if (!id) continue;
    const entry = library.byId[id];
    if (!entry) { warnings.push(`Asset がライブラリにありません: ${slot} = ${id}`); continue; }
    selected.push({ slot, entry });
  }

  const headgearEntry = selected.find((s) => s.slot === "headgear")?.entry;
  const hairPolicy: "hide" | "overlay" | null =
    headgearEntry ? (headgearEntry.metadata.hairPolicy ?? "overlay") : null;

  const equipment: EquipmentPlacement[] = [];
  const hiddenSet = new Set<string>();

  for (const { slot, entry } of selected) {
    const url = modelUrl(entry);
    const socket = SLOT_SOCKET[slot];
    const parentName = socketNodeName(socket);
    const parentNode = parentName ? baseRoot.getObjectByName(parentName) ?? null : null;
    let visible = true;
    if (slot === "hair" && hairPolicy === "hide") visible = false;

    for (const part of entry.metadata.hideParts ?? []) hiddenSet.add(part);

    if (!url) {
      warnings.push(`${slot} (${entry.metadata.id}) に model がありません。メタデータのみで扱います。`);
      equipment.push({ slot, assetId: entry.metadata.id, nodeName: SLOT_NODE_NAME[slot], socket, parentNode: parentName, parentFound: !!parentNode, worldPosition: [0, 0, 0], visible: false });
      continue;
    }

    let assetGltf;
    try {
      assetGltf = await loader.loadAsync(url);
    } catch {
      warnings.push(`${slot} (${entry.metadata.id}) の GLB を読み込めませんでした。`);
      continue;
    }
    const assetRoot = assetGltf.scene;
    assetRoot.name = SLOT_NODE_NAME[slot];
    assetRoot.visible = visible;
    assetRoot.userData.slot = slot;
    assetRoot.userData.assetId = entry.metadata.id;

    const texUrl = textureUrl(entry);
    if (texUrl) {
      try {
        const map = await loadTexture(texUrl);
        disposables.push(() => map.dispose());
        assetRoot.traverse((o) => {
          if (!isMesh(o)) return;
          eachMaterial(o, (m) => {
            const std = m as THREE.MeshStandardMaterial;
            if ("map" in std) { std.map = map; std.needsUpdate = true; }
          });
        });
      } catch {
        warnings.push(`${slot} (${entry.metadata.id}) の texture を読み込めませんでした。`);
      }
    }

    if (opts.applyPalette !== false) {
      const paletteSlot = (entry.metadata.appearance?.paletteSlots ?? [])[0] as PaletteSlot | undefined;
      if (paletteSlot && PALETTE_SLOTS.includes(paletteSlot)) tint(assetRoot, palette[paletteSlot]);
    }

    (parentNode ?? baseRoot).add(assetRoot);
    if (!parentNode) warnings.push(`Socket 親ノード (${parentName ?? socket}) が見つかりません。CharacterRoot 直下に取り付けました: ${slot}`);

    assetRoot.updateWorldMatrix(true, true);
    const wp = assetRoot.getWorldPosition(new THREE.Vector3());
    equipment.push({
      slot, assetId: entry.metadata.id, nodeName: assetRoot.name, socket,
      parentNode: parentName, parentFound: !!parentNode,
      worldPosition: [wp.x, wp.y, wp.z], visible,
    });
  }

  // ---- hideParts / hairPolicy visibility bake (spec sections 9.1 / 10). ----
  const actualHidden: string[] = [];
  baseRoot.traverse((o) => {
    if (!isMesh(o) || !o.name) return;
    if (hiddenSet.has(o.name)) { o.visible = false; if (!actualHidden.includes(o.name)) actualHidden.push(o.name); }
  });
  for (const part of hiddenSet) if (!actualHidden.includes(part)) warnings.push(`hideParts 対象が Base に見つかりません: ${part}`);

  pixelSampling(root);

  root.updateWorldMatrix(true, true);
  const box = visibleBox(root);
  const size = box.getSize(new THREE.Vector3());
  const restBox = {
    min: box.min.toArray() as [number, number, number],
    max: box.max.toArray() as [number, number, number],
    size: size.toArray() as [number, number, number],
  };

  return {
    root, baseRoot, clips, equipment,
    hiddenParts: actualHidden, hairPolicy, warnings, restBox,
    dispose() {
      for (const d of disposables) d();
      root.traverse((o) => {
        if (isMesh(o)) {
          o.geometry?.dispose();
          eachMaterial(o, (m) => {
            for (const value of Object.values(m)) if (value instanceof THREE.Texture) value.dispose();
            m.dispose();
          });
        }
      });
    },
  };
}

export function normalisePalette(palette: Record<string, string>): Record<PaletteSlot, string> {
  const out = {} as Record<PaletteSlot, string>;
  for (const slot of PALETTE_SLOTS) out[slot] = (palette[slot] ?? "#808080").toLowerCase();
  return out;
}
