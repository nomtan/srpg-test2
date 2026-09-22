"""Three-character pilot. Raw and legacy prepared files are never overwritten.

Run inspection first, then Blender --background --python this_file.py.
Outputs use prepared/phase1/; all five Actions live in the shared library only.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from inspect_tripo_roster import SOURCES
from prepare_tripo_roster import make_rig, PROFILES
from tripo_roster_common import preview_scene, smooth, blend

ART = ROOT / 'artifacts/character_phase1'
SHARED = ROOT / 'assets/characters/_shared'
KEYS = ('adventure', 'knight', 'black_mage')
RENAME = {'root': 'Root', 'pelvis': 'Hips', 'spine': 'Spine', 'chest': 'Chest',
          'neck': 'Neck', 'head': 'Head', 'tabard': 'Skirt_01', 'tabard_tip': 'Skirt_02'}
for side in ('L', 'R'):
    for old, new in [('clavicle', 'Shoulder'), ('upper_arm', 'UpperArm'),
                     ('forearm', 'LowerArm'), ('hand', 'Hand'), ('thigh', 'UpperLeg'),
                     ('shin', 'LowerLeg'), ('foot', 'Foot'), ('cape', 'Cape_01'),
                     ('cape_tip', 'Cape_02')]:
        RENAME[old+'.'+side] = new+'_'+side


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def rename_rig(rig, mesh):
    for old, new in RENAME.items():
        rig.data.bones[old].name = new
        if mesh.vertex_groups.get(old):
            mesh.vertex_groups[old].name = new
    rig.name = 'MasterRig'
    rig.data.name = 'MasterSkeleton'


def skeleton_spec(rig):
    return [{'name': b.name, 'parent': b.parent.name if b.parent else None,
             'head': list(b.head_local), 'tail': list(b.tail_local),
             'matrix': [list(r) for r in b.matrix_local], 'deform': b.use_deform}
            for b in rig.data.bones]


def create_rig(spec):
    arm = bpy.data.armatures.new('MasterSkeleton')
    rig = bpy.data.objects.new('MasterRig', arm)
    bpy.context.scene.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for item in spec:
        b = arm.edit_bones.new(item['name'])
        b.head, b.tail = item['head'], item['tail']
        b.matrix = Matrix(item['matrix'])
        b.length = (Vector(item['tail'])-Vector(item['head'])).length
        b.use_deform = item['deform']
        if item['parent']:
            b.parent = arm.edit_bones[item['parent']]
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.show_in_front = True
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
    return rig


def export(path, objects, animations=False, yup=True):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        use_active_scene=True, export_yup=yup, export_animations=animations,
        export_animation_mode='ACTIONS', export_frame_range=False, export_force_sampling=True,
        export_anim_slide_to_zero=True, export_skins=True, export_apply=False,
        export_rest_position_armature=True, export_optimize_animation_size=False,
        export_cameras=False, export_lights=False, export_extras=True)


def sockets(rig):
    result = []
    for name, bone in [('HeadSocket','Head'), ('WeaponSocket_R','Hand_R'),
                       ('WeaponSocket_L','Hand_L'), ('BackSocket','Chest')]:
        obj = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = rig
        obj.parent_type = 'BONE'
        obj.parent_bone = bone
        # glTF's ordinary-node Y-up conversion differs from bone-local frames.
        # Cancel it so the delivered socket has identity relative to its bone.
        obj.matrix_world = rig.matrix_world @ rig.data.bones[bone].matrix_local @ Matrix.Rotation(-math.pi/2,4,'X')
        obj['bone'] = bone
        obj.empty_display_size = .025
        result.append(obj)
    return result


def make_master():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/characters'/SOURCES['adventure']))
    mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
    rig = make_rig(mesh, 'adventure')
    rename_rig(rig, mesh)
    rig.matrix_world = Matrix.Identity(4)
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for side, sign in [('L',1), ('R',-1)]:
        upper = rig.data.edit_bones['UpperArm_'+side]
        lower = rig.data.edit_bones['LowerArm_'+side]
        hand = rig.data.edit_bones['Hand_'+side]
        lengths = [b.length for b in (upper, lower, hand)]
        start = upper.head.copy()
        for b, length in zip((upper, lower, hand), lengths):
            b.head = start
            b.tail = start+Vector((sign*length,0,0))
            b.roll = 0
            start = b.tail.copy()
    # Blender Z-up / +Y front exports to glTF Y-up / -Z front.
    turn = Matrix.Rotation(math.pi, 4, 'Z')
    for b in rig.data.edit_bones:
        b.transform(turn)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.data.objects.remove(mesh, do_unlink=True)
    spec = skeleton_spec(rig)
    sock = sockets(rig)
    out = SHARED/'master_rig'
    out.mkdir(parents=True, exist_ok=True)
    write_json(out/'skeleton.json', spec)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'master_rig.blend'))
    export(out/'master_rig.glb', [rig]+sock)
    return spec


def transfer_knight(mesh, original_weights):
    def target(name):
        if name in ('Hips','Spine','Chest','Neck','Head'):
            return name
        if name == 'UpperChest': return 'Chest'
        if 'Eye' in name or 'Neck_Twist' in name: return 'Head'
        for prefix, side in [('Left_', 'L'), ('Right_', 'R')]:
            if name.startswith(prefix):
                part = name[len(prefix):]
                if part in ('Shoulder','UpperArm','LowerArm','Hand','UpperLeg','LowerLeg','Foot'):
                    return part+'_'+side
                if part.startswith('Toes'): return 'Foot_'+side
                return 'Hand_'+side
        raise ValueError('Unmapped source bone '+name)
    # Preserve the existing skin; fold unsupported fingers/twists into their parent.
    spatial = [{mesh.vertex_groups[g.group].name:g.weight for g in v.groups} for v in mesh.data.vertices]
    mesh.vertex_groups.clear()
    for name in RENAME.values():
        if name != 'Root': mesh.vertex_groups.new(name=name)
    for v, entries, fallback in zip(mesh.data.vertices, original_weights, spatial):
        weights = {}
        for name, w in entries:
            n = target(name)
            weights[n] = weights.get(n,0)+w
        if not weights: weights = fallback
        # Keep the source's cape/skirt attached to its torso, avoiding leg splitting.
        cloth = {n:w for n,w in fallback.items() if n.startswith(('Cape_', 'Skirt_'))}
        amount = sum(cloth.values())
        if amount > .05:
            weights = {n:w*(1-amount) for n,w in weights.items()}
            for n,w in cloth.items(): weights[n] = weights.get(n,0)+w
        items = sorted(weights.items(),key=lambda p:-p[1])[:4]
        total = sum(w for n,w in items)
        for n,w in items:
            if w>0: mesh.vertex_groups[n].add([v.index], w/total, 'REPLACE')


def split_at_neck(mesh, height):
    parts = []
    for name, clear_inner, clear_outer in [('Body',False,True), ('HeadBase',True,False)]:
        obj = mesh.copy()
        obj.data = mesh.data.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.name = name
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
            dist=1e-7, plane_co=(0,0,height), plane_no=(0,0,1),
            clear_inner=clear_inner, clear_outer=clear_outer)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
        parts.append(obj)
    bpy.data.objects.remove(mesh, do_unlink=True)
    return parts


def raster_masks(body, image, key, out):
    """Rasterize conservative clothing labels in original UVs, not a global hue shift."""
    width, height = image.size
    pixels = np.empty(width*height*4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(height,width,4)
    mask = np.zeros_like(pixels)
    cape = np.zeros_like(pixels)
    uv = body.data.uv_layers.active.data
    body.data.calc_loop_triangles()
    # Geometry is canonical, front +Y. Exclude hands and the neck/skin boundary.
    for tri in body.data.loop_triangles:
        coords = [body.data.vertices[i].co for i in tri.vertices]
        center = sum(coords, Vector())/3
        if center.z > .53 or center.z < .10 or abs(center.x) > .24:
            continue
        points = np.array([uv[i].uv[:] for i in tri.loops])*[width,height]-.5
        lo = np.maximum(np.floor(points.min(axis=0)).astype(int),0)
        hi = np.minimum(np.ceil(points.max(axis=0)).astype(int),[width-1,height-1])
        if np.any(lo>hi): continue
        xx,yy = np.meshgrid(np.arange(lo[0],hi[0]+1),np.arange(lo[1],hi[1]+1))
        a,b,c = points
        den = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(den)<1e-9: continue
        u = ((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
        v = ((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den
        inside = (u>=0)&(v>=0)&(u+v<=1)
        rgb = pixels[yy,xx,:3]
        r,g,b = rgb[...,0],rgb[...,1],rgb[...,2]
        if key == 'adventure':
            primary = (g>r*.88)&(g>b*1.10)&(r<b*2.3)
            secondary = (r>g*1.65)&(r>b*1.35)
        elif key == 'knight':
            primary = (b>r*1.25)&(b>g*1.06)
            secondary = (r>b*1.65)&(g>b*1.10)&(r>g*1.04)
        else:
            primary = (b>g*1.25)&(b>r*.90)
            secondary = (r>b*1.65)&(g>b*1.05)&(r>g*1.02)
        # Warm skin and hair are excluded geometrically: hands, head and upper neck.
        mask[yy[inside&primary],xx[inside&primary],0] = 1
        mask[yy[inside&secondary],xx[inside&secondary],1] = 1
        if key in ('adventure','knight') and center.y < -.105 and .16<center.z<.44:
            cape[yy[inside],xx[inside],:3] = 1
    mask[...,3] = 1
    cape[...,3] = 1
    counts = [int(np.count_nonzero(mask[...,i])) for i in range(3)]
    assert min(counts[:2])>100, (key,counts)
    def save(name, values):
        tex = bpy.data.images.new(name, width=width, height=height, alpha=True)
        tex.colorspace_settings.name = 'Non-Color'
        tex.pixels.foreach_set(values.reshape(-1))
        tex.filepath_raw = str(out/(name+'.png'))
        tex.file_format = 'PNG'
        tex.save()
        tex.pack()
    save('palette_mask', mask)
    if key in ('adventure','knight'): save('cape_mask', cape)
    return {'resolution':[width,height], 'channel_pixels':counts,
            'cape_pixels':int(np.count_nonzero(cape[...,0])),
            'method':'conservative UV triangle raster + clothing color labels; visual review required'}


def build_character(key, spec):
    source = ROOT/'assets/characters'/SOURCES[key]
    out = source.parent/'prepared/phase1'
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    mesh = max((o for o in bpy.context.scene.objects if o.type=='MESH'), key=lambda o:len(o.data.vertices))
    original_weights = [[(mesh.vertex_groups[g.group].name,g.weight) for g in v.groups] for v in mesh.data.vertices]
    for obj in list(bpy.context.scene.objects):
        if obj != mesh: bpy.data.objects.remove(obj, do_unlink=True)
    mesh.parent = None
    mesh.matrix_world = Matrix.Identity(4)
    image = next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE')
    image_hash = hashlib.sha256(image.packed_file.data).hexdigest()
    original_count = len(mesh.data.vertices)
    fitted = make_rig(mesh, key)
    rename_rig(fitted, mesh)
    if key == 'knight': transfer_knight(mesh, original_weights)
    else:
        # The legacy spatial fallback lets rear glove/sleeve vertices pick up
        # cape/torso weights. Keep each arm cross-section together before fitting.
        neck, shoulder, elbow, wrist, _, _, _ = PROFILES[key]
        a = Vector((shoulder[0], 0, shoulder[1]))
        e = Vector((elbow[0], -.01, elbow[1]))
        w = Vector((wrist[0], -.025, wrist[1]))
        axis = (w-a).normalized()
        for v in mesh.data.vertices:
            x,y,z = v.co
            ax = abs(x)
            expected_z = shoulder[1]+(ax-shoulder[0])*(wrist[1]-shoulder[1])/(wrist[0]-shoulder[0])
            if ax < shoulder[0]-.045 or z >= neck-.035 or abs(z-expected_z)>.15:
                continue
            side = 'L' if x>=0 else 'R'
            along = (Vector((ax,y,z))-a).dot(axis)
            arm = blend({'UpperArm_'+side:1},{'LowerArm_'+side:1},smooth((e-a).length-.018,(e-a).length+.018,along))
            arm = blend(arm,{'Hand_'+side:1},smooth((w-a).length-.012,(w-a).length+.012,along))
            old = {mesh.vertex_groups[g.group].name:g.weight for g in v.groups}
            weights = blend(old,arm,smooth(shoulder[0]-.045,shoulder[0]-.01,ax))
            for group in mesh.vertex_groups: group.remove([v.index])
            entries = sorted(weights.items(),key=lambda p:-p[1])[:4]
            total = sum(w for n,w in entries)
            for n,weight in entries:
                if weight>0: mesh.vertex_groups[n].add([v.index],weight/total,'REPLACE')
    master = create_rig(spec)
    # Transfer into a single exact bind/rest skeleton, including A -> T pose.
    matrices = {b.name:master.data.bones[b.name].matrix_local @ b.matrix_local.inverted()
                for b in fitted.data.bones}
    displacements = []
    turned = Matrix.Rotation(math.pi,4,'Z')
    for v in mesh.data.vertices:
        before = v.co.copy()
        co = Vector()
        for g in v.groups:
            co += (matrices[mesh.vertex_groups[g.group].name] @ before)*g.weight
        displacements.append((co-turned@before).length)
        v.co = co
    # Correct only the boot contact band; leave the common skeleton untouched.
    floor = min(v.co.z for v in mesh.data.vertices)
    for v in mesh.data.vertices:
        amount = max(0.0, min(1.0, (.10-v.co.z)/.04))
        v.co.z -= floor*amount
    mesh.parent = master
    mesh.matrix_world = Matrix.Identity(4)
    mesh.modifiers[0].object = master
    bpy.data.objects.remove(fitted, do_unlink=True)
    master.name = 'MasterRig'
    master.data.name = 'MasterSkeleton'
    # Rigid head preserves face/hair shape; the shared cut is hidden by the collars.
    seam = .55
    for v in mesh.data.vertices:
        if v.co.z >= seam-.006:
            for group in mesh.vertex_groups: group.remove([v.index])
            mesh.vertex_groups['Head'].add([v.index],1,'REPLACE')
    body, head = split_at_neck(mesh, seam)
    # UV2 provides an emblem projection, leaving the original albedo UV unchanged.
    uv2 = body.data.uv_layers.new(name='EmblemUV')
    for loop in body.data.loops:
        p = body.data.vertices[loop.vertex_index].co
        uv2.data[loop.index].uv = (.5-p.x/.30, (p.z-.17)/.27)
    body.data.uv_layers.active_index = 0
    palette = raster_masks(body, image, key, out)
    sock = sockets(master)
    master['coordinate_contract'] = 'Blender Z-up/+Y front; glTF and Godot Y-up/-Z front'
    head['attachment'] = 'HeadSocket; rigid Head-local geometry in head_default.glb'
    for obj in (body,head):
        obj['phase1_status'] = 'pilot_requires_visual_acceptance'
    for img in bpy.data.images:
        if img.has_data and not img.packed_file: img.pack()
    # Save editable master without duplicating any animation Actions.
    preview_scene(bpy.context.scene)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'character.blend'))
    export(out/'body.glb', [master,body]+sock)
    # Rigid mesh in Head bone local coordinates: one Skeleton3D in runtime assembly.
    head.modifiers.clear()
    head.parent = None
    head.matrix_world = Matrix.Identity(4)
    head.data.transform(master.data.bones['Head'].matrix_local.inverted())
    head.vertex_groups.clear()
    # Bone-local coordinates have their own basis. Applying the world Z->Y
    # conversion a second time here rotates the face through the neck in Godot.
    export(out/'head_default.glb', [head], yup=False)
    result = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'source_image_sha256': image_hash, 'source_vertices':original_count,
              'body_vertices':len(body.data.vertices), 'head_vertices':len(head.data.vertices),
              'body_triangles':sum(len(p.vertices)-2 for p in body.data.polygons),
              'head_triangles':sum(len(p.vertices)-2 for p in head.data.polygons),
              'materials':1, 'bones':len(master.data.bones), 'seam_blender_z':seam,
              'fit_displacement_max':max(displacements),
              'fit_displacement_mean':sum(displacements)/len(displacements),
              'palette':palette, 'actions_in_character':len(bpy.data.actions),
              'weight_source':'existing Tripo + local cloth correction' if key=='knight' else 'spatial fallback (raw has no rig)',
              'status':'structural pilot; see visual acceptance report'}
    write_json(out/'validation.json',result)
    return result


def animations(spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rig = create_rig(spec)
    rig.animation_data_create()
    scene = bpy.context.scene
    scene.render.fps = 30
    for name, period in [('idle',60),('walk',30),('attack_melee',36),('cast_magic',48),('hit',24)]:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame in range(1,period+2):
            t = (frame-1)/period
            swing = math.sin(t*2*math.pi)
            pulse = math.sin(t*math.pi)**2
            for pb in rig.pose.bones:
                pb.rotation_mode = 'XYZ'
                pb.rotation_euler = (0,0,0)
                pb.location = (0,0,0)
            # All animations start from a relaxed stance, not the T bind pose.
            for side, sign in [('L',1),('R',-1)]:
                rig.pose.bones['UpperArm_'+side].rotation_euler.x = -math.radians(53)
            if name == 'idle':
                rig.pose.bones['Chest'].rotation_euler.x = .015*swing
                rig.pose.bones['Head'].rotation_euler.z = .025*swing
            elif name == 'walk':
                for side, sign in [('L',1),('R',-1)]:
                    rig.pose.bones['UpperLeg_'+side].rotation_euler.x = sign*.24*swing
                    rig.pose.bones['LowerLeg_'+side].rotation_euler.x = -.20*max(0,-sign*swing)
                    rig.pose.bones['UpperArm_'+side].rotation_euler.z = sign*.20*swing
            elif name == 'attack_melee':
                rig.pose.bones['UpperArm_R'].rotation_euler.z = -1.0*pulse
                rig.pose.bones['LowerArm_R'].rotation_euler.z = -.65*pulse
                rig.pose.bones['Chest'].rotation_euler.y = .20*math.sin(t*2*math.pi)
            elif name == 'cast_magic':
                for side, sign in [('L',1),('R',-1)]:
                    rig.pose.bones['UpperArm_'+side].rotation_euler.x *= 1-.6*pulse
                    rig.pose.bones['UpperArm_'+side].rotation_euler.z = sign*.60*pulse
                    rig.pose.bones['LowerArm_'+side].rotation_euler.z = sign*.45*pulse
            else:
                rig.pose.bones['Chest'].rotation_euler.x = -.18*pulse
                rig.pose.bones['Head'].rotation_euler.x = -.10*pulse
            for pb in rig.pose.bones:
                pb.keyframe_insert('rotation_euler', frame=frame, group=pb.name)
        action['loop'] = name in ('idle','walk')
    rig.animation_data.action = None
    for pb in rig.pose.bones: pb.rotation_euler = (0,0,0)
    scene.frame_set(1)
    out = SHARED/'animations'
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'common_combat.blend'))
    export(out/'common_combat.glb', [rig], animations=True)


def main():
    inspection = json.loads((ART/'inspection.json').read_text(encoding='utf-8'))
    for key in KEYS:
        source = ROOT/'assets/characters'/SOURCES[key]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == inspection[key]['sha256']
    spec = make_master()
    results = {key:build_character(key,spec) for key in KEYS}
    animations(spec)
    write_json(ART/'build.json', results)
    print('PHASE1_BUILD_COMPLETE', flush=True)


if __name__ == '__main__':
    main()
