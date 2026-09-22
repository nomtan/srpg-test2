"""Reopen the pilot; reuse one library, render motion and all six head swaps."""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from inspect_tripo_roster import SOURCES
from prepare_character_phase1 import KEYS, ART, SHARED, skeleton_spec, write_json


def setup():
    scene = bpy.context.scene
    scene.render.resolution_x = 400
    scene.render.resolution_y = 460
    scene.render.image_settings.file_format = 'PNG'
    scene.camera.location = (-.9,3,1.1)
    scene.camera.rotation_euler = (Vector((0,0,.50))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    # Neutral emission matches the raw texture without lighting obscuring the seam.
    for mat in bpy.data.materials:
        if not mat.use_nodes: continue
        tex = next((n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'),None)
        output = next((n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL'),None)
        if tex and output:
            emit = mat.node_tree.nodes.new('ShaderNodeEmission')
            mat.node_tree.links.new(tex.outputs['Color'],emit.inputs['Color'])
            mat.node_tree.links.new(emit.outputs[0],output.inputs['Surface'])
    return scene


def load_actions():
    with bpy.data.libraries.load(str(SHARED/'animations/common_combat.blend'),link=False) as (src,dst):
        dst.actions = src.actions
    return {a.name:a for a in dst.actions}


def render(scene,name):
    scene.render.filepath = str(ART/(name+'.png'))
    bpy.ops.render.render(write_still=True)


def main():
    expected = json.loads((SHARED/'master_rig/skeleton.json').read_text())
    result = {}
    for key in KEYS:
        out = (ROOT/'assets/characters'/SOURCES[key]).parent/'prepared/phase1'
        bpy.ops.wm.open_mainfile(filepath=str(out/'character.blend'))
        rig = bpy.data.objects['MasterRig']
        current = skeleton_spec(rig)
        assert len(current)==len(expected)
        for a,b in zip(current,expected):
            assert a['name']==b['name'] and a['parent']==b['parent']
            error = max(abs(x-y) for r,s in zip(a['matrix'],b['matrix']) for x,y in zip(r,s))
            assert error<1e-5, (key,a['name'],error,a['matrix'],b['matrix'])
        assert len(bpy.data.actions)==0
        scene = setup()
        actions = load_actions()
        assert set(actions)=={'idle','walk','attack_melee','cast_magic','hit'}
        rig.animation_data_create()
        report = {}
        for name,action in actions.items():
            rig.animation_data.action = action
            if action.slots: rig.animation_data.action_slot = action.slots[0]
            maximum = 0
            floors = []
            for frame in [1, int(action.frame_range[1]*.25), int(action.frame_range[1]*.5), int(action.frame_range[1]*.75), int(action.frame_range[1])]:
                scene.frame_set(frame)
                assert rig.pose.bones['Root'].location.length<1e-7
                for part in ['Body','HeadBase']:
                    obj = scene.objects[part]
                    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
                    mesh = ev.to_mesh()
                    assert all(all(abs(c)<3 for c in v.co) for v in mesh.vertices)
                    if part=='Body': floors.append(min(v.co.z for v in mesh.vertices))
                    for edge in mesh.edges:
                        i,j = edge.vertices
                        old = (obj.data.vertices[i].co-obj.data.vertices[j].co).length
                        if old>.002:
                            maximum=max(maximum,(mesh.vertices[i].co-mesh.vertices[j].co).length/old)
                    ev.to_mesh_clear()
            scene.frame_set(int(action.frame_range[1]*.25))
            render(scene,key+'_'+name)
            report[name] = {'max_edge_stretch':maximum, 'floor_range': [min(floors),max(floors)],'shared_action':True}
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.rotation_euler=(0,0,0)
            pb.location=(0,0,0)
        scene.frame_set(1)
        render(scene,key+'_tpose')
        # Six cross-character combinations. Head mesh comes from delivered GLB.
        original_head = scene.objects['HeadBase']
        original_head.hide_render=True
        for other in KEYS:
            if other==key: continue
            path = (ROOT/'assets/characters'/SOURCES[other]).parent/'prepared/phase1/head_default.glb'
            before = set(scene.objects)
            bpy.ops.import_scene.gltf(filepath=str(path))
            added = set(scene.objects)-before
            head = next(o for o in added if o.type=='MESH')
            rig.animation_data.action=actions['idle']
            if actions['idle'].slots: rig.animation_data.action_slot=actions['idle'].slots[0]
            scene.frame_set(15)
            # Importer assumes Y-up world geometry, but this GLB is bone-local.
            head.matrix_world=rig.matrix_world @ rig.pose.bones['Head'].matrix @ Matrix.Rotation(-math.pi/2,4,'X')
            setup()
            render(scene,key+'_with_'+other)
            for o in added: bpy.data.objects.remove(o,do_unlink=True)
        original_head.hide_render=False
        result[key] = report
    write_json(ART/'blender_validation.json', result)
    print('PHASE1_REOPEN_CHECKS_COMPLETE',flush=True)


if __name__=='__main__': main()
