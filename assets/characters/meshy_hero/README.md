# Meshy Hero

- `hero.blend`: editable 26-bone skin and three Actions, created with Blender MCP / Blender 5.1.2.
- `hero.glb`: Godot asset, packed color / metallic-roughness / normal textures, four skin influences per vertex.
- `idle`: 2 seconds; `walk`: 1 second; `run`: 20/30 seconds. All are in-place cycles at 30 fps with matching endpoint keys.
- Four cape bones provide secondary motion. Hands, head, armor and original UVs are retained.
- Blender front: -Y. GLB front: +X; soles at Y=0; rest height: 2.2 units.

The sample scene selects this GLB as `player_model`; its existing actor controller
blends idle/walk/run and keeps stride phase when Shift changes the gait.
`hero.blend.import` skips direct Blender import so Godot uses the prepared GLB.
Keep `animation/remove_immutable_tracks=false` to reset all bones when stopping.

Untouched source backup: `artifacts/meshy_hero/hero_before_rig.blend`.
Rebuild with `blender --background --factory-startup --python tools/rig_meshy_hero.py`.
Verify with `godot --headless --path . --script scripts/world_jrpg/verify_meshy_hero.gd`.
Rendered sample images and skin/loop validation: `artifacts/meshy_hero/`.
