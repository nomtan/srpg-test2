"""Phase 1.5: native proportions, semantic parts and source-derived motion.

Writes ONLY prepared/phase1_5 and artifacts/character_phase1_5.
The source rig/animation, raw and every previous prepared version are read-only.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT/'artifacts/character_phase1_5'
sys.path.insert(0,str(ROOT/'tools'))
from tripo_roster_common import preview_scene, smooth, blend

SOURCES = {'adventure':'tripo_adventure/adventure.glb',
           'knight':'tripo_knight2/knigth.glb', 'black_mage':'tripo_black_mage/black_mage.glb'}
PROFILES = {
    'adventure': {'head':.553, 'shoulder':(.19,.46), 'elbow':(.255,.39), 'wrist':(.31,.34),
                  'hip':.245,'knee':.13,'ankle':.06,'leg_x':.112,'boot':.145},
    'knight': {'head':.607, 'shoulder':(.185,.503), 'elbow':(.24,.438), 'wrist':(.304,.410),
               'hip':.209,'knee':.109,'ankle':.055,'leg_x':.109,'boot':.10},
    'black_mage': {'head':.478, 'shoulder':(.15,.365), 'elbow':(.20,.30), 'wrist':(.24,.255),
                   'hip':.175,'knee':.09,'ankle':.045,'leg_x':.095,'boot':.085},
}
TURN = Matrix.Rotation(math.pi,4,'Z')


def write_json(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')


def verify_protected():
    before=json.loads((ART/'protected_before.json').read_text())
    changed=[p for p,h in before.items() if not (ROOT/p).exists() or hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
    assert not changed, ('PROTECTED FILES CHANGED',changed)
    return len(before)


def activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj


def image_array(image):
    w,h=image.size
    data=np.empty(w*h*4,dtype=np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(h,w,4)


def hsv(rgb):
    r,g,b=rgb[...,0],rgb[...,1],rgb[...,2]
    hi=np.max(rgb[...,:3],axis=-1)
    lo=np.min(rgb[...,:3],axis=-1)
    d=hi-lo
    hue=np.zeros_like(hi)
    nz=d>1e-7
    for condition,value in [(hi==r,(g-b)/(d+1e-12)),(hi==g,2+(b-r)/(d+1e-12)),(hi==b,4+(r-g)/(d+1e-12))]:
        hue=np.where(nz&condition,value,hue)
    return (hue/6)%1, d/(hi+1e-12), hi


def sample_faces(mesh,pixels):
    uv=mesh.data.uv_layers.active.data
    h,w=pixels.shape[:2]
    centers=np.array([p.center[:] for p in mesh.data.polygons])
    colors=[]
    for p in mesh.data.polygons:
        coords=np.array([uv[i].uv[:] for i in p.loop_indices])
        center=coords.mean(axis=0)
        # Interior samples avoid bleeding across unrelated tightly packed islands.
        coords=np.concatenate((center[None,:],center[None,:]*.75+coords*.25))
        xy=np.clip((coords*[w,h]).astype(int),[0,0],[w-1,h-1])
        colors.append(np.median(pixels[xy[:,1],xy[:,0],:3],axis=0))
    return centers,np.array(colors)


def semantic_head(mesh,key,pixels):
    pos,rgb=sample_faces(mesh,pixels)
    x,y,z=pos.T
    r,g,b=rgb.T
    hue,sat,val=hsv(rgb)
    if key=='adventure':
        scarf=(r>g*2.2)&(b<r*.42)
        green=(hue>.17)&(hue<.40)&(sat>.12)
        selected=(z>.588)|((z>.544)&~scarf&~green)
    elif key=='knight':
        blue=(b>r*1.45)&(b>g*1.2)&(sat>.40)
        selected=(z>.614)|((z>.586)&~blue&(abs(x)<.19))
    else:
        hair=(r>b*1.20)&(g>b*1.03)&(b>r*.37)&(g>r*.59)&(val>.16)
        # The low side/back tresses belong to Head, not to the robe collar.
        purple=(hue>.64)&(hue<.90)&(sat>.18)
        side_tress=(z>.42)&(abs(x)>.105)&(abs(x)<.18)&((y<-.035)|(y>.045))&~purple
        low_tress=((z>.395)&((abs(x)>.11)|((y>.03)&(z>.442)))&hair)|side_tress
        face=(z>.465)&(y<-.055)&(abs(x)<.155)
        hat_edge=(z>.475)&(hue>.65)&(hue<.88)&((abs(x)>.18)|(abs(y)>.17))
        selected=(z>.475)|low_tress|face|hat_edge
    # Smooth only ambiguous boundary faces; preserve hard clothing-color vetoes.
    by_vertex={}
    for p in mesh.data.polygons:
        for i in p.vertices:
            co=tuple(round(c,6) for c in mesh.data.vertices[i].co)
            by_vertex.setdefault(co,[]).append(p.index)
    neighbors=[set() for _ in mesh.data.polygons]
    for faces in by_vertex.values():
        for i in faces: neighbors[i].update(faces)
    for _ in range(2):
        old=selected.copy()
        for i,nb in enumerate(neighbors):
            if z[i]<(.39 if key=='black_mage' else .54): continue
            fraction=sum(bool(old[j]) for j in nb)/len(nb)
            if fraction>.82: selected[i]=True
            elif fraction<.12: selected[i]=False
    return selected,pos,rgb


def split_semantic(mesh,selected):
    parts=[]
    for name,head in [('Body',False),('HeadBase',True)]:
        obj=mesh.copy()
        obj.data=mesh.data.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.name=name
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        remove=[f for f in bm.faces if bool(selected[f.index])!=head]
        bmesh.ops.delete(bm,geom=remove,context='FACES')
        loose=[v for v in bm.verts if not v.link_faces]
        if loose: bmesh.ops.delete(bm,geom=loose,context='VERTS')
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
        parts.append(obj)
    bpy.data.objects.remove(mesh,do_unlink=True)
    return parts


def native_rig(key):
    source=json.loads((ROOT/'assets/characters/_shared/master_rig/skeleton.json').read_text())
    p=PROFILES[key]
    arm=bpy.data.armatures.new('SemanticSkeleton')
    rig=bpy.data.objects.new('MasterRig',arm)
    bpy.context.scene.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    hip,knee,ankle=p['hip'],p['knee'],p['ankle']
    sx,sz=p['shoulder']; ex,ez=p['elbow']; wx,wz=p['wrist']
    chest=sz+.025
    upper_len=math.hypot(ex-sx,ez-sz)
    lower_len=math.hypot(wx-ex,wz-ez)
    points={'Root':((0,0,0),.06), 'Hips':((0,0,hip),.07),
            'Spine':((0,0,hip+.07),max(.035,chest-.06-hip-.07)),
            'Chest':((0,0,chest-.06),.06), 'Neck':((0,0,chest),p['head']-chest),
            'Head':((0,0,p['head']),.25),
            'Skirt_01':((0,-.095,hip+.06),.10), 'Skirt_02':((0,-.12,hip-.04),max(.03,hip-.11))}
    for side,sign in [('L',1),('R',-1)]:
        lx=p['leg_x']*sign
        points.update({
            'Shoulder_'+side:((sign*.065,0,chest),math.hypot(sx-.065,sz-chest)),
            'UpperArm_'+side:((sign*sx,0,sz),upper_len),
            'LowerArm_'+side:((sign*(sx+upper_len),0,sz),lower_len),
            'Hand_'+side:((sign*(sx+upper_len+lower_len),0,sz),.04),
            'UpperLeg_'+side:((lx,0,hip),hip-knee),
            'LowerLeg_'+side:((lx*1.07,-.005,knee),knee-ankle),
            'Foot_'+side:((lx*1.1,.005,ankle),.10),
            'Cape_01_'+side:((sign*.09,.085,chest),max(.06,chest-hip)),
            'Cape_02_'+side:((sign*.12,.13,hip),max(.06,hip-.10))})
    for item in source:
        bone=arm.edit_bones.new(item['name'])
        head,length=points[item['name']]
        matrix=Matrix(item['matrix'])
        matrix.translation=TURN@Vector(head)
        # Set a nonzero head/tail first: assigning matrix to a zero-length
        # EditBone otherwise silently loses its intended orientation.
        bone.head=matrix.translation
        bone.tail=matrix.translation+matrix.to_3x3()@Vector((0,length,0))
        bone.matrix=matrix
        bone.length=length
        bone.use_deform=item['name']!='Root'
        if item['parent']: bone.parent=arm.edit_bones[item['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones: pb.rotation_mode='QUATERNION'
    rig.show_in_front=True
    return rig


def natural_pose(rig,key):
    p=PROFILES[key]
    sx,sz=p['shoulder']; ex,ez=p['elbow']; wx,wz=p['wrist']
    upper=math.atan2(ez-sz,ex-sx)
    lower=math.atan2(wz-ez,wx-ex)
    for pb in rig.pose.bones:
        pb.rotation_quaternion=Quaternion()
        pb.location=(0,0,0)
    for side in ('L','R'):
        rig.pose.bones['UpperArm_'+side].rotation_quaternion=Quaternion((1,0,0),upper)
        rig.pose.bones['LowerArm_'+side].rotation_quaternion=Quaternion((1,0,0),lower-upper)
    bpy.context.view_layer.update()
    return upper,lower


def weights(body,key,pixels,rig):
    p=PROFILES[key]
    sx,sz=p['shoulder']; ex,ez=p['elbow']; wx,wz=p['wrist']
    hip,knee,ankle=p['hip'],p['knee'],p['ankle']
    old_groups=[g.name for g in body.vertex_groups]
    old_weights=[[(old_groups[g.group],g.weight) for g in v.groups] for v in body.data.vertices]
    body.vertex_groups.clear()
    for bone in rig.data.bones:
        if bone.use_deform: body.vertex_groups.new(name=bone.name)
    centers,colors=sample_faces(body,pixels)
    rgb=np.zeros((len(body.data.vertices),3))
    count=np.zeros(len(body.data.vertices))
    for f,c in zip(body.data.polygons,colors):
        for i in f.vertices: rgb[i]+=c; count[i]+=1
    rgb/=np.maximum(count[:,None],1)
    hue,sat,val=hsv(rgb)
    source_map={'Hips':'Hips','Spine':'Spine','Chest':'Chest','UpperChest':'Chest','Neck':'Neck','Head':'Neck','Neck_Twist_A':'Neck'}
    for prefix,side in [('Left_','L'),('Right_','R')]:
        for part in ['Shoulder','UpperArm','LowerArm','Hand','UpperLeg','LowerLeg','Foot']:
            source_map[prefix+part]=part+'_'+side
    result=[]
    for v in body.data.vertices:
        x,y,z=v.co
        ax=abs(x); side='L' if x>=0 else 'R'
        torso=blend({'Hips':1},{'Chest':1},smooth(hip+.055,sz-.045,z))
        h,s=hue[v.index],sat[v.index]
        cloth_color=((.16<h<.43 and s>.12) or ((h<.028 or h>.94) and s>.45)) if key=='adventure' else ((.53<h<.76 and s>.25) or (.035<h<.18 and s>.4 and val[v.index]>.48)) if key=='knight' else ((.64<h<.90) or (.035<h<.18 and s>.4 and val[v.index]>.48))
        robe=key=='black_mage' and z<hip+.10 and (cloth_color or (z>.04 and ax>.145) or (z>.06 and y<-.105 and ax<.07))
        coat=(.085<z<p['boot']+.035 and cloth_color and (abs(y)>.095 or ax>p['leg_x']+.035))
        leg=blend({'UpperLeg_'+side:1},{'LowerLeg_'+side:1},1-smooth(knee-.02,knee+.02,z))
        leg=blend(leg,{'Foot_'+side:1},1-smooth(ankle+.015,ankle+.045,z))
        influence=(1-smooth(hip-.055,hip+.015,z))*max(smooth(.025,.065,ax),1-smooth(hip-.12,hip-.065,z))
        w=blend(torso,leg,influence)
        if robe or coat:
            w=blend({'Skirt_01':1},torso,smooth(hip+.035,hip+.12,z))
        elif key=='black_mage' and z<hip+.07 and z>p['boot']:
            w={'Skirt_01':1}
        # Back cloth and the front tabard are never attached independently to legs.
        if key in ('adventure','knight'):
            back=smooth(.065,.105,y)*smooth(.075,.13,z)*(1-smooth(sz-.025,sz+.015,z))
            if back>0:
                cape=blend({'Cape_01_'+side:1},{'Cape_02_'+side:1},1-smooth(hip-.02,hip+.025,z))
                if ax<.05:
                    other='R' if side=='L' else 'L'
                    cape=blend({n.replace('_'+side,'_'+other):v for n,v in cape.items()},cape,.5+.5*smooth(0,.05,ax))
                w=blend(w,cape,back)
            if y<-.085 and z<hip+.075 and z>(.105 if key=='knight' else .17) and ax<.11:
                w={'Skirt_01':1}
        # Source Knight arm weights are valuable; retain them in the arm region.
        a=Vector((sx,0,sz)); e=Vector((ex,-.01,ez)); wrist=Vector((wx,-.025,wz))
        axis=(wrist-a).normalized()
        point=Vector((ax,y,z))
        along=(point-a).dot(axis)
        arm=blend({'UpperArm_'+side:1},{'LowerArm_'+side:1},smooth((e-a).length-.025,(e-a).length+.025,along))
        arm=blend(arm,{'Hand_'+side:1},smooth((wrist-a).length-.018,(wrist-a).length+.018,along))
        expected=sz+(ax-sx)*(wz-sz)/(wx-sx)
        arm_amount=smooth(sx-.055,sx-.01,ax)*(1-smooth(.075,.115,abs(z-expected)))
        arm_amount*=1-smooth(.085,.13,y)
        if key=='knight' and arm_amount>.1:
            transferred={}
            for name,weight in old_weights[v.index]:
                target=source_map.get(name)
                if target is None and name.startswith(('Left_','Right_')):
                    target='Hand_'+('L' if name.startswith('Left_') else 'R')
                if target and ('Arm_' in target or 'Hand_' in target or 'Shoulder_' in target):
                    transferred[target]=transferred.get(target,0)+weight
            if sum(transferred.values())>.3:
                total=sum(transferred.values())
                arm={n:a/total for n,a in transferred.items()}
        w=blend(w,arm,arm_amount)
        # Belt pouches are not sleeves even where their silhouettes touch.
        leather=(.025<h<.15 and s>.25 and rgb[v.index,2]<rgb[v.index,0]*.65)
        if leather and y<-.065 and z<hip+.16 and ax<sx+.055:
            w={'Hips':1}
        if z>sz+.035 and ax<.13: w={'Chest':1}
        result.append(w)
    # UV seam duplicates must have exactly equal weights, or animation opens cracks.
    groups={}
    for v in body.data.vertices:
        groups.setdefault(tuple(round(c,6) for c in v.co),[]).append(v.index)
    # Geodesic smoothing prevents hard spatial/color labels from becoming skin
    # discontinuities. Work on a position-welded graph but retain the mesh/UVs.
    names=[g.name for g in body.vertex_groups]
    columns={n:i for i,n in enumerate(names)}
    dense=np.zeros((len(groups),len(names)),dtype=np.float64)
    welded=np.zeros(len(body.data.vertices),dtype=np.int32)
    ids_list=list(groups.values())
    for row,ids in enumerate(ids_list):
        welded[ids]=row
        for i in ids:
            for n,w in result[i].items(): dense[row,columns[n]]+=w/len(ids)
    edges=np.array([(welded[e.vertices[0]],welded[e.vertices[1]]) for e in body.data.edges],dtype=np.int32)
    edges=np.unique(np.sort(edges,axis=1),axis=0)
    edges=edges[edges[:,0]!=edges[:,1]]
    degree=np.bincount(edges.reshape(-1),minlength=len(groups))
    for _ in range(18):
        sums=np.zeros_like(dense)
        np.add.at(sums,edges[:,0],dense[edges[:,1]])
        np.add.at(sums,edges[:,1],dense[edges[:,0]])
        dense=.45*dense+.55*sums/np.maximum(degree[:,None],1)
    for row,ids in enumerate(ids_list):
        entries=sorted(zip(names,dense[row]),key=lambda p:-p[1])[:4]
        total=sum(w for n,w in entries)
        for n,w in entries:
            if w>1e-6: body.vertex_groups[n].add(ids,w/total,'REPLACE')


def inverse_bind(body,rig,key):
    """Solve the T-rest mesh so the native A-pose reproduces every raw vertex.

    This changes only what is necessary for A->T. It never fits the torso,
    head or legs to the Master's proportions.
    """
    natural_pose(rig,key)
    transforms={b.name:rig.pose.bones[b.name].matrix @ b.matrix_local.inverted() for b in rig.data.bones}
    error=0.0
    movement=[]
    for v in body.data.vertices:
        raw=TURN@v.co
        matrix=Matrix(((0,0,0,0),)*4)
        for g in v.groups:
            matrix+=transforms[body.vertex_groups[g.group].name]*g.weight
        point=matrix.inverted()@raw
        error=max(error,(matrix@point-raw).length)
        movement.append((point-raw).length)
        v.co=point
    body.parent=rig
    body.matrix_world=Matrix.Identity(4)
    body.modifiers.clear()
    mod=body.modifiers.new('Semantic Skin','ARMATURE')
    mod.object=rig
    return error,movement


def neck_overlap(head,key,rig):
    # A hidden skin plug closes the join during head tilt and across bodies.
    p=PROFILES[key]
    z=p['head']
    mat=bpy.data.materials.new('NeckOverlapSkin')
    mat.diffuse_color=(.72,.47,.32,1)
    mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(.72,.47,.32,1)
    bsdf.inputs['Roughness'].default_value=1
    head.data.materials.append(mat)
    bm=bmesh.new()
    bm.from_mesh(head.data)
    # Weld only coincident seam duplicates to identify the actual cut boundary;
    # per-corner UVs are retained. Close the neck interior, not eyes or hat gaps.
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    boundary=[e for e in bm.edges if e.is_boundary and all(v.co.z<z+.075 for v in e.verts)]
    if boundary:
        caps=bmesh.ops.holes_fill(bm,edges=boundary,sides=0)['faces']
        head['neck_cap_faces']=len(caps)
        for face in caps: face.material_index=len(head.data.materials)-1
        bmesh.ops.recalc_face_normals(bm,faces=caps)
    bm.to_mesh(head.data)
    bm.free()
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=1,depth=1,location=(0,.015,z+.006))
    plug=bpy.context.object
    plug.name='NeckOverlap'
    plug.scale=(.07,.075,.042)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    plug.data.materials.append(mat)
    # The neck plug extends 15mm below the socket; body-specific offsets are zero.
    activate(head)
    plug.select_set(True)
    bpy.ops.object.join()
    head.parent=rig
    head.matrix_world=Matrix.Identity(4)
    head.vertex_groups.clear()
    head.vertex_groups.new(name='Head').add(list(range(len(head.data.vertices))),1,'REPLACE')
    head.modifiers.clear()
    mod=head.modifiers.new('Rigid Head','ARMATURE')
    mod.object=rig


def raster_regions(body,key,pixels,out):
    """UV-space semantic cloth masks; never select warm/gold colors as cloth."""
    size=1024
    regions=np.zeros((size,size),dtype=np.uint8)
    secondary_region=np.zeros((size,size),dtype=bool)
    caperegion=np.zeros((size,size),dtype=bool)
    cleanregion=np.zeros((size,size),dtype=bool)
    uv=body.data.uv_layers.active.data
    body.data.calc_loop_triangles()
    for tri in body.data.loop_triangles:
        center=sum((body.data.vertices[i].co for i in tri.vertices),Vector())/3
        x,y,z=center
        # These positions are still in the raw native A-pose coordinate system.
        label=1
        if key=='knight': label=2 if y<-.055 and z<.34 and abs(x)<.14 else 1
        if key=='black_mage': label=2 if z>.31 and (abs(x)>.12 or z>.405) else 1
        points=np.array([uv[i].uv[:] for i in tri.loops])*size-.5
        lo=np.maximum(np.floor(points.min(axis=0)).astype(int),0)
        hi=np.minimum(np.ceil(points.max(axis=0)).astype(int),size-1)
        if np.any(lo>hi): continue
        xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1))
        a,b,c=points
        den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-9: continue
        u=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
        v=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
        inside=(u>=-.015)&(v>=-.015)&(u+v<=1.015)
        regions[yy[inside],xx[inside]]=label
        if key=='adventure' and ((z>.49 and abs(x)<.20) or (y>.045 and z>.18)):
            secondary_region[yy[inside],xx[inside]]=True
        cape=key=='knight' and y>.075 and .065<z<.51 and abs(x)<(.12+.30*(.50-z))
        tabard=key=='knight' and y<-.075 and z<.32 and abs(x)<.115
        if cape: caperegion[yy[inside],xx[inside]]=True
        if cape or tabard: cleanregion[yy[inside],xx[inside]]=True
    # Sample at higher resolution but keep the original texture's color values.
    indices=np.minimum((np.arange(size)+.5)*pixels.shape[0]/size,pixels.shape[0]-1).astype(int)
    rgb=pixels[indices[:,None],indices[None,:],:3]
    hue,sat,val=hsv(rgb)
    if key=='adventure':
        primary=(hue>.11)&(hue<.43)&(sat>.10)&(rgb[...,1]>rgb[...,0]*.88)&(rgb[...,1]>rgb[...,2]*1.1)
        secondary=((hue>.94)|(hue<.028))&(sat>.45)&secondary_region
    elif key=='knight':
        blue=(hue>.53)&(hue<.76)&(sat>.38)
        primary=blue&(regions==1)
        secondary=blue&(regions==2)
    else:
        purple=(hue>.67)&(hue<.84)&(sat>.23)
        primary=purple&(regions==1)
        secondary=purple&(regions==2)
    mask=np.zeros((size,size,4),dtype=np.float32)
    mask[...,0]=primary&(regions>0)
    mask[...,1]=secondary&(regions>0)
    mask[...,3]=1
    def save(name,values,noncolor=True):
        h,w=values.shape[:2]
        image=bpy.data.images.new(name,width=w,height=h,alpha=True)
        if noncolor: image.colorspace_settings.name='Non-Color'
        image.pixels.foreach_set(values.astype(np.float32).reshape(-1))
        image.filepath_raw=str(out/(name+'.png'))
        image.file_format='PNG'
        image.save()
        image.pack()
        return image
    cleaned=None
    if key=='knight':
        # Remove every warm glyph inside the cloth panels, never armor/buckles.
        original_blue=(rgb[...,2]>rgb[...,0]*1.6)&(rgb[...,2]>rgb[...,1]*1.25)
        gold=~original_blue&cleanregion
        # Downsample coverage conservatively to the original albedo resolution.
        n=pixels.shape[0]
        factor=size//n
        safe=cleanregion.reshape(n,factor,n,factor).any(axis=(1,3))
        # Include the atlas gutter sampled by bilinear filtering at UV-island edges.
        # Without this padding the glyph survives as a one-pixel golden outline.
        for _ in range(2):
            safe=safe|np.roll(safe,1,0)|np.roll(safe,-1,0)|np.roll(safe,1,1)|np.roll(safe,-1,1)
        native_blue=(pixels[...,2]>pixels[...,0]*1.6)&(pixels[...,2]>pixels[...,1]*1.25)
        remove=safe&~native_blue
        for _ in range(2):
            remove=(remove|np.roll(remove,1,0)|np.roll(remove,-1,0)|np.roll(remove,1,1)|np.roll(remove,-1,1))&safe
        clean=pixels.copy()
        blue=native_blue&safe&~remove
        seed=np.median(pixels[blue,:3],axis=0)
        clean[remove,:3]=seed
        # Harmonic patch from nearby original cloth. Restrict the write to glyphs.
        # Clamp samples to the known cloth palette so nearby gold borders cannot bleed in.
        low=np.quantile(pixels[blue,:3],.12,axis=0)
        high=np.quantile(pixels[blue,:3],.88,axis=0)
        for _ in range(450):
            mean=(np.roll(clean[:,:,:3],1,0)+np.roll(clean[:,:,:3],-1,0)+np.roll(clean[:,:,:3],1,1)+np.roll(clean[:,:,:3],-1,1))*.25
            clean[remove,:3]=np.clip(mean[remove],low,high)
        cleaned=save('body_albedo_clean',clean,False)
        # Cleaned glyph texels are cloth too; include them in the palette mask.
        repaired=np.repeat(np.repeat(remove,factor,axis=0),factor,axis=1)
        mask[...,0]=np.maximum(mask[...,0],repaired&(regions==1))
        mask[...,1]=np.maximum(mask[...,1],repaired&(regions==2))
        cape=np.zeros_like(mask); cape[caperegion,:3]=1; cape[...,3]=1
        save('cape_mask',cape)
        write_json(out/'clean_albedo_audit.json',{'changed_pixels':int(remove.sum()),
            'method':'cloth-only harmonic patch from surrounding original blue; raw retained',
            'outside_selected_region_changed':bool(np.any(clean[~remove]!=pixels[~remove]))})
    save('palette_mask',mask)
    return cleaned,{'primary_pixels':int(mask[...,0].sum()),'secondary_pixels':int(mask[...,1].sum()),
                    'supports_emblem':key=='knight','resolution':[size,size]}


def extract_source():
    path=ROOT/'assets/characters/_shared/animations/common_combat.blend'
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    data={}
    for action in bpy.data.actions:
        rig.animation_data_create()
        rig.animation_data.action=action
        if action.slots: rig.animation_data.action_slot=action.slots[0]
        frames=[]
        for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
            bpy.context.scene.frame_set(frame)
            frames.append({pb.name:list(pb.matrix_basis.to_quaternion()) for pb in rig.pose.bones})
        data[action.name]=frames
    assert set(data)=={'idle','walk','attack_melee','cast_magic','hit'}
    write_json(ART/'master_motion.json',{'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'clips':data})
    return data


def retarget(rig,key,motion):
    upper,lower=natural_pose(rig,key)
    offsets={}
    for side in ('L','R'):
        offsets['UpperArm_'+side]=Quaternion((1,0,0),upper+math.radians(53))
        offsets['LowerArm_'+side]=Quaternion((1,0,0),lower-upper)
    rig.animation_data_create()
    actions={}
    for name,frames in motion.items():
        action=bpy.data.actions.new(name)
        action.use_fake_user=True
        action['source']='_shared/animations/common_combat.blend::'+name
        rig.animation_data.action=action
        for i,pose in enumerate(frames,1):
            for pb in rig.pose.bones:
                q=Quaternion(pose[pb.name])
                pb.rotation_quaternion=offsets.get(pb.name,Quaternion())@q
                pb.location=(0,0,0)
            bpy.context.view_layer.update()
            # Preserve each native foot's sole orientation. This is the same
            # rotation-only contact constraint for every body, not bespoke walks.
            for side in ('L','R'):
                pb=rig.pose.bones['Foot_'+side]
                desired=rig.data.bones[pb.name].matrix_local.copy()
                desired.translation=pb.matrix.translation
                pb.matrix=desired
            bpy.context.view_layer.update()
            for pb in rig.pose.bones:
                pb.keyframe_insert('rotation_quaternion',frame=i,group=pb.name)
        actions[name]=action
    rig.animation_data.action=None
    natural_pose(rig,key)
    return actions


def sockets(rig):
    result=[]
    for label,bone in [('HeadSocket','Head'),('WeaponSocket_R','Hand_R'),('WeaponSocket_L','Hand_L'),('BackSocket','Chest')]:
        obj=bpy.data.objects.new(label,None)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent=rig; obj.parent_type='BONE'; obj.parent_bone=bone
        obj.matrix_world=rig.matrix_world@rig.pose.bones[bone].matrix@Matrix.Rotation(-math.pi/2,4,'X')
        obj['bone']=bone
        obj.empty_display_size=.015
        result.append(obj)
    return result


def export(path,objects,animations=False,yup=True):
    assert 'phase1_5' in path.parts
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        use_active_scene=True,export_yup=yup,export_animations=animations,
        export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=True,
        export_anim_slide_to_zero=True,export_skins=True,export_apply=False,
        export_rest_position_armature=True,export_optimize_animation_size=False,
        export_cameras=False,export_lights=False,export_extras=True)
    if animations:
        import struct
        data=path.read_bytes()
        size=struct.unpack_from('<I',data,12)[0]
        document=json.loads(data[20:20+size])
        for animation in document['animations']:
            animation['channels']=[c for c in animation['channels'] if c['target']['path']=='rotation']
        encoded=json.dumps(document,separators=(',',':')).encode('utf-8')
        encoded+=b' '*((-len(encoded))%4)
        suffix=data[20+size:]
        path.write_bytes(struct.pack('<III',0x46546C67,2,20+len(encoded)+len(suffix))+
                         struct.pack('<II',len(encoded),0x4E4F534A)+encoded+suffix)


def render_preview(key,rig,body,head):
    preview_scene(bpy.context.scene)
    scene=bpy.context.scene
    scene.render.resolution_x=480; scene.render.resolution_y=560
    scene.camera.location=(0,3,.63)
    scene.camera.rotation_euler=(Vector((0,0,.49))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    mats=list(body.data.materials)+list(head.data.materials)
    for mat in set(mats):
        nodes,links=mat.node_tree.nodes,mat.node_tree.links
        output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
        bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        emit=nodes.new('ShaderNodeEmission')
        tex=next((n for n in nodes if n.type=='TEX_IMAGE'),None)
        if tex: links.new(tex.outputs['Color'],emit.inputs['Color'])
        else: emit.inputs['Color'].default_value=bsdf.inputs['Base Color'].default_value
        links.new(emit.outputs[0],output.inputs['Surface'])
    for part in ['assembled','body','head']:
        body.hide_render=part=='head'; head.hide_render=part=='body'
        scene.render.filepath=str(ART/(key+'_'+part+'_preview.png'))
        bpy.ops.render.render(write_still=True)
    body.hide_render=head.hide_render=False


def build(key,motion):
    raw=ROOT/'assets/characters'/SOURCES[key]
    out=raw.parent/'prepared/phase1_5'
    out.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.import_scene.gltf(filepath=str(raw))
    mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
    for obj in list(bpy.context.scene.objects):
        if obj!=mesh: bpy.data.objects.remove(obj,do_unlink=True)
    mesh.parent=None; mesh.matrix_world=Matrix.Identity(4); mesh.modifiers.clear()
    image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE')
    pixels=image_array(image)
    selected,positions,colors=semantic_head(mesh,key,pixels)
    write_json(out/'semantic_selection.json',{'head_source_face_indices':np.flatnonzero(selected).tolist(),
        'rule_version':1,'source_sha256':hashlib.sha256(raw.read_bytes()).hexdigest()})
    body,head=split_semantic(mesh,selected)
    body.data.materials[0]=body.data.materials[0].copy()
    clean,palette=raster_regions(body,key,pixels,out)
    if clean:
        for node in body.data.materials[0].node_tree.nodes:
            if node.type=='TEX_IMAGE': node.image=clean
    rig=native_rig(key)
    weights(body,key,pixels,rig)
    silhouette_error,movement=inverse_bind(body,rig,key)
    head.data.transform(TURN)
    neck_overlap(head,key,rig)
    actions=retarget(rig,key,motion)
    # Emblem UV derived in native body space, without changing albedo UV.
    uv2=body.data.uv_layers.new(name='EmblemUV')
    for loop in body.data.loops:
        co=body.data.vertices[loop.vertex_index].co
        uv2.data[loop.index].uv=(.5-co.x/.30,(co.z-.115)/.30)
    body.data.uv_layers.active_index=0
    # Export sockets in rest to avoid baking a current animation offset into them.
    for pb in rig.pose.bones: pb.rotation_quaternion=Quaternion()
    bpy.context.view_layer.update()
    sock=sockets(rig)
    scene=bpy.context.scene
    scene.render.fps=30
    (out/'animations').mkdir(exist_ok=True)
    export(out/'body.glb',[rig,body]+sock)
    export(out/'animations/common_combat.glb',[rig],animations=True)
    # Save the authoring master with the native source pose displayed.
    natural_pose(rig,key)
    for img in bpy.data.images:
        if img.has_data and not img.packed_file: img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'character.blend'))
    # Rigid head is bone-local; no second world-up conversion is applied.
    temp=head.copy(); temp.data=head.data.copy()
    bpy.context.scene.collection.objects.link(temp)
    temp.name='HeadSet'
    temp.modifiers.clear(); temp.parent=None; temp.matrix_world=Matrix.Identity(4)
    temp.data.transform(rig.data.bones['Head'].matrix_local.inverted())
    temp.vertex_groups.clear()
    export(out/'head_default.glb',[temp],yup=False)
    bpy.data.objects.remove(temp,do_unlink=True)
    bones=[{'name':b.name,'parent':b.parent.name if b.parent else None,
            'head':list(b.head_local),'tail':list(b.tail_local),'matrix':[list(r) for r in b.matrix_local]}
            for b in rig.data.bones]
    result={'source_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),
        'skeleton_strategy':'native bind; shared names, hierarchy and axes',
        'source_pose_reconstruction_max_error_m':silhouette_error,
        'a_to_t_only_max_displacement_m':max(movement),
        'body_vertices':len(body.data.vertices),'head_vertices':len(head.data.vertices),
        'body_triangles':sum(len(p.vertices)-2 for p in body.data.polygons),
        'head_triangles':sum(len(p.vertices)-2 for p in head.data.polygons),
        'bones':bones,'head_socket_native_height':PROFILES[key]['head'],
        'neck_overlap_m':.015,'combination_offsets':{},'palette':palette,
        'supports_emblem':key=='knight','retargeted_clips':list(actions),
        'animation_source_sha256':hashlib.sha256((ROOT/'assets/characters/_shared/animations/common_combat.blend').read_bytes()).hexdigest(),
        'acceptance':'pending visual and runtime verification'}
    write_json(out/'validation.json',result)
    render_preview(key,rig,body,head)
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',nargs='+',choices=list(SOURCES))
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    verify_protected()
    motion=extract_source()
    results=json.loads((ART/'build.json').read_text()) if (ART/'build.json').exists() else {}
    results.update({key:build(key,motion) for key in (args.only or SOURCES)})
    write_json(ART/'build.json',results)
    print('PHASE1_5_BUILD_COMPLETE; protected files:',verify_protected(),flush=True)


if __name__=='__main__': main()
