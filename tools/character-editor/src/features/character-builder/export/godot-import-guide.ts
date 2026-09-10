import type { CharacterExportMetadata } from "@/domain/character-export";
import { GODOT_SCALE_RULE } from "@/domain/character-export";

/** Short guide bundled in the zip; the full version lives in docs/godot-import-guide.md. */
export function godotImportGuide(meta: CharacterExportMetadata): string {
  const id = meta.id;
  return `# Godot Import — ${meta.name} (${id})

Files
- ${id}.glb              Final Character Mesh + rig nodes + skinning-free node animation + equipment
- ${id}.png              Palette reference (colours are also baked into the GLB material baseColorFactor)
- ${id}.character.json   Runtime metadata (animation mapping, activeAnimationSet, palette, assets)

## 1. Place the files
Copy \`${id}.glb\` (and \`${id}.character.json\`) into \`res://test/exports/\` (or your own character dir).

## 2. Import settings (Import dock, with ${id}.glb selected)
- Nodes > Apply Root Scale: on, Root Scale: 1.0   (${GODOT_SCALE_RULE})
- Nodes > Root Type: Node3D
- Animation > Import: on, FPS: 30, Trimming: off
- Skins > Use Named Skins: on
- Reimport.

## 3. Keep the pixel look (prompt 11 / 27)
GLB cannot fully carry Godot's texture filter. After import, either:
- Project Settings > Rendering > Textures > Canvas Textures > Default Texture Filter = Nearest, or
- select the imported materials and set Sampling > Filter = Nearest, or
- add an import script that walks materials and sets \`texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\`.
Palette colours are in \`baseColorFactor\`; no shader-side palette swap is needed in v1.

## 4. Animation mapping
Read \`${id}.character.json\`:
- \`activeAnimationSet\` = "${meta.activeAnimationSet}"
- \`animations[activeAnimationSet]\` and \`animations["default"]\` map idle / walk / run / attack to the GLB clip names
  (clip names keep the source spelling, incl. "animation.gread_sword_attack" — normalise via this map, do not rename clips).

## 5. Test scene
\`res://test/character_export_test.tscn\` loads the newest GLB in \`res://test/exports/\` (falls back to
\`res://assets/world_jrpg/explorer_base_1.glb\`). Keys: 1 = idle, 2 = run, 3 = attack.
`;
}
