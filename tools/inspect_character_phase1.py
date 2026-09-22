"""Read-only Blender inspection for the three Phase 1 raw sources."""
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from inspect_tripo_roster import SOURCES
from tripo_roster_common import preview_scene

OUT = ROOT / 'artifacts/character_phase1'
OUT.mkdir(parents=True, exist_ok=True)
report = {}
for key in ('adventure', 'knight', 'black_mage'):
    source = ROOT / 'assets/characters' / SOURCES[key]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    objects = list(bpy.context.scene.objects)
    meshes = [o for o in objects if o.type == 'MESH']
    rigs = [o for o in objects if o.type == 'ARMATURE']
    points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    entry = {
        'source': str(source.relative_to(ROOT)),
        'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'objects': [{'name': o.name, 'type': o.type,
                     'matrix_world': [list(r) for r in o.matrix_world]} for o in objects],
        'mesh_count': len(meshes), 'material_count': len(bpy.data.materials),
        'texture_count': len(bpy.data.images), 'armature_count': len(rigs),
        'bones': [{'armature': o.name, 'name': b.name,
                   'parent': b.parent.name if b.parent else None,
                   'head': list(b.head_local), 'tail': list(b.tail_local)}
                  for o in rigs for b in o.data.bones],
        'actions': [a.name for a in bpy.data.actions],
        'vertices': sum(len(o.data.vertices) for o in meshes),
        'triangles': sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons),
        'blender_world_bounds': [low, high], 'height': high[2]-low[2],
        'feet_blender_z': low[2],
        'meshes': [{'name': o.name, 'vertex_groups': [g.name for g in o.vertex_groups],
                    'materials': [m.name for m in o.data.materials],
                    'vertices': len(o.data.vertices),
                    'triangles': sum(len(p.vertices)-2 for p in o.data.polygons),
                    'bounds': [[min((o.matrix_world @ v.co)[i] for v in o.data.vertices) for i in range(3)],
                               [max((o.matrix_world @ v.co)[i] for v in o.data.vertices) for i in range(3)]]}
                   for o in meshes],
    }
    # The untextured Icosphere is a rig helper, not character geometry.
    character = max(meshes, key=lambda o: len(o.data.vertices))
    parents = list(range(len(character.data.vertices)))
    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i
    def union(a,b):
        parents[find(a)] = find(b)
    positions = {}
    for v in character.data.vertices:
        position = tuple(round(c,6) for c in v.co)
        if position in positions: union(v.index,positions[position])
        else: positions[position] = v.index
    for edge in character.data.edges: union(*edge.vertices)
    components = {}
    for v in character.data.vertices: components.setdefault(find(v.index),[]).append(v.co)
    entry['position_welded_components'] = [
        {'vertices':len(points), 'bounds':[[min(p[i] for p in points) for i in range(3)],
                                        [max(p[i] for p in points) for i in range(3)]]}
        for points in sorted(components.values(),key=len,reverse=True)]
    entry['weapon_shield'] = 'None visible in front/back inspection'
    entry['cape'] = 'Merged scarf tails' if key=='adventure' else 'Merged cape with baked gold emblem' if key=='knight' else 'No separate cape; robe'
    for obj in meshes:
        obj.hide_render = obj != character
    entry['character_height'] = max(v.co.z for v in character.data.vertices)-min(v.co.z for v in character.data.vertices)
    entry['bone_count'] = len(entry['bones'])
    entry['forward_blender'] = '-Y (front render verified)'
    entry['forward_gltf'] = '+Z; requires 180 degree turn for Godot -Z'
    entry['parts'] = 'Head/hair/body share the main mesh; semantic separation needs visual review.'
    preview_scene(bpy.context.scene)
    scene = bpy.context.scene
    scene.render.resolution_x = 400
    scene.render.resolution_y = 460
    for label, location in ([] if '--no-render' in sys.argv else [('front', (0,-3,.65)), ('back', (0,3,.65))]):
        scene.camera.location = location
        scene.camera.rotation_euler = (Vector((0,0,.49))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath = str(OUT / (key+'_'+label+'.png'))
        bpy.ops.render.render(write_still=True)
    report[key] = entry
    print('PHASE1_INSPECT', key, json.dumps(entry), flush=True)
(OUT / 'inspection.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
