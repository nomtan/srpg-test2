"""Reopen saved Phase 1.5 files and measure motion/feet/edge deformation."""
import json
import sys
from pathlib import Path
sys.dont_write_bytecode=True
import bpy
import numpy as np
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from prepare_character_phase1_5 import ART,SOURCES,verify_protected,natural_pose,write_json


def vertices(obj):
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh=evaluated.to_mesh()
    points=np.empty(len(mesh.vertices)*3,dtype=np.float32)
    mesh.vertices.foreach_get('co',points)
    evaluated.to_mesh_clear()
    return points.reshape(-1,3)


def main():
    verify_protected()
    source=json.loads((ROOT/'assets/characters/_shared/master_rig/skeleton.json').read_text())
    results={}
    for key,relative in SOURCES.items():
        out=(ROOT/'assets/characters'/relative).parent/'prepared/phase1_5'
        bpy.ops.wm.open_mainfile(filepath=str(out/'character.blend'))
        scene=bpy.context.scene
        rig=scene.objects['MasterRig']
        body=scene.objects['Body']
        assert len(rig.data.bones)==26
        for item in source:
            bone=rig.data.bones[item['name']]
            assert (bone.parent.name if bone.parent else None)==item['parent']
            expected=Matrix(item['matrix']).to_3x3()
            assert max(abs(a-b) for r,s in zip(bone.matrix_local.to_3x3(),expected) for a,b in zip(r,s))<1e-5
        rig.animation_data.action=None
        natural_pose(rig,key)
        baseline=vertices(body)
        edges=np.array([e.vertices[:] for e in body.data.edges])
        before=np.linalg.norm(baseline[edges[:,0]]-baseline[edges[:,1]],axis=1)
        active=before>.004
        regions={
            'feet':baseline[:,2]<.095,
            'robe':(baseline[:,2]>.095)&(baseline[:,2]<.28),
            'upper_body':baseline[:,2]>.28,
        }
        entry={'bone_axes_match_source':True,'clips':{},'native_pose_floor':float(baseline[:,2].min())}
        for name in ['idle','walk','attack_melee','cast_magic','hit']:
            action=bpy.data.actions[name]
            rig.animation_data.action=action
            if action.slots: rig.animation_data.action_slot=action.slots[0]
            end=int(action.frame_range[1])
            frames=range(1,end+1) if name=='walk' else [1,round(end*.25),round(end*.5),round(end*.75),end]
            floors=[]; stretches=[]; changed=0.; initial=None
            foot_bounds={side:[] for side in ('L','R')}
            for frame in frames:
                scene.frame_set(frame)
                points=vertices(body)
                assert np.isfinite(points).all()
                assert rig.pose.bones['Root'].location.length<1e-7
                assert all(pb.location.length<1e-5 for pb in rig.pose.bones), (key,name,'non-rotation motion')
                pose=[v for pb in rig.pose.bones for row in pb.matrix_basis for v in row]
                if initial is None: initial=pose
                else: changed=max(changed,max(abs(a-b) for a,b in zip(initial,pose)))
                lengths=np.linalg.norm(points[edges[:,0]]-points[edges[:,1]],axis=1)
                stretches.append(lengths[active]/before[active])
                floors.append(float(points[:,2].min()))
                for side,sign in [('L',-1),('R',1)]:
                    foot=(baseline[:,2]<.075)&(baseline[:,0]*sign>.04)
                    foot_bounds[side].append(float(points[foot,2].min()))
            assert changed>1e-4,(key,name,'not animated')
            stretch=np.concatenate(stretches)
            entry['clips'][name]={'frames_sampled':len(list(frames)), 'actual_motion_delta':changed,
                'floor_min_m':min(floors),'floor_max_m':max(floors),
                'edge_stretch_max':float(stretch.max()),
                'edge_stretch_p99':float(np.quantile(stretch,.99)),
                'edge_stretch_p999':float(np.quantile(stretch,.999)),
                'edges_over_2x_samples':int((stretch>2).sum()),
                'foot_floor_ranges':{s:[min(v),max(v)] for s,v in foot_bounds.items()}}
        results[key]=entry
        print('REOPEN_MEASURED',key,flush=True)
    write_json(ART/'blender_validation.json',results)
    write_json(ART/'preservation.json',{'unchanged_files':verify_protected(),'all_protected_files_unchanged':True})
    print('PHASE1_5_REOPEN_COMPLETE',flush=True)


if __name__=='__main__': main()
