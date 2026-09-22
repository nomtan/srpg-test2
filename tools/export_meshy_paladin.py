"""Export the inspected Meshy rig for JRPGWorldSample without editing the blend.

blender --background --factory-startup --python tools/export_meshy_paladin.py
"""
import bpy
import json
import math
import struct
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artifacts/meshy_paladin/blue_plume_paladin_walk.blend'
OUTPUT = ROOT / 'assets/characters/meshy_paladin/blue_plume_paladin.glb'

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
rig = bpy.data.objects['Paladin_Rig']
mesh = bpy.data.objects['output_unwrapped']
walk = rig.animation_data.action
walk.name = 'walk'
walk.use_fake_user = True
rig.animation_data.action = None
rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
pose = {name: matrix.copy() for name, matrix in rest.items()}

# A planted neutral stance avoids freezing one foot in the air when movement stops.
for side, sign in [('L', 1), ('R', -1)]:
    shoulder = rest['upper_arm.' + side].translation.copy()
    upper_direction = Vector((sign * .40, 0, -.92)).normalized()
    lower_direction = Vector((sign * .12, -.20, -.98)).normalized()
    elbow = shoulder + upper_direction * rig.data.bones['upper_arm.' + side].length
    wrist = elbow + lower_direction * rig.data.bones['forearm.' + side].length
    for name, origin, direction in [
        ('upper_arm.' + side, shoulder, upper_direction),
        ('forearm.' + side, elbow, lower_direction),
        ('hand.' + side, wrist, lower_direction),
    ]:
        bone = rig.data.bones[name]
        rotation = (bone.tail_local - bone.head_local).normalized().rotation_difference(direction)
        pose[name] = rotation.to_matrix().to_4x4() @ rest[name]
        pose[name].translation = origin

idle = bpy.data.actions.new('idle')
idle.use_fake_user = True
rig.animation_data.action = idle
for bone in rig.pose.bones:
    if bone.parent:
        basis = rest[bone.name].inverted() @ rest[bone.parent.name] @ pose[bone.parent.name].inverted() @ pose[bone.name]
    else:
        basis = rest[bone.name].inverted() @ pose[bone.name]
    bone.location, bone.rotation_quaternion, _ = basis.decompose()
    bone.scale = (1, 1, 1)
    for frame in [1, 25]:
        bone.keyframe_insert(data_path='location', frame=frame, group=bone.name)
        bone.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=bone.name)

# Match the sample's +X-facing, feet-at-origin, approximately 2.2-unit characters.
floor_z = min(v.co.z for v in mesh.data.vertices)
source_height = max(v.co.z for v in mesh.data.vertices) - floor_z
scale = 2.2 / source_height
wrapper = bpy.data.objects.new('BluePlumePaladin', None)
bpy.context.scene.collection.objects.link(wrapper)
wrapper.rotation_euler.z = math.pi / 2
wrapper.scale = (scale, scale, scale)
wrapper.location.z = -floor_z * scale
rig.parent = wrapper
rig.matrix_parent_inverse = Matrix.Identity(4)
bpy.context.scene.frame_set(1)
bpy.context.view_layer.update()
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT), export_format='GLB', export_yup=True,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=False, export_frame_step=1, export_force_sampling=True,
    export_anim_slide_to_zero=True,
    export_skins=True, export_all_influences=False, export_apply=False,
    export_morph=False, export_rest_position_armature=True,
    export_optimize_animation_size=False, export_cameras=False, export_lights=False,
)

data = OUTPUT.read_bytes()
json_length, chunk_type = struct.unpack_from('<II', data, 12)
assert chunk_type == 0x4E4F534A
gltf = json.loads(data[20:20 + json_length])
clips = {clip['name']: max(gltf['accessors'][sampler['input']]['max'][0] for sampler in clip['samplers'])
         for clip in gltf['animations']}
assert set(clips) == {'idle', 'walk'}, clips
assert abs(clips['walk'] - 32 / 24) < .0001
assert len(gltf['skins']) == 1 and len(gltf['skins'][0]['joints']) == 24
assert len(gltf['images']) == 3
print(json.dumps({'file': str(OUTPUT), 'bytes': len(data), 'animations': clips,
                  'bones': len(gltf['skins'][0]['joints']), 'images': len(gltf['images']),
                  'scale': scale, 'front': '+X', 'feet_y': 0}, indent=2))
