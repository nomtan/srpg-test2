"""Render the untouched hero geometry before authoring its rig."""
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from prepare_tripo_knight import make_materials, preview_scene

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/characters/tripo_hiro/hero.glb'))
scene = bpy.context.scene
obj = next(o for o in scene.objects if o.type == 'MESH')
print('HERO_INSPECT', json.dumps({'location': list(obj.location), 'rotation': list(obj.rotation_euler),
    'scale': list(obj.scale), 'bounds': [list(v) for v in obj.bound_box],
    'vertices': len(obj.data.vertices), 'faces': len(obj.data.polygons)}), flush=True)
base = next(n for n in obj.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE').image
toon, _, _ = make_materials(base)
obj.data.materials[0] = toon
_, camera = preview_scene(scene)
scene.render.resolution_x = 600
scene.render.resolution_y = 700
out = ROOT / 'artifacts/tripo_hero'
out.mkdir(parents=True, exist_ok=True)
for name, position in [('front', (0, -3, .50)), ('side', (3, 0, .50)), ('back', (0, 3, .50))]:
    camera.location = position
    camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(out / ('source_' + name + '.png'))
    bpy.ops.render.render(write_still=True)
