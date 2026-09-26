"""Build the matched 001/002/003 set through live Blender MCP.

Call build('001'), build('002'), build('003'). Each call creates a new scene,
preserving existing work. Only body/001 supplies a rig. Sources are immutable.
"""
import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

from build_golden_path import create_animations, enum, inspect, write_json

ROOT = Path(__file__).resolve().parents[3]
IDS = ('001', '002', '003')


def source(kind, idx):
    return ROOT / f'assets/characters/tripo/{kind}/{idx}/model.glb'


def import_source(kind, idx):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source(kind, idx)))
    return set(bpy.data.objects) - before


def bounds(mesh):
    points = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    return [Vector(tuple(fn(p[i] for p in points) for i in range(3)))
            for fn in (min, max)]


def transfer_weights(donor, target, rig):
    """Nearest rest-surface barycentric transfer, normalized to four influences."""
    donor.data.calc_loop_triangles()
    verts = [v.co.copy() for v in donor.data.vertices]
    triangles = [tuple(t.vertices) for t in donor.data.loop_triangles]
    tree = BVHTree.FromPolygons(verts, triangles, all_triangles=True)
    groups = {g.index: target.vertex_groups.new(name=g.name) for g in donor.vertex_groups}
    distances = []
    for vertex in target.data.vertices:
        point, _, index, distance = tree.find_nearest(vertex.co)
        distances.append(distance)
        tri = triangles[index]
        bc = barycentric_transform(point, *(verts[i] for i in tri),
                                   Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        weights = {}
        for vi, influence in zip(tri, bc):
            for group in donor.data.vertices[vi].groups:
                weights[group.group] = weights.get(group.group, 0) + max(0, influence) * group.weight
        best = sorted(weights.items(), key=lambda pair: pair[1], reverse=True)[:4]
        total = sum(weight for _, weight in best)
        assert total > 0, ('unweighted vertex', vertex.index)
        for group, weight in best:
            if weight > 0:
                groups[group].add([vertex.index], weight / total, 'REPLACE')
    target.parent = rig
    target.modifiers.new('SharedSkeleton', 'ARMATURE').object = rig
    return dict(method='nearest_triangle_barycentric_top4',
                max_distance=max(distances), mean_distance=sum(distances) / len(distances),
                unweighted_vertices=0)


def build(idx):
    assert idx in IDS
    manifest_path = ROOT / f'assets/characters/tripo/characters/charcter{idx}.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf8'))
    target = ROOT / Path(manifest['output']['glb']).parent
    hashes = {str(source(k, i).relative_to(ROOT)).replace('\\', '/'):
              hashlib.sha256(source(k, i).read_bytes()).hexdigest()
              for k in ('body', 'face') for i in IDS}
    scene = bpy.data.scenes.new('Build_charcter' + idx)
    bpy.context.window.scene = scene
    scene.unit_settings.scale_length = 1
    enum(scene.unit_settings, 'system', 'METRIC')
    scene.render.fps = 30
    imported = import_source('body', '001')
    rig = next(o for o in imported if o.type == 'ARMATURE')
    donor = next(o for o in rig.children if o.type == 'MESH')
    inspection = {'rig_source': inspect([rig, donor])}
    assert len(rig.data.bones) == 65 and 'mixamorig:Head' in rig.data.bones
    for bone in rig.pose.bones:
        bone.custom_shape = None
    rig.name = 'humanoid_v1'
    rig.data.name = 'humanoid_v1'
    rig.data.bones['mixamorig:Head'].name = 'head'
    # Names must remain identical between exports to share animation resources.
    for previous in bpy.data.objects:
        if previous not in imported and previous.name in ('Character', 'humanoid_v1', 'Body', 'Head'):
            assert any(s.name.startswith('Build_charcter') for s in previous.users_scene), (
                'Export name conflicts with existing work; preserve it and use a separate Blender session', previous.name)
            previous.name += '_previous'
    rig.name = 'humanoid_v1'
    body = donor
    transfer = {'method': 'original_tripo_weights'}
    body_scale = 1.0
    if idx != '001':
        body_objects = import_source('body', idx)
        assert len(body_objects) == 1
        body = next(iter(body_objects))
        inspection['body_source'] = inspect(body_objects)
        lo, hi = bounds(body)
        donor_lo, donor_hi = bounds(donor)
        body_scale = (donor_hi.z - donor_lo.z) / (hi.z - lo.z)
        center = Vector(((lo.x + hi.x) / 2, 0, lo.z))
        body.data.transform(Matrix.Scale(body_scale, 4) @ Matrix.Translation(-center) @ body.matrix_world)
        body.matrix_world = Matrix.Identity(4)
        transfer = transfer_weights(donor, body, rig)
        # Preserve the imported donor for inspection, but unlink it from this export scene.
        for collection in list(donor.users_collection):
            collection.objects.unlink(donor)
    body.name = 'Body'
    body.data.materials[0].name = 'Body_' + idx
    face_objects = import_source('face', idx)
    inspection['face_source'] = inspect(face_objects)
    assert len(face_objects) == 1
    face = next(iter(face_objects))
    assert face.type == 'MESH' and not face.vertex_groups
    face.name = 'Head'
    face.data.materials[0].name = 'Head_' + idx
    fit = manifest['fit']
    face.data.transform(Matrix.Translation(Vector(fit['face_position'])) @
                        Matrix.Scale(fit['face_scale'][0], 4) @ face.matrix_world)
    face.matrix_world = Matrix.Identity(4)
    face.parent = rig
    face.vertex_groups.new(name='head').add(list(range(len(face.data.vertices))), 1, 'REPLACE')
    face.modifiers.new('SharedSkeleton', 'ARMATURE').object = rig
    character = bpy.data.objects.new('Character', None)
    scene.collection.objects.link(character)
    rig.parent = character
    character['character_id'] = manifest['character_id']
    character['rig_profile'] = 'humanoid_v1'
    face['hair_integrated'] = True
    # Reuse one action set during a batch; original source has no animation.
    if all(name in bpy.data.actions for name in ('idle', 'walk', 'attack', 'hit')):
        rig.animation_data_create()
        rig.animation_data.action = bpy.data.actions['idle']
    else:
        create_animations(rig)
    scene.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in (character, rig, body, face):
        obj.select_set(True)
    target.mkdir(parents=True, exist_ok=True)
    export_props = bpy.ops.export_scene.gltf.get_rna_type().properties
    assert 'ACTIONS' in [e.identifier for e in export_props['export_animation_mode'].enum_items]
    bpy.ops.export_scene.gltf(filepath=str(ROOT / manifest['output']['glb']), use_selection=True, use_active_scene=True,
                             export_animations=True, export_animation_mode='ACTIONS',
                             export_force_sampling=True, export_frame_range=False, export_extras=True)
    for path, digest in hashes.items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    write_json(target / 'build_report.json', dict(source_hashes=hashes, inspection=inspection,
               rig_source_body_id='001', body_scale=body_scale, weight_transfer=transfer,
               fit=fit, bounds={o.name: [list(p) for p in bounds(o)] for o in (body, face)},
               bones=[b.name for b in rig.data.bones], clips=['idle', 'walk', 'attack', 'hit']))
    work = ROOT / 'artifacts/character_batch'
    work.mkdir(parents=True, exist_ok=True)
    (work / '.gdignore').touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(work / f'charcter{idx}.blend'))
    print('BUILT', manifest['character_id'], transfer)
    return scene


def preview(idx, clip='idle', frame=1, side=False):
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    rig.animation_data.action = bpy.data.actions[clip]
    scene.frame_set(frame)
    camera = scene.camera
    if camera is None:
        camera = bpy.data.objects.new('BatchCamera', bpy.data.cameras.new('BatchCamera'))
        scene.collection.objects.link(camera)
        scene.camera = camera
        light = bpy.data.objects.new('BatchLight', bpy.data.lights.new('BatchLight', 'AREA'))
        scene.collection.objects.link(light)
        light.location = (-1, -3, 4)
        light.rotation_euler = (Vector((0, 0, .7)) - light.location).to_track_quat('-Z', 'Y').to_euler()
        light.data.energy = 300
        light.data.size = 4
    enum(camera.data, 'type', 'ORTHO')
    camera.data.ortho_scale = 1.8
    camera.location = (2.5, -3, 1.2) if side else (0, -3, .78)
    camera.rotation_euler = (Vector((0, 0, .75)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    enum(scene.render.image_settings, 'file_format', 'PNG')
    scene.render.filepath = str(ROOT / f'artifacts/character_batch/{idx}_{clip}_{"side" if side else "front"}.png')
    bpy.ops.render.render(write_still=True)
