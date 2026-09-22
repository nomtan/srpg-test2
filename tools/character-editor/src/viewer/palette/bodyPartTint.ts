// Per-body-part colouring for the base character.
//
// The base GLB ships ONE material shared by all 20 body meshes (see build-base-model.mjs), so
// writing a colour straight onto a mesh's material repaints the whole body. Overridden parts get
// their own cloned material instead; everything else keeps the shared one and follows the global
// `skin` palette slot.
//
// Parts are resolved through `resolvePart`, not by node name: GLTFLoader uniquifies duplicate node
// names, so the base model's two `ashisaki` / `ashikubi` meshes load as `ashisaki` + `ashisaki_1`,
// and the torso mesh collides with the group of the same name and loads as `dou_1`. The caller
// passes a resolver that reads the Blockbench element UUID out of `userData`.
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
  resolvePart: (object: THREE.Object3D) => string | null = (o) => o.name || null,
): BodyTintResult {
  const cloneCache = new Map<string, THREE.Material>();
  const applied: string[] = [];

  root.traverse((object) => {
    const mesh = object as THREE.Mesh;
    if (!mesh.isMesh || Array.isArray(mesh.material)) return;
    const base = mesh.material as THREE.MeshStandardMaterial;
    // A textured material carries its own colours; tinting it would only darken the texture.
    if (!base || base.map) return;

    const part = resolvePart(mesh);
    const override = part ? partColors[part] : undefined;
    if (override && part && !applied.includes(part)) applied.push(part);

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
