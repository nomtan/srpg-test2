"""Run inside Blender through Blender MCP; never as a background Blender job.

The measured source contract is intentionally specific to Body 001. Source GLBs
are read-only. build_body(), finish_face('001'), then finish_face('002') retain
the very same body, armature and actions between exports.
"""
import bpy
import hashlib
import json
import math
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/characters/generated'
FITS = {'001': (.52, (.0019, -.0589, .89)),
        '002': (.60, (.0019, -.0589, .89))}


def enum(owner, prop, value):
    values = [e.identifier for e in owner.bl_rna.properties[prop].enum_items]
    assert value in values, (prop, value, values)
    setattr(owner, prop, value)


def inspect(objects):
    result = []
    for o in objects:
        row = dict(name=o.name, type=o.type,
                   parent=o.parent.name if o.parent else None,
                   matrix=[list(r) for r in o.matrix_world])
        if o.type == 'MESH':
            points = [o.matrix_world @ v.co for v in o.data.vertices]
            row.update(vertices=len(points), polygons=len(o.data.polygons),
                       bounds=[[min(p[i] for p in points) for i in range(3)],
                               [max(p[i] for p in points) for i in range(3)]],
                       materials=[m.name for m in o.data.materials],
                       images=[dict(name=n.image.name, size=list(n.image.size))
                               for m in o.data.materials for n in m.node_tree.nodes
                               if n.type == 'TEX_IMAGE' and n.image],
                       groups=[g.name for g in o.vertex_groups])
        if o.type == 'ARMATURE':
            row['bones'] = [dict(name=b.name, parent=b.parent.name if b.parent else None,
                                 head=list(b.head_local), tail=list(b.tail_local))
                            for b in o.data.bones]
        result.append(row)
    return result


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def build_body():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    hashes = {f'assets/characters/tripo/{kind}/{idx}/model.glb':
              hashlib.sha256((ROOT / f'assets/characters/tripo/{kind}/{idx}/model.glb').read_bytes()).hexdigest()
              for kind, idx in [('body', '001'), ('face', '001'), ('face', '002')]}
    write_json(OUT / 'golden_path_001/source_hashes.json', hashes)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/characters/tripo/body/001/model.glb'))
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    body = next(o for o in rig.children if o.type == 'MESH')
    write_json(OUT / 'golden_path_001/body_source_inspection.json', inspect([rig, body]))
    # glTF importer custom bone display objects are not source geometry.
    shapes = {p.custom_shape for p in rig.pose.bones if p.custom_shape}
    for p in rig.pose.bones:
        p.custom_shape = None
    for shape in shapes:
        bpy.data.objects.remove(shape, do_unlink=True)
    assert len(rig.data.bones) == 65
    rig.name = 'humanoid_v1'
    rig.data.name = 'humanoid_v1'
    rig.data.bones['mixamorig:Head'].name = 'head'
    body.name = 'Body'
    body.data.materials[0].name = 'Body'
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 1.0
    enum(scene.unit_settings, 'system', 'METRIC')
    scene.render.fps = 30
    character = bpy.data.objects.new('Character', None)
    scene.collection.objects.link(character)
    rig.parent = character
    character['rig_profile'] = 'humanoid_v1'
    create_animations(rig)


def create_animations(rig):
    """Shared in-place compatibility clips for the inspected 65-bone Tripo rig."""
    scene = bpy.context.scene
    rig.animation_data_create()
    # A small in-place motion set for compatibility, not production combat art.
    for clip, frames in [('idle', 60), ('walk', 30), ('attack', 30), ('hit', 24)]:
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame in range(1, frames + 2):
            t = (frame - 1) / frames
            wave = math.sin(2 * math.pi * t)
            pulse = math.sin(math.pi * t) ** 2
            rotations = {'mixamorig:LeftArm': (0, .75, 0),
                         'mixamorig:RightArm': (0, -.75, 0),
                         'mixamorig:Spine2': (.025 * wave, 0, 0),
                         'head': (.015 * wave, 0, .025 * wave)}
            if clip == 'walk':
                rotations.update({'mixamorig:LeftUpLeg': (.25 * wave, 0, 0),
                                  'mixamorig:RightUpLeg': (-.25 * wave, 0, 0),
                                  'mixamorig:LeftLeg': (-.18 * max(0, wave), 0, 0),
                                  'mixamorig:RightLeg': (-.18 * max(0, -wave), 0, 0),
                                  'mixamorig:LeftArm': (-.18 * wave, .75, 0),
                                  'mixamorig:RightArm': (.18 * wave, -.75, 0)})
            elif clip == 'attack':
                rotations.update({'mixamorig:RightArm': (-.9 * pulse, -.75 + .35 * pulse, 0),
                                  'mixamorig:RightForeArm': (-.4 * pulse, 0, 0),
                                  'mixamorig:Spine2': (.10 * pulse, 0, -.15 * pulse),
                                  'head': (-.04 * pulse, 0, .07 * pulse)})
            elif clip == 'hit':
                rotations.update({'mixamorig:Spine2': (-.18 * pulse, 0, 0),
                                  'head': (-.12 * pulse, 0, .06 * pulse)})
            for p in rig.pose.bones:
                enum(p, 'rotation_mode', 'QUATERNION')
                p.location = (0, 0, 0)
                p.scale = (1, 1, 1)
                xyz = rotations.get(p.name, (0, 0, 0))
                q = Quaternion((0, 0, 1), xyz[2]) @ Quaternion((0, 1, 0), xyz[1]) @ Quaternion((1, 0, 0), xyz[0])
                basis = p.bone.matrix_local.to_quaternion()
                p.rotation_quaternion = basis.inverted() @ q @ basis
                p.keyframe_insert('rotation_quaternion', frame=frame, group=p.name)
        action['purpose'] = 'Golden Path compatibility motion'
    rig.animation_data.action = bpy.data.actions['idle']
    scene.frame_set(1)
    print('Body ready: 65 original bones, head renamed, four shared actions')


