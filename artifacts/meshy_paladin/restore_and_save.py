"""Reproduce the inspected rig from the pre-rig backup and save the result."""
import bpy
import json
from pathlib import Path
from mathutils import Vector

folder = Path(__file__).resolve().parent
target = folder / 'blue_plume_paladin_walk.blend'
if target.exists():
    raise RuntimeError(f'Refusing to overwrite {target}')
namespace = {'__name__': 'meshy_paladin_rig'}
script = folder / 'rig_paladin.py'
exec(compile(script.read_text(encoding='utf-8'), str(script), 'exec'), namespace)
namespace['build']()
namespace['bind']()
namespace['animate']()
summary = namespace['inspect']()
assert summary['unweighted_vertices'] == 0
assert summary['loop_max_vertex_delta'] < 1e-6
assert len(bpy.data.images) == 3
for image in bpy.data.images:
    assert image.packed_file
    # Background loading is lazy; accessing a pixel decodes the packed image.
    first_pixel = image.pixels[0]
    assert image.has_data and image.size[0] > 0
bpy.context.scene.frame_set(1)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            space.region_3d.view_rotation = Vector((3, -6, 1.6)).to_track_quat('Z', 'Y')
            space.region_3d.view_location = Vector((0, 0, -.02))
            space.region_3d.view_distance = 3.4
            space.overlay.show_overlays = False
            # Reuse the material-preview enum already verified against this Blender.
            space.shading.type = 'MATERIAL'
text = bpy.data.texts.new('Paladin_Readme')
text.write((folder / 'README.md').read_text(encoding='utf-8'))
bpy.ops.wm.save_as_mainfile(filepath=str(target), compress=True)
print(json.dumps({'saved': str(target), 'bytes': target.stat().st_size, 'verified': summary}, indent=2))
