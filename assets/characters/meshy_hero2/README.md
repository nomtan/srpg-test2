# Meshy Hero 2

- `hero2.blend`: editable 26-bone skin and three Actions, created with Blender MCP / Blender 5.1.2. Switch the scene selector between `Original` and `Toon` to compare materials.
- `hero2.glb`: Godot asset with the original 7,242-vertex surface, unchanged UVs and byte-identical 4K Base Color. A separate thin skinned hull supplies the outline. glTF splits vertices along flat normals, so its vertex count is larger than the Blender source.
- `idle`: 2 seconds; `walk`: 1 second; `run`: 20/30 seconds. In-place cycles at 30 fps with matching endpoint keys.
- Four cape bones provide secondary motion. Shoulder, neck, knee and cape placement are fitted to hero2. Kneecap weights preserve ground clearance during running.
- All vertices have normalized weights, at most four influences each. Blender front: -Y; GLB front: +X; sole origin: Y=0; rest height: 2.2 units.

`samples/JRPGWorldSample.tscn` selects this GLB as `player_model`. The actor
blends idle/walk/run and retains stride phase when Shift changes the gait.
`hero2.blend.import` skips direct Blender import; Godot uses the prepared GLB.
Keep `animation/remove_immutable_tracks=false` to reset all bones on stopping.

## Toon appearance

`Toon` uses Eevee, Standard / None, exposure 0 and gamma 1. A single white sun
and weak neutral world illuminate Diffuse BSDF → Shader to RGB → Constant
ColorRamp. The three neutral bands (0.68 / 0.84 / 1.0) multiply the untouched
Base Color before Emission → Material Output. No Normal Map, metallic or
specular response is used. Painted shading already in the texture is retained.

Hair, armor, clothes and cape use flat shading; only the face/ear region uses
smooth shading (824 of 14,528 faces). No subdivision or shape edits are applied.
The outline is a separate inverted hull, expanded 0.003 Blender units and
weighted to the same rig. The original surface, UVs, weights and animation keys
are unchanged. Original materials, normals and all three packed PBR textures
remain in `Original`. Standard was selected after rendering the same Toon scene
with both AgX and Standard.

Shader to RGB cannot be represented in glTF. The GLB therefore contains a
portable matte fallback (Metallic 0, Roughness 1, specular level 0, no normal
texture). `hero2_import.gd`, configured in `hero2.glb.import`, assigns the
equivalent three-band Godot shader and outline material during import. Keep
these scripts/shaders with the GLB to preserve the stepped look in Godot.
This asset disables automatic mesh LODs and vertex compression so the thin hull
and flat surface retain their spacing; its shader applies a small depth offset
to keep outlines behind the painted surface at creases.
The Godot shader uses scene light direction/shadows with neutral bands, preventing
colored lights from washing out the painted palette. Another engine needs its
own toon shader; the GLB alone does not carry Eevee's node graph.

## Editing and verification

Untouched pre-rig backup: `artifacts/meshy_hero2/hero2_before_rig.blend`.
Pre-Toon disk backups and live Blender snapshot: `artifacts/meshy_hero2/toon/`.
Rebuild the current look from that rigged snapshot:
`blender --background --factory-startup --python tools/toon_meshy_hero2.py`.
The older `tools/rig_meshy_hero2.py` rebuilds only the rig and would replace the Toon setup.
Verify: `godot --headless --path . --script scripts/world_jrpg/verify_meshy_hero2.gd`.
Render integration previews by adding `-- --capture` without `--headless`.
Hashes, comparison renders and sample captures: `artifacts/meshy_hero2/toon/`.
