"""Build nine editable Toon characters and portable, modular game assets.

blender --background --factory-startup --python tools/prepare_tripo_roster.py -- --render
Optional: --only adventure black_mage (keys from SOURCES).
Source GLBs are read only. The source scene, rig, materials, UVs and images are kept.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from tripo_roster_common import (BANDS, OUTLINE_WIDTH, enum, smooth, blend,
    make_materials, angle_normals, action_curves, preview_scene, fingerprint, digest)
from inspect_tripo_roster import SOURCES

PERIODS = {'idle': 60, 'walk': 30, 'run': 20}
# Bone landmarks in the original Blender mesh coordinates (Z up, front -Y).
# Each entry: head base, shoulder X/Z, elbow X/Z, wrist X/Z, hip/knee/ankle Z,
# face X radius, face bottom/top/front-plane, skirt policy.
PROFILES = {
    'adventure': (.55, (.19,.46), (.255,.39), (.31,.34), (.245,.13,.06), (.153,.55,.755,-.075), 'coat'),
    'black_mage': (.48, (.15,.365), (.20,.30), (.24,.255), (.175,.09,.045), (.135,.475,.66,-.10), 'robe'),
    'butler': (.55, (.15,.455), (.24,.455), (.30,.455), (.225,.115,.045), (.145,.55,.77,-.08), 'dress'),
    'chief_butler': (.55, (.16,.465), (.265,.465), (.33,.465), (.25,.13,.055), (.15,.55,.785,-.06), 'coat'),
    'hero': (.55, (.19,.455), (.25,.365), (.30,.305), (.245,.132,.048), (.145,.55,.775,-.075), 'armor'),
    'knight': (.59, (.185,.503), (.24,.438), (.304,.410), (.209,.109,.055), (.165,.60,.82,-.07), 'armor'),
    'scholar': (.53, (.15,.43), (.245,.43), (.30,.43), (.225,.115,.045), (.145,.53,.74,-.08), 'coat'),
    'warrior': (.55, (.19,.455), (.255,.365), (.31,.31), (.245,.13,.052), (.145,.55,.76,-.075), 'armor'),
    'white_mage': (.53, (.16,.45), (.28,.45), (.345,.45), (.225,.115,.045), (.145,.53,.75,-.06), 'robe'),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_rig(mesh, key):
    head, shoulder, elbow, wrist, leg, face, cloth = PROFILES[key]
    arm = bpy.data.armatures.new('Character_Skeleton')
    rig = bpy.data.objects.new('Character_Rig', arm)
    bpy.context.scene.collection.objects.link(rig)
    rig.matrix_world = mesh.matrix_world.copy()
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name, a, b, parent=None, deform=True):
        item = arm.edit_bones.new(name)
        item.head, item.tail, item.use_deform = a, b, deform
        if parent:
            item.parent = arm.edit_bones[parent]
    hip, knee, ankle = leg
    chest = shoulder[1] + .025
    bone('root', (0,0,0), (0,0,.06), deform=False)
    bone('pelvis', (0,0,hip), (0,0,hip+.07), 'root')
    bone('spine', (0,0,hip+.07), (0,0,chest-.06), 'pelvis')
    bone('chest', (0,0,chest-.06), (0,0,chest), 'spine')
    bone('neck', (0,0,chest), (0,0,head), 'chest')
    bone('head', (0,0,head), (0,0,.88), 'neck')
    leg_x = .095 if key in ['black_mage','butler','scholar'] else .112
    for side, sign in [('L',1), ('R',-1)]:
        def point(xz, y=0): return (sign*xz[0], y, xz[1])
        bone('clavicle.'+side, (sign*.065,0,chest), point(shoulder), 'chest')
        bone('upper_arm.'+side, point(shoulder), point(elbow,-.01), 'clavicle.'+side)
        bone('forearm.'+side, point(elbow,-.01), point(wrist,-.025), 'upper_arm.'+side)
        hand_dir = (Vector(point(wrist,-.025))-Vector(point(elbow,-.01))).normalized()*.04
        bone('hand.'+side, point(wrist,-.025), Vector(point(wrist,-.025))+hand_dir, 'forearm.'+side)
        bone('thigh.'+side, (sign*leg_x,0,hip), (sign*leg_x*1.07,-.005,knee), 'pelvis')
        bone('shin.'+side, (sign*leg_x*1.07,-.005,knee), (sign*leg_x*1.10,.005,ankle), 'thigh.'+side)
        bone('foot.'+side, (sign*leg_x*1.10,.005,ankle), (sign*leg_x*1.10,-.095,.025), 'shin.'+side)
        bone('cape.'+side, (sign*.09,.085,chest), (sign*.12,.13,hip), 'chest')
        bone('cape_tip.'+side, (sign*.12,.13,hip), (sign*.16,.17,.10), 'cape.'+side)
    bone('tabard', (0,-.095,hip+.06), (0,-.12,hip-.04), 'pelvis')
    bone('tabard_tip', (0,-.12,hip-.04), (0,-.13,.09), 'tabard')
    bpy.ops.object.mode_set(mode='OBJECT')
    enum(arm,'display_type','STICK')
    rig.show_in_front = True
    for pb in rig.pose.bones: enum(pb,'rotation_mode','QUATERNION')
    mesh.parent = rig
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    mesh.matrix_basis = Matrix.Identity(4)
    mesh.modifiers.clear()
    mesh.vertex_groups.clear()
    mod = mesh.modifiers.new('Character Skin','ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = False
    for b in arm.bones:
        if b.use_deform: mesh.vertex_groups.new(name=b.name)
    # Spatial weights are evaluated on identical positions, including UV seam duplicates.
    # The head and hands stay rigid; blending is restricted to joint transition bands.
    for v in mesh.data.vertices:
        x,y,z = v.co
        ax = abs(x)
        side = 'L' if x >= 0 else 'R'
        torso = blend({'pelvis':1}, {'chest':1}, smooth(hip+.065,chest-.045,z))
        torso = blend(torso, {'head':1}, smooth(head-.02,head,z))
        leg_weights = blend({'thigh.'+side:1},{'shin.'+side:1},1-smooth(knee-.012,knee+.012,z))
        leg_weights = blend(leg_weights,{'foot.'+side:1},1-smooth(ankle+.014,ankle+.028,z))
        weights = blend(torso, leg_weights, 1-smooth(hip-.055,hip+.015,z))
        if cloth in ['dress','robe','coat']:
            # Keep the skirt shell together. Boots underneath still use leg chains.
            shell = smooth(.045,.060,z) * (1-smooth(hip+.03,hip+.065,z))
            shell *= max(smooth(.055,.09,abs(y)), smooth(leg_x+.035,leg_x+.06,ax))
            weights = blend(weights, {'pelvis':1}, shell)
            if cloth == 'dress':
                # The petticoat is a continuous ring above the boots, including
                # its inner folds. Do not split that ring between the knees.
                ring = smooth(.055,.080,z) * (1-smooth(hip+.03,hip+.065,z))
                weights = blend(weights, {'pelvis':1}, ring)
        elif z < hip+.08 and y < -.082:
            amount = smooth(.040,.060,z) * (1-smooth(hip+.055,hip+.085,z))
            panel = {'tabard':1} if ax < .105 else {'pelvis':1}
            weights = blend(weights, panel, amount)
        # Back cloth; no knee influence on the rear cape hem.
        back = smooth(.085,.125,y) * (1-smooth(chest-.035,chest,z))
        side_hem = smooth(.175,.20,ax) * smooth(0,.018,y) * (1-smooth(hip+.015,hip+.05,z))
        back = max(back,side_hem)
        if cloth == 'armor' or key in ['adventure','chief_butler']:
            cape = blend({'cape.'+side:1},{'cape_tip.'+side:1},1-smooth(hip-.02,hip+.025,z))
            if ax < .035:
                other = 'R' if side == 'L' else 'L'
                cape = blend({k.replace('.'+side,'.'+other):w for k,w in cape.items()},cape,.5+.5*smooth(0,.035,ax))
            weights = blend(weights,cape,back)
        # Distance along the shoulder-wrist direction supports both T and A poses.
        a=Vector((shoulder[0],0,shoulder[1])); e=Vector((elbow[0],-.01,elbow[1])); w=Vector((wrist[0],-.025,wrist[1]))
        axis=(w-a).normalized(); point=Vector((ax,y,z)); along=(point-a).dot(axis)
        arm_weights=blend({'upper_arm.'+side:1},{'forearm.'+side:1},smooth((e-a).length-.012,(e-a).length+.012,along))
        arm_weights=blend(arm_weights,{'hand.'+side:1},smooth((w-a).length-.014,(w-a).length+.012,along))
        # Only the extremities outside the torso participate; hats/hair stay on head.
        expected_z = shoulder[1] + (ax-shoulder[0])*(wrist[1]-shoulder[1])/max(.01,wrist[0]-shoulder[0])
        arm_amount = smooth(shoulder[0]-.045,shoulder[0]-.005,ax)
        arm_amount *= 1-smooth(.065,.115,abs(z-expected_z))
        arm_amount *= 1-smooth(head-.045,head,z)
        weights=blend(weights,arm_weights,arm_amount)
        if z >= head: weights={'head':1}
        entries=sorted(((n,w) for n,w in weights.items() if w>.0001),key=lambda item:-item[1])[:4]
        total=sum(w for n,w in entries)
        for name,weight in entries: mesh.vertex_groups[name].add([v.index],weight/total,'REPLACE')
    return rig


def animate(rig, mesh, key):
    scene=bpy.context.scene
    scene.render.fps=30
    rig.animation_data_create()
    rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
    vectors={b.name:b.tail_local-b.head_local for b in rig.data.bones}
    def inherited(pose,name):
        parent=rig.data.bones[name].parent.name
        return pose[parent] @ rest[parent].inverted() @ rest[name]
    def rotate(matrix,angle,axis):
        return Matrix.Translation(matrix.translation) @ Matrix.Rotation(angle,4,axis) @ matrix.to_3x3().to_4x4()
    def aim(name,origin,direction):
        result=vectors[name].normalized().rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4() @ rest[name]
        result.translation=origin
        return result
    for clip,period in PERIODS.items():
        action=bpy.data.actions.new(clip)
        action.use_fake_user=True
        rig.animation_data.action=action
        moving,running=clip!='idle',clip=='run'
        for frame in range(1,period+2):
            scene.frame_set(frame)
            t=math.tau*(frame-1)/period
            pose={'root':rest['root'].copy(),'pelvis':rest['pelvis'].copy()}
            pose['pelvis'].translation.z -= .018 if running else .010 if moving else .002
            pose['spine']=rotate(inherited(pose,'spine'),math.radians(4 if running else 1.5 if moving else .35*math.sin(t)),'X')
            pose['chest']=rotate(inherited(pose,'chest'),.015*math.sin(t) if moving else 0,'Z')
            pose['neck']=inherited(pose,'neck')
            pose['head']=rest['head'].copy()
            pose['head'].translation=inherited(pose,'head').translation
            for side,sign,offset in [('L',1,0),('R',-1,.5)]:
                u=((frame-1)/period+offset)%1
                stance=.50 if running else .62
                stride=.055 if running else .032
                if not moving: fy,lift=0,0
                elif u<stance: fy,lift=-stride+2*stride*u/stance,0
                else:
                    s=(u-stance)/(1-stance)
                    fy=stride-2*stride*smooth(0,1,s)
                    lift=(.038 if running else .019)*math.sin(math.pi*s)**1.5
                thigh,shin,foot=(prefix+side for prefix in ['thigh.','shin.','foot.'])
                hip=inherited(pose,thigh).translation
                ankle=rest[foot].translation+Vector((0,fy,lift))
                la,lb=vectors[thigh].length,vectors[shin].length
                direction=(ankle-hip).normalized()
                distance=min((ankle-hip).length,la+lb-.00001)
                ankle=hip+direction*distance
                along=(la*la-lb*lb+distance*distance)/(2*distance)
                bend=Vector((0,-1,0)); bend=(bend-direction*bend.dot(direction)).normalized()
                knee=hip+direction*along+bend*math.sqrt(max(0,la*la-along*along))
                pose[thigh]=aim(thigh,hip,knee-hip); pose[shin]=aim(shin,knee,ankle-knee)
                pose[foot]=rest[foot].copy(); pose[foot].translation=ankle
                clav,upper,fore,hand=(prefix+side for prefix in ['clavicle.','upper_arm.','forearm.','hand.'])
                pose[clav]=inherited(pose,clav)
                shoulder=inherited(pose,upper).translation
                swing=(.30 if running else .18)*math.cos(t+offset*math.tau) if moving else .006*math.sin(t)
                # Robe sleeves need more clearance from the torso.
                spread=.80 if key in ['butler','white_mage','scholar','chief_butler'] else .62
                upper_dir=Vector((sign*spread,swing,-.78)).normalized()
                fore_dir=Vector((sign*spread,swing-(.15 if running else .025),-.78)).normalized()
                elbow=shoulder+upper_dir*vectors[upper].length
                wrist=elbow+fore_dir*vectors[fore].length
                pose[upper]=aim(upper,shoulder,upper_dir); pose[fore]=aim(fore,elbow,fore_dir); pose[hand]=aim(hand,wrist,fore_dir)
                for name,phase in [('cape.'+side,0),('cape_tip.'+side,-.7)]:
                    flutter=(1.0 if moving else .20)*math.sin(2*t+phase)
                    pose[name]=rotate(inherited(pose,name),math.radians((3 if running else 1 if moving else 0)+flutter),'X')
            pose['tabard']=rotate(inherited(pose,'tabard'),math.radians(-2 if running else -.8 if moving else 0),'X')
            pose['tabard_tip']=inherited(pose,'tabard_tip')
            for pb in rig.pose.bones:
                basis=rest[pb.name].inverted() @ rest[pb.parent.name] @ pose[pb.parent.name].inverted() @ pose[pb.name] if pb.parent else rest[pb.name].inverted() @ pose[pb.name]
                pb.location,pb.rotation_quaternion,_=basis.decompose(); pb.scale=(1,1,1)
            bpy.context.view_layer.update()
            ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); data=ev.to_mesh()
            floor=min(v.co.z for v in data.vertices); ev.to_mesh_clear()
            rig.pose.bones['root'].location+=rest['root'].to_3x3().inverted() @ Vector((0,0,-floor))
            for pb in rig.pose.bones:
                pb.keyframe_insert(data_path='location',frame=frame,group=pb.name)
                pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=pb.name)
        for curve in action_curves(action):
            for point in curve.keyframe_points: enum(point,'interpolation','LINEAR')
    rig.animation_data.action=bpy.data.actions['idle']; scene.frame_set(1)


def partition(mesh, key, base):
    """Separate whole source triangles; copy their exact UVs and corner normals."""
    head=PROFILES[key][0]
    rx,low,high,front=PROFILES[key][5]
    groups={'Body':[], 'Head_Shell':[], 'Face_Default':[]}
    candidates=set()
    for p in mesh.data.polygons:
        c=p.center
        if all(mesh.data.vertices[v].co.z >= head for v in p.vertices) and abs(c.x)<rx and low<c.z<high and c.y<front:
            candidates.add(p.index)
    selected=candidates
    if key != 'knight':
        # Grow the continuous shallow face surface across geometric edges.
        # UV seams are matched by position; sharp folds at the fringe stop growth.
        vertex_keys=[tuple(round(c,5) for c in v.co) for v in mesh.data.vertices]
        shared=defaultdict(list)
        for p in mesh.data.polygons:
            for a,b in p.edge_keys:
                shared[tuple(sorted((vertex_keys[a],vertex_keys[b])))].append(p.index)
        neighbors=defaultdict(set); shallow=defaultdict(set)
        for indices in shared.values():
            for a in indices:
                if a not in candidates: continue
                for b in indices:
                    if a==b: continue
                    neighbors[a].add(b)
                    if b in candidates and mesh.data.polygons[a].normal.dot(mesh.data.polygons[b].normal)>math.cos(math.radians(18)):
                        shallow[a].add(b)
        components=[]; unseen=set(candidates)
        while unseen:
            first=unseen.pop(); region={first}; pending=[first]
            while pending:
                current=pending.pop(); found=shallow[current]&unseen
                unseen.difference_update(found); region.update(found); pending.extend(found)
            components.append(region)
        def face_score(region):
            return sum(p.area for i in region if abs((p:=mesh.data.polygons[i]).center.x)<.09 and p.center.z<low+.11 and p.normal.y<-.7)
        surface_region=max(components,key=face_score)
        # Use painted skin to find the facial patch. Then fill enclosed dark
        # islands (eyes/brows); hair connected to the exterior stays on the head.
        pixels=np.empty(len(base.pixels),dtype=np.float32); base.pixels.foreach_get(pixels)
        pixels=pixels.reshape((base.size[1],base.size[0],4))
        uv=mesh.data.uv_layers.active
        skin=set()
        for i in candidates:
            p=mesh.data.polygons[i]
            coords=[uv.data[li].uv for li in p.loop_indices]
            u=sum(c.x for c in coords)/len(coords); v=sum(c.y for c in coords)/len(coords)
            r,g,b,_=pixels[min(base.size[1]-1,max(0,int(v*base.size[1]))),min(base.size[0]-1,max(0,int(u*base.size[0])))]
            if r>.78 and .74<g/r<.92 and .58<b/r<.86:
                skin.add(i)
        assert len(skin)>30, ('No facial skin detected',key,len(skin))
        # Fit the shallow curved facial surface using light skin, then include
        # its painted dark eyes/brows. The raised fringe lies in front of this
        # surface, even when blonde hair has nearly the same color as skin.
        coords=np.array([tuple(mesh.data.polygons[i].center) for i in sorted(skin)])
        def features(coords):
            x,z=coords[:,0],coords[:,2]-(low+high)/2
            return np.column_stack((np.ones(len(coords)),x,x*x,z,z*z,x*z))
        design=features(coords); keep=np.ones(len(coords),dtype=bool)
        for _ in range(5):
            coefficients=np.linalg.lstsq(design[keep],coords[keep,1],rcond=None)[0]
            residual=np.abs(coords[:,1]-design@coefficients)
            keep=residual<max(.009,float(np.median(residual))*2.5)
        selected=set()
        for i in candidates:
            p=mesh.data.polygons[i]
            predicted=float((features(np.array([tuple(p.center)]))@coefficients)[0])
            tolerance=.012
            if abs(p.center.y-predicted)<tolerance:
                selected.add(i)
        mesh['face_surface_fit']=list(coefficients)
        # Brown-haired faces benefit from the surface fit around angular cheeks.
        # For pale/blonde hair, the connected region gives the cleaner fringe.
        selected=selected|surface_region if key in ['adventure','warrior'] else surface_region
        # Fill tiny enclosed nose/mouth islands so a replacement cannot leave a
        # triangle of the old facial expression behind. Exterior hair is excluded.
        unseen=candidates-selected
        while unseen:
            first=unseen.pop(); region={first}; pending=[first]; touches_outside=False
            while pending:
                current=pending.pop()
                touches_outside=touches_outside or bool(neighbors[current]-candidates)
                found=(neighbors[current]&unseen)
                unseen.difference_update(found); region.update(found); pending.extend(found)
            if not touches_outside and sum(mesh.data.polygons[i].area for i in region)<.003:
                if any(neighbors[i]&selected for i in region): selected.update(region)
        assert len(selected)>30,(key,len(skin),len(selected))
    for p in mesh.data.polygons:
        c=p.center
        is_head=all(mesh.data.vertices[v].co.z >= head for v in p.vertices)
        # This is a replaceable facial surface, not a new topology or an overlay.
        is_face=p.index in selected
        groups['Face_Default' if is_face else 'Head_Shell' if is_head else 'Body'].append(p.index)
    assert all(groups.values()), {k:len(v) for k,v in groups.items()}
    parts=[]
    mesh.data.calc_loop_triangles()
    source_normals=[n.vector.copy() for n in mesh.data.corner_normals]
    for name,indices in groups.items():
        polygons=[mesh.data.polygons[i] for i in indices]
        vertex_ids=sorted({v for p in polygons for v in p.vertices})
        mapping={v:i for i,v in enumerate(vertex_ids)}
        data=bpy.data.meshes.new(name+'_Mesh')
        data.from_pydata([mesh.data.vertices[i].co for i in vertex_ids],[],[[mapping[v] for v in p.vertices] for p in polygons])
        for mat in mesh.data.materials: data.materials.append(mat)
        for uv in mesh.data.uv_layers:
            target=data.uv_layers.new(name=uv.name)
            for dst,src in zip(data.polygons,polygons):
                for dl,sl in zip(dst.loop_indices,src.loop_indices): target.data[dl].uv=uv.data[sl].uv
        normals=[]
        for dst,src in zip(data.polygons,polygons):
            dst.use_smooth=src.use_smooth
            normals.extend(source_normals[i] for i in src.loop_indices)
        data.normals_split_custom_set(normals)
        obj=mesh.copy(); obj.data=data; obj.name=name
        bpy.context.scene.collection.objects.link(obj)
        obj.vertex_groups.clear()
        for group in mesh.vertex_groups: obj.vertex_groups.new(name=group.name)
        for i,old in enumerate(vertex_ids):
            for g in mesh.data.vertices[old].groups: obj.vertex_groups[g.group].add([i],g.weight,'REPLACE')
        obj['source_vertex_ids']=vertex_ids
        obj['source_polygon_ids']=indices
        obj['part']=name
        parts.append(obj)
    # Exact polygon corners and UVs survive the separation.
    assert sum(len(p.data.polygons) for p in parts)==len(mesh.data.polygons)
    for part in parts:
        for p,source_id in zip(part.data.polygons,part['source_polygon_ids']):
            old=mesh.data.polygons[source_id]
            for li,old_li in zip(p.loop_indices,old.loop_indices):
                a=part.data.vertices[part.data.loops[li].vertex_index].co
                b=mesh.data.vertices[mesh.data.loops[old_li].vertex_index].co
                assert a==b
                for uv,old_uv in zip(part.data.uv_layers,mesh.data.uv_layers): assert uv.data[li].uv==old_uv.data[old_li].uv
    return parts


def make_outline(part, normals, ink):
    outline=part.copy(); outline.data=part.data.copy()
    outline.name=part.name.replace('_Default','')+'_Outline'
    bpy.context.scene.collection.objects.link(outline)
    for v,old in zip(outline.data.vertices,part['source_vertex_ids']): v.co+=normals[old]*OUTLINE_WIDTH
    outline.data.flip_normals()
    outline.data.normals_split_custom_set([(0,0,0)]*len(outline.data.loops))
    outline.data.materials.clear(); outline.data.materials.append(ink)
    return outline


def validate(mesh, parts, rig, before):
    assert fingerprint(mesh.data)==before
    assert all(abs(sum(g.weight for g in v.groups)-1)<1e-6 and 1<=len(v.groups)<=4 for v in mesh.data.vertices)
    head=mesh.vertex_groups['head'].index
    for p in parts:
        if p.name in ['Face_Default','Head_Shell']:
            assert all(len(v.groups)==1 and v.groups[0].group==head and v.groups[0].weight==1 for v in p.data.vertices)
    report={'geometry_before':before,'geometry_after':fingerprint(mesh.data),'bones':len(rig.data.bones),
        'unweighted_vertices':0,'max_influences':max(len(v.groups) for v in mesh.data.vertices),
        'parts':{p.name:{'vertices':len(p.data.vertices),'polygons':len(p.data.polygons)} for p in parts},'clips':{}}
    for clip,period in PERIODS.items():
        rig.animation_data.action=bpy.data.actions[clip]
        ends=[]; floors=[]
        for frame in range(1,period+2):
            bpy.context.scene.frame_set(frame)
            ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); data=ev.to_mesh()
            points=[v.co.copy() for v in data.vertices]
            assert all(math.isfinite(c) for v in points for c in v)
            floors.append(min(v.z for v in points))
            if frame in [1,period+1]: ends.append(points)
            ev.to_mesh_clear()
        seam=max((a-b).length for a,b in zip(*ends))
        assert seam<1e-5 and max(abs(f) for f in floors)<1e-5,(clip,seam,min(floors),max(floors))
        report['clips'][clip]={'seconds':period/30,'loop_seam':seam,'floor_range':[min(floors),max(floors)]}
    rig.animation_data.action=bpy.data.actions['idle']; bpy.context.scene.frame_set(1)
    return report


def export(path, objects, parts, matte, base_hash, animations=True):
    old=[p.data.materials[0] for p in parts]
    for p in parts: p.data.materials[0]=matte
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    try:
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,
            export_yup=True,export_animations=animations,export_animation_mode='ACTIONS',export_frame_range=False,
            export_force_sampling=True,export_anim_slide_to_zero=True,export_skins=True,export_apply=False,
            export_rest_position_armature=True,export_optimize_animation_size=False,export_cameras=False,
            export_lights=False,export_image_format='AUTO',export_extras=False)
    finally:
        for p,mat in zip(parts,old): p.data.materials[0]=mat
    blob=path.read_bytes(); size=struct.unpack_from('<I',blob,12)[0]; doc=json.loads(blob[20:20+size])
    assert len(doc['skins'])==1 and len(doc['skins'][0]['joints'])==26
    if animations: assert {a['name'] for a in doc['animations']}==set(PERIODS)
    assert len(doc['images'])==1
    view=doc['bufferViews'][doc['images'][0]['bufferView']]; start=28+size+view.get('byteOffset',0)
    assert hashlib.sha256(blob[start:start+view['byteLength']]).hexdigest()==base_hash
    assert all('normalTexture' not in m for m in doc['materials'])
    return {'sha256':sha(path),'nodes':[n.get('name') for n in doc['nodes']]}


def render_previews(scene, original, rig, art):
    for target,view,clip,frame,label in [
        (original,'Standard',None,1,'original_standard'),(scene,'AgX','idle',1,'toon_agx'),
        (scene,'Standard','idle',1,'toon_standard'),(scene,'Standard','walk',9,'walk'),
        (scene,'Standard','run',6,'run')]:
        bpy.context.window.scene=target
        target.view_settings.view_transform=view
        target.view_settings.look='None'
        if clip: rig.animation_data.action=bpy.data.actions[clip]
        target.frame_set(frame)
        target.render.filepath=str(art/(label+'.png'))
        bpy.ops.render.render(write_still=True,scene=target.name)
    bpy.context.window.scene=scene
    scene.view_settings.view_transform='Standard'
    rig.animation_data.action=bpy.data.actions['idle']; scene.frame_set(1)
    # Review exactly which triangles will change when only the face is replaced.
    face=scene.objects['Face_Default']; previous=face.data.materials[0]
    mask=bpy.data.materials.new('QA_Face_Mask')
    nodes=mask.node_tree.nodes; nodes.clear()
    emission=nodes.new('ShaderNodeEmission'); emission.inputs['Color'].default_value=(.02,.8,.6,1)
    output=nodes.new('ShaderNodeOutputMaterial'); mask.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
    face.data.materials[0]=mask
    scene.render.filepath=str(art/'face_mask.png')
    bpy.ops.render.render(write_still=True,scene=scene.name)
    face.data.materials[0]=previous
    bpy.data.materials.remove(mask)


def build(key, render):
    source=ROOT/'assets/characters'/SOURCES[key]
    out=source.parent/'prepared'
    art=ROOT/'artifacts/tripo_roster'/key
    out.mkdir(parents=True,exist_ok=True); art.mkdir(parents=True,exist_ok=True)
    source_hash=sha(source)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.import_scene.gltf(filepath=str(source))
    original=bpy.context.scene; original.name='Original'
    original_mesh=next(o for o in original.objects if o.type=='MESH')
    original_mesh.name='Original_Body'
    original_mesh.data.name='Original_Mesh'
    original_mat=original_mesh.data.materials[0]; original_mat.name='Original'
    before=fingerprint(original_mesh.data)
    bsdf=next(n for n in original_mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    base=bsdf.inputs['Base Color'].links[0].from_node.image
    base_hash=hashlib.sha256(base.packed_file.data).hexdigest()
    image_hashes={i.name:hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.packed_file}
    scene=bpy.data.scenes.new('Toon'); bpy.context.window.scene=scene
    scene.render.engine=original.render.engine
    mesh=original_mesh.copy(); mesh.data=original_mesh.data.copy(); mesh.name='Working_Mesh'
    matrix=original_mesh.matrix_world.copy(); mesh.parent=None; mesh.matrix_world=matrix
    scene.collection.objects.link(mesh)
    toon,matte,ink=make_materials(base)
    mesh.data.materials.clear(); mesh.data.materials.append(toon)
    normals=angle_normals(mesh.data)
    rig=make_rig(mesh,key); animate(rig,mesh,key)
    parts=partition(mesh,key,base)
    outlines=[make_outline(p,normals,ink) for p in parts]
    report=validate(mesh,parts,rig,before)
    scene.collection.objects.unlink(mesh)
    bpy.data.objects.remove(mesh)
    light,camera=preview_scene(scene)
    # Same framing, key light and environment for a reproducible comparison.
    scene.render.resolution_x=560; scene.render.resolution_y=640
    original.world=scene.world; original.camera=camera
    original.collection.objects.link(light); original.collection.objects.link(camera)
    original.render.resolution_x=560; original.render.resolution_y=640
    original.render.resolution_percentage=100
    original.view_settings.view_transform='Standard'; original.view_settings.look='None'
    report.update({'source':str(source.relative_to(ROOT)).replace('\\','/'),'source_sha256':source_hash,
        'base_color_sha256':base_hash,'packed_images_sha256':image_hashes,'bands':BANDS,
        'normal_map':False,'normal_angle_degrees':32,'outline_width':OUTLINE_WIDTH,
        'original_rig_preserved':any(o.type=='ARMATURE' for o in original.objects)})
    report['export']=export(out/'character.glb',[rig]+parts+outlines,parts,matte,base_hash)
    face=next(p for p in parts if p.name=='Face_Default')
    face_outline=next(p for p in outlines if p.name=='Face_Outline')
    export(out/'face_default.glb',[rig,face,face_outline],[face],matte,base_hash,False)
    manifest={'version':1,'character':key,'bone':'head','mesh':'Face_Default','outline':'Face_Outline',
        'space':'Blender mesh-local Z-up / glTF mesh-local Y-up; keep the original origin and UV atlas',
        'source_vertex_ids':list(face['source_vertex_ids']),'source_polygon_ids':list(face['source_polygon_ids']),
        'base_color_sha256':base_hash,'head_rest_matrix':[list(r) for r in rig.data.bones['head'].matrix_local],
        'notes':'Skin-connected front patch with enclosed painted eyes and brows; hair stays on Head_Shell. Knight uses the replaceable front visor. Replacement must fit this character boundary; cross-character compatibility is not assumed.'}
    (out/'face_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    # Editable face boundary group for matching replacement meshes.
    edges={}
    for p in face.data.polygons:
        for edge in p.edge_keys: edges[edge]=edges.get(edge,0)+1
    boundary=sorted({v for edge,count in edges.items() if count==1 for v in edge})
    face['boundary_vertex_ids']=boundary
    scene['character']=key
    scene['README']='Toon: Eevee / Standard / 3 Constant bands. Original: untouched imported model, materials, normals and source rig. Actions: idle/walk/run. Face_Default and Face_Outline can be replaced together. Preserve boundary, UVs and rigid head weights.'
    scene['source_sha256']=source_hash
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active; enum(space.shading,'type','RENDERED')
                space.shading.use_scene_world_render=True; space.shading.use_scene_lights_render=True
                enum(space.region_3d,'view_perspective','CAMERA'); space.overlay.show_overlays=False
    if render: render_previews(scene,original,rig,art)
    bpy.context.window.scene=scene
    bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'character.blend'))
    assert sha(source)==source_hash
    assert image_hashes=={i.name:hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.packed_file}
    (out/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('ROSTER_DONE',key,json.dumps(report['parts']),flush=True)


def main():
    sys.stdout.reconfigure(line_buffering=True)
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',nargs='+',choices=list(SOURCES),default=list(SOURCES))
    parser.add_argument('--render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    for key in args.only: build(key,args.render)

if __name__=='__main__': main()
