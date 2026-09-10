import { NearestFilter, Texture, type Object3D, type Mesh } from "three";

export function usePixelSampling(root: Object3D) {
  root.traverse((node) => {
    const mesh = node as Mesh;
    if (!mesh.isMesh) return;
    for (const material of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
      for (const value of Object.values(material)) if (value instanceof Texture) {
        value.magFilter = NearestFilter;
        value.minFilter = NearestFilter;
        value.generateMipmaps = false;
        value.needsUpdate = true;
      }
    }
  });
}
