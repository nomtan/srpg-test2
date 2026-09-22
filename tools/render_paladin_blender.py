"""Render one saved paladin view in a separate Blender process.

blender --background assets/characters/paladin/paladin.blend \
  --python tools/render_paladin_blender.py -- rear
"""
import bpy
import sys
from pathlib import Path

out=Path(__file__).resolve().parents[1]/'assets'/'characters'/'paladin'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['front']
view=args[0]
if view not in ('front','rear'):
    raise ValueError('Choose front or rear')
scene=bpy.data.scenes['PALADIN | Studio']
bpy.context.window.scene=scene
scene.camera=bpy.data.objects['Camera | '+('Front' if view=='front' else 'Rear')+' three-quarter']
scene.render.resolution_percentage=100
scene.cycles.samples=64
scene.render.filepath=str(out/('paladin_'+view+'.png'))
bpy.ops.render.render(write_still=True)
print('PALADIN_RENDER_COMPLETE',view)
