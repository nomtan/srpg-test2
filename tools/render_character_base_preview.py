import bpy
from mathutils import Vector
import os

ROOT=r"C:\Users\nomur\Desktop\git\srpg-test2"
blend=os.path.join(ROOT,'assets','characters','base_tpose','CHR_Base_TPose.blend')
out=os.path.join(ROOT,'assets','characters','base_tpose','CHR_Base_TPose_preview.png')
bpy.ops.wm.open_mainfile(filepath=blend)

def point(obj,target):
    obj.rotation_euler=((Vector(target)-obj.location).to_track_quat('-Z','Y')).to_euler()

bpy.ops.object.camera_add(location=(2.7,4.5,2.35))
cam=bpy.context.object; point(cam,(0,0,0.76)); cam.data.lens=62
bpy.context.scene.camera=cam
bpy.ops.object.light_add(type='AREA',location=(2.2,3.0,4.0))
key=bpy.context.object; key.data.energy=650; key.data.shape='DISK'; key.data.size=4.0; point(key,(0,0,.8))
bpy.ops.object.light_add(type='AREA',location=(-3.0,1.0,2.1))
fill=bpy.context.object; fill.data.energy=380; fill.data.size=3.0; point(fill,(0,0,.8))
bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,-.005))
plane=bpy.context.object
mat=bpy.data.materials.new('PreviewGround'); mat.diffuse_color=(.10,.12,.14,1); plane.data.materials.append(mat)
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=700; scene.render.resolution_y=700; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.filepath=out
scene.world.color=(.035,.045,.06)
bpy.ops.render.render(write_still=True)
print(out)
