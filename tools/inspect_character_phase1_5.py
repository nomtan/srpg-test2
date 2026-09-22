"""Inspect raw colors/geometry for hand-authored semantic selection rules."""
import json
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from tripo_roster_common import preview_scene

SOURCES = {'adventure':'tripo_adventure/adventure.glb', 'knight':'tripo_knight2/knigth.glb',
           'black_mage':'tripo_black_mage/black_mage.glb'}
ART = ROOT/'artifacts/character_phase1_5'

def main():
    for key,relative in SOURCES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/characters'/relative))
        mesh = max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
        for o in bpy.context.scene.objects:
            if o.type=='MESH' and o!=mesh: o.hide_render=True
        mat=mesh.data.materials[0]
        nodes,links=mat.node_tree.nodes,mat.node_tree.links
        tex=next(n for n in nodes if n.type=='TEX_IMAGE')
        image=tex.image
        (ART/(key+'_raw_albedo.jpg')).write_bytes(image.packed_file.data)
        emit=nodes.new('ShaderNodeEmission')
        links.new(tex.outputs['Color'],emit.inputs['Color'])
        links.new(emit.outputs[0],next(n for n in nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
        pixels=np.array(image.pixels[:],dtype=np.float32).reshape(image.size[1],image.size[0],4)
        uv=mesh.data.uv_layers.active.data
        samples=[]
        for p in mesh.data.polygons:
            t=sum((uv[i].uv for i in p.loop_indices),Vector((0,0)))/len(p.loop_indices)
            c=pixels[min(image.size[1]-1,int(t.y*image.size[1])),min(image.size[0]-1,int(t.x*image.size[0])),:3]
            samples.append([*p.center,*c,p.area])
        np.save(ART/(key+'_face_samples.npy'),samples)
        preview_scene(bpy.context.scene)
        scene=bpy.context.scene
        scene.render.resolution_x=640
        scene.render.resolution_y=720
        for view,position in [('front',(0,-3,.6)),('back',(0,3,.6)),('side',(3,0,.6))]:
            scene.camera.location=position
            scene.camera.rotation_euler=(Vector((0,0,.49))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(ART/(key+'_raw_'+view+'.png'))
            bpy.ops.render.render(write_still=True)
    print('RAW_INSPECTION_COMPLETE',flush=True)

if __name__=='__main__': main()
