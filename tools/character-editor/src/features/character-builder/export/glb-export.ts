// GLB bake (spec sections 5-7 / prompts 5-7): serialise the assembled scene graph, keeping the
// rig node hierarchy, semantic equipment node names, socket transforms and animation clips.
// onlyVisible drops hideParts / hairPolicy-hidden / unselected meshes (prompt 8).
import * as THREE from "three";
import { GLTFExporter, type GLTFExporterOptions } from "three/addons/exporters/GLTFExporter.js";

export interface GlbBakeResult {
  buffer: ArrayBuffer;
  blob: Blob;
}

export async function exportCharacterGlb(root: THREE.Object3D, clips: THREE.AnimationClip[]): Promise<GlbBakeResult> {
  root.updateWorldMatrix(true, true);
  const exporter = new GLTFExporter();
  const options: GLTFExporterOptions = {
    binary: true,
    onlyVisible: true,
    animations: clips,
    includeCustomExtensions: false,
    embedImages: true,
    trs: true,
  };
  const output = await new Promise<ArrayBuffer | { [k: string]: unknown }>((resolve, reject) => {
    exporter.parse(root, resolve, reject, options);
  });
  if (!(output instanceof ArrayBuffer)) throw new Error("GLTFExporter がバイナリ GLB を返しませんでした。");
  return { buffer: output, blob: new Blob([output], { type: "model/gltf-binary" }) };
}
