import bpy
import json

properties = bpy.ops.export_scene.gltf.get_rna_type().properties
names = ['export_format', 'export_animations', 'export_animation_mode', 'export_frame_range',
         'export_frame_step', 'export_force_sampling', 'export_nla_strips', 'export_skins',
         'export_all_influences', 'export_yup', 'export_apply', 'export_image_format',
         'export_anim_single_armature', 'export_morph', 'export_optimize_animation_size',
         'export_optimize_animation_keep_anim_armature', 'use_selection', 'export_rest_position_armature']
print(json.dumps({n: {'type': properties[n].type, 'default': properties[n].default,
                     'enum': [i.identifier for i in properties[n].enum_items] if properties[n].type == 'ENUM' else []}
                  for n in names if n in properties}, indent=2))