def finish_face(face_id):
    rig = bpy.data.objects['humanoid_v1']
    rig.animation_data.action = None
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    for o in list(bpy.data.objects):
        if o.get('golden_path_face'):
            bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f'assets/characters/tripo/face/{face_id}/model.glb'))
    imported = set(bpy.data.objects) - before
    target = OUT / f'golden_path_{face_id}'
    write_json(target / 'face_source_inspection.json', inspect(imported))
    assert len(imported) == 1
    face = next(iter(imported))
    assert face.type == 'MESH' and not face.vertex_groups
    face.name = 'Head'
    face['golden_path_face'] = face_id
    face['hair_integrated'] = face_id == '002'
    face['surface_expression'] = 'Head material UV texture; normal depth test'
    face.data.materials[0].name = 'Head_' + face_id
    scale, position = FITS[face_id]
    face.data.transform(Matrix.Translation(Vector(position)) @ Matrix.Scale(scale, 4) @ face.matrix_world)
    face.matrix_world = Matrix.Identity(4)
    face.parent = rig
    group = face.vertex_groups.new(name='head')
    group.add(list(range(len(face.data.vertices))), 1.0, 'REPLACE')
    mod = face.modifiers.new('SharedSkeleton', 'ARMATURE')
    mod.object = rig
    rig.animation_data.action = bpy.data.actions['idle']
    bpy.context.scene.frame_set(1)
    manifest_path = ROOT / f'assets/characters/tripo/characters/golden_path_{face_id}.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest['fit'] = dict(face_position=list(position), face_rotation_degrees=[0, 0, 0], face_scale=[scale]*3)
    manifest['fit_coordinate_system'] = 'Blender Z-up meters; source world transform then scale and translation, baked into mesh'
    manifest['hair_mode'] = 'integrated_in_head' if face_id == '002' else 'absent_in_source'
    write_json(manifest_path, manifest)
    bpy.ops.object.select_all(action='DESELECT')
    for name in ['Character', 'humanoid_v1', 'Body', 'Head']:
        bpy.data.objects[name].select_set(True)
    # GLB is the exporter default; avoid assuming dynamic enum identifiers.
    bpy.ops.export_scene.gltf(filepath=str(target / 'character.glb'), use_selection=True,
                             export_animations=True, export_animation_mode='ACTIONS',
                             export_force_sampling=True, export_frame_range=False,
                             export_extras=True)
    work = ROOT / 'artifacts/golden_path' / face_id
    work.mkdir(parents=True, exist_ok=True)
    (work.parent / '.gdignore').touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(work / 'character.blend'))
    print('EXPORTED', face_id, 'fit', manifest['fit'])


def preview(face_id, clip='idle', frame=1, side=False):
    rig = bpy.data.objects['humanoid_v1']
    rig.animation_data.action = bpy.data.actions[clip]
    scene = bpy.context.scene
    scene.frame_set(frame)
    co = bpy.data.objects.get('PreviewCamera')
    if co is None:
        data = bpy.data.cameras.new('PreviewCamera')
        co = bpy.data.objects.new('PreviewCamera', data)
        scene.collection.objects.link(co)
    enum(co.data, 'type', 'ORTHO')
    co.data.ortho_scale = 1.7
    co.location = (2, -3, 1.3) if side else (0, -3, .85)
    co.rotation_euler = (Vector((0, 0, .72))-co.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = co
    lo = bpy.data.objects.get('PreviewLight')
    if lo is None:
        data = bpy.data.lights.new('PreviewLight', 'AREA')
        lo = bpy.data.objects.new('PreviewLight', data)
        scene.collection.objects.link(lo)
    lo.location = (-1, -3, 3)
    lo.rotation_euler = (Vector((0, 0, .7))-lo.location).to_track_quat('-Z', 'Y').to_euler()
    lo.data.energy = 300
    lo.data.size = 4
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    enum(scene.render.image_settings, 'file_format', 'PNG')
    scene.render.filepath = str(OUT / f'golden_path_{face_id}/{clip}_{"side" if side else "front"}.png')
    bpy.ops.render.render(write_still=True)
