import bpy
import json
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[3]
for face_id in ('001', '002'):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(root / f'assets/characters/tripo/face/{face_id}/model.glb'))
    mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
    bpy.context.view_layer.update()
    world = mesh.matrix_world
    vertices = [world @ v.co for v in mesh.data.vertices]
    lo = [min(v[i] for v in vertices) for i in range(3)]
    hi = [max(v[i] for v in vertices) for i in range(3)]
    print('FACE', face_id, 'BOUNDS', lo, hi)
    # Source GLB front is negative Y in Blender coordinates.
    areas = {}
    for label, height in [('brow', .70), ('eye', .60), ('mouth', .36)]:
        samples = []
        for polygon in mesh.data.polygons:
            center = world @ polygon.center
            if abs(center.x) > .22 or abs((center.z - lo[2]) / (hi[2] - lo[2]) - height) > .045:
                continue
            if center.y > (lo[1] + hi[1]) * .5:
                continue
            for loop_id in polygon.loop_indices:
                uv = mesh.data.uv_layers.active.data[loop_id].uv
                samples.append([round(uv.x, 4), round(uv.y, 4)])
        areas[label] = samples
    out = root / f'artifacts/golden_path/face_{face_id}_uv_samples.json'
    out.write_text(json.dumps(areas), encoding='utf8')
    for x, z in [(-.16,.58),(.16,.58),(-.16,.68),(.16,.68),(0,.36)]:
        hit, location, normal, face_index = mesh.ray_cast(Vector((x,-2,z)), Vector((0,1,0)))
        if hit:
            poly = mesh.data.polygons[face_index]
            print('RAY',face_id,x,z,'xyz',tuple(round(v,3) for v in location),'uv', [tuple(round(t,3) for t in mesh.data.uv_layers.active.data[l].uv) for l in poly.loop_indices])
