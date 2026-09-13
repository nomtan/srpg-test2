// Per-body-part colouring for the base character.
//
// The base GLB ships ONE material shared by all 20 body meshes (see build-base-model.mjs), so
// writing a colour straight onto a mesh's material repaints the whole body. Overridden parts get
// their own cloned material instead; everything else keeps the shared one and follows the global
// `skin` palette slot.
//
// Part names come from the base model, where `ashikubi` and `ashisaki` each appear twice (left and
// right). Keying by name therefore colours both sides at once — the same limitation `hideParts`
// has, and the reason the Builder marks those rows "左右同時".
import * as THREE from "three";

export interface BodyTintResult {
  /** Part names that actually matched a mesh and took an override. */
  applied: string[];
  /** Materials cloned for this tint; the caller owns disposal. */
  cloned: THREE.Material[];
}

export function tintBodyParts(
  root: THREE.Object3D,
  skin: string,
  partColors: Record<string, string> = {},
): BodyTintResult {
  const cloneCache = new Map<string, THREE.Material>();
  const applied: string[] = [];

  root.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (!mesh.isMesh || Array.isArray(mesh.material)) return;
    const base = mesh.material as THREE.MeshStandardMaterial;
    // A textured material carries its own colours; tinting it would only darken the texture.
    if (!base || base.map) return;

    const override = mesh.name ? partColors[mesh.name] : undefined;
    if (override && !applied.includes(mesh.name)) applied.push(mesh.name);

    const hex = override ?? skin;
    if (hex === skin) {
      // Fallback parts stay on the shared material, which carries the skin colour.
      base.color?.set(skin);
      base.needsUpdate = true;
      return;
    }
    let material = cloneCache.get(hex);
    if (!material) {
      material = base.clone();
      (material as THREE.MeshStandardMaterial).color.set(hex);
      material.needsUpdate = true;
      cloneCache.set(hex, material);
    }
    mesh.material = material;
  });

  return { applied, cloned: [...cloneCache.values()] };
}
