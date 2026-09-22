"""Reopen delivered files and verify preservation and rigid modular head parts."""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from inspect_tripo_roster import SOURCES
from tripo_roster_common import fingerprint
from prepare_tripo_roster import render_previews

results={}
for key,path in SOURCES.items():
    source=ROOT/'assets/characters'/path
    out=source.parent/'prepared'
    report=json.loads((out/'validation.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(out/'character.blend'))
    scene=bpy.context.scene
    assert scene.name=='Toon' and scene.view_settings.view_transform=='Standard'
    assert 'EEVEE' in scene.render.engine
    original=bpy.data.scenes['Original']
    assert fingerprint(original.objects['Original_Body'].data)==report['geometry_before']
    assert hashlib.sha256(source.read_bytes()).hexdigest()==report['source_sha256']
    hashes={i.name:hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.packed_file}
    assert hashes==report['packed_images_sha256']
    assert len([o for o in scene.objects if o.type=='LIGHT'])==1
    mat=scene.objects['Body'].data.materials[0]
    ramp=next(n for n in mat.node_tree.nodes if n.type=='VALTORGB')
    assert ramp.color_ramp.interpolation=='CONSTANT' and len(ramp.color_ramp.elements)==3
    assert not any(n.type in ['NORMAL_MAP','BUMP','BSDF_PRINCIPLED'] for n in mat.node_tree.nodes)
    rig=scene.objects['Character_Rig']
    assert len(rig.data.bones)==26
    rigid_errors={}
    for clip in ['idle','walk','run']:
        rig.animation_data.action=bpy.data.actions[clip]
        for frame in [1,6,9,15]:
            scene.frame_set(frame)
            for name in ['Face_Default','Head_Shell']:
                obj=scene.objects[name]
                ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); data=ev.to_mesh()
                # All distances to a reference point must be preserved under head motion.
                origin=obj.data.vertices[0].co; changed=data.vertices[0].co
                error=max(abs((v.co-changed).length-(old.co-origin).length) for v,old in zip(data.vertices,obj.data.vertices))
                assert error<1e-5,(key,clip,frame,name,error)
                rigid_errors[name]=max(rigid_errors.get(name,0),error)
                ev.to_mesh_clear()
    art=ROOT/'artifacts/tripo_roster'/key
    render_previews(scene,original,rig,art)
    # Back and profile catches cloth/limb problems hidden from the main view.
    camera=scene.camera
    for name,location in [('run_back',(1.1,2.7,1.35)),('walk_side',(2.8,0,1.0))]:
        camera.location=location
        camera.rotation_euler=(Vector((0,0,.49))-camera.location).to_track_quat('-Z','Y').to_euler()
        rig.animation_data.action=bpy.data.actions['run' if 'run' in name else 'walk']
        scene.frame_set(6 if 'run' in name else 9)
        scene.render.filepath=str(art/(name+'.png'))
        bpy.ops.render.render(write_still=True)
    results[key]={'saved_file_verified':True,'source_and_textures_preserved':True,'rigid_distance_max_error':rigid_errors}
    print('REOPEN_VERIFIED',key,flush=True)
(ROOT/'artifacts/tripo_roster/reopen_validation.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('ALL_NINE_REOPEN_VALIDATED',flush=True)
