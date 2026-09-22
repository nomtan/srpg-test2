"""Read-back checks; run with Blender --background <completed blend>."""
import bpy
import json

rig = bpy.data.objects['Paladin_Rig']
obj = bpy.data.objects['output_unwrapped']
assert len(rig.data.bones) == 24
assert rig.animation_data.action.name == 'Walk_InPlace'
assert len(obj.data.uv_layers) == 1
assert all(image.packed_file for image in bpy.data.images)
assert (bpy.context.scene.frame_start, bpy.context.scene.frame_end) == (1, 32)
print(json.dumps({
    'bones': len(rig.data.bones),
    'action': rig.animation_data.action.name,
    'range': [bpy.context.scene.frame_start, bpy.context.scene.frame_end],
    'textures': [image.name for image in bpy.data.images],
    'saved_file_verified': bpy.data.filepath,
}, indent=2))
