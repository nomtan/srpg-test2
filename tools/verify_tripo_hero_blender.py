"""Reopen the saved blend and verify animation shape preservation independently."""
import json
import math
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from prepare_tripo_hero import PERIODS, fingerprint

bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'assets/characters/tripo_hiro/hero_toon.blend'))
scene = bpy.data.scenes['Toon']
bpy.context.window.scene = scene
body = bpy.data.objects['Hero_Body']
rig = bpy.data.objects['Hero_Rig']
original = bpy.data.objects['Original_Body']
assert fingerprint(body.data) == fingerprint(original.data)
assert len(original.vertex_groups) == len(body.vertex_groups) == 25
assert {m.type for m in body.modifiers} == {'ARMATURE'}
assert scene.view_settings.view_transform == 'Standard'
assert len([o for o in scene.objects if o.type == 'LIGHT']) == 1
assert scene.render.engine == 'BLENDER_EEVEE'
material = body.data.materials[0]
ramp = next(n for n in material.node_tree.nodes if n.type == 'VALTORGB').color_ramp
assert ramp.interpolation == 'CONSTANT' and len(ramp.elements) == 3
assert not any(n.type in {'NORMAL_MAP', 'BUMP'} for n in material.node_tree.nodes)
head_ids = [v.index for v in body.data.vertices if v.co.z >= .55]
head_edges = [(e.vertices[0], e.vertices[1]) for e in body.data.edges
              if all(body.data.vertices[i].co.z >= .55 for i in e.vertices)]
head_edges = np.array(head_edges, dtype=np.int32)
rest_positions = np.empty(len(body.data.vertices) * 3, dtype=np.float32)
body.data.vertices.foreach_get('co', rest_positions)
rest_positions = rest_positions.reshape((-1, 3))
rest_lengths = np.linalg.norm(rest_positions[head_edges[:, 0]] - rest_positions[head_edges[:, 1]], axis=1)
hem = [v for v in body.data.vertices if v.co.y > .105 and v.co.z < .14]
assert len(hem) > 0
assert all(body.vertex_groups[g.group].name.startswith('cape') for v in hem for g in v.groups)
report = {'rigid_head_vertices': len(head_ids), 'cape_hem_vertices': len(hem), 'clips': {}}
for clip, period in PERIODS.items():
    rig.animation_data.action = bpy.data.actions[clip]
    worst = 0.0
    for frame in range(1, period + 2):
        scene.frame_set(frame)
        ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = ev.to_mesh()
        positions = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get('co', positions)
        positions = positions.reshape((-1, 3))
        lengths = np.linalg.norm(positions[head_edges[:, 0]] - positions[head_edges[:, 1]], axis=1)
        worst = max(worst, float(np.max(np.abs(lengths - rest_lengths))))
        normals = np.empty(len(mesh.corner_normals) * 3, dtype=np.float32)
        mesh.corner_normals.foreach_get('vector', normals)
        assert np.isfinite(normals).all()
        ev.to_mesh_clear()
    assert worst < 1e-6, (clip, worst)
    report['clips'][clip] = {'max_head_edge_length_error': worst, 'normals_finite': True}
    print('VERIFIED', clip, worst, flush=True)
out = ROOT / 'artifacts/tripo_hero/toon'
(out / 'reopen_validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('REOPEN_VALIDATION', json.dumps(report), flush=True)
if '--render' in sys.argv:
    camera = scene.camera
    for clip, frame, suffix, location in [
        ('run', 16, 'opposite', (1.1, -2.7, 1.35)),
        ('run', 6, 'back', (-1.1, 2.7, 1.20)),
        ('walk', 24, 'opposite', (1.1, -2.7, 1.35)),
    ]:
        rig.animation_data.action = bpy.data.actions[clip]
        scene.frame_set(frame)
        camera.location = location
        camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(out / f'toon_standard_{clip}_{suffix}.png')
        bpy.ops.render.render(write_still=True)
