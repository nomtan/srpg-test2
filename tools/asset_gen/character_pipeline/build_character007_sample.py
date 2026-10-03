"""Run through Blender MCP. Walk-only sample; not a Phase 5 modular Face."""
import hashlib
import json
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
from build_characters import bounds
from build_golden_path import create_animations
from build_modular_parts import clean_toon_materials

ROOT = Path(__file__).resolve().parents[3]


def build():
    scene = bpy.context.scene
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    body = next(o for o in scene.objects if o.type == 'MESH' and o.parent == rig)
    face = next(o for o in scene.objects if o.type == 'MESH' and o.data.materials and o.parent is None)
    hashes = {kind: hashlib.sha256((ROOT / f'assets/characters/tripo/{kind}/007/model.glb').read_bytes()).hexdigest() for kind in ('body', 'face')}
    rig.name = 'Character007Rig'
    rig.data.bones['mixamorig:Head'].name = 'head'
    for pose in rig.pose.bones:
        pose.custom_shape = None
    body.name = 'Body007'
    face.name = 'Face007'
    # Keep the approved size; lower the complete Face into the collar.
    scale = 0.54
    position = (0.001907, -0.0589, 0.84)
    face.data.transform(Matrix.Translation(Vector(position)) @ Matrix.Scale(scale, 4) @ face.matrix_world)
    face.matrix_world = Matrix.Identity(4)
    face.parent = rig
    face.vertex_groups.new(name='head').add(list(range(len(face.data.vertices))), 1, 'REPLACE')
    face.modifiers.new('BodyHeadFollow', 'ARMATURE').object = rig
    for obj in (body, face):
        clean_toon_materials(obj)
    character = bpy.data.objects.new('Character007', None)
    scene.collection.objects.link(character)
    rig.parent = character
    create_animations(rig, [('walk', 30)])
    bpy.ops.object.select_all(action='DESELECT')
    for obj in (character, rig, body, face):
        obj.select_set(True)
    output = ROOT / 'assets/characters/generated/character007'
    output.mkdir(parents=True, exist_ok=True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    assert 'ACTIONS' in [item.identifier for item in props['export_animation_mode'].enum_items]
    bpy.ops.export_scene.gltf(filepath=str(output / 'character.glb'), use_selection=True,
        use_active_scene=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False, export_extras=True)
    for kind, digest in hashes.items():
        assert hashlib.sha256((ROOT / f'assets/characters/tripo/{kind}/007/model.glb').read_bytes()).hexdigest() == digest
    report = dict(purpose='JRPG sample, walk only; Phase 5 expression authoring remains pending',
        body_id='body007', face_id='face007', source_sha256=hashes,
        face_fit=dict(scale=scale, position=position), animation=['walk'], weapon=None,
        bones=len(rig.data.bones), bounds={o.name:[list(v) for v in bounds(o)] for o in (body,face)})
    (output / 'build_report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('CHARACTER007_SAMPLE', output)


build()
