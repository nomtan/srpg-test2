"""Rigs the Tripo dragon (assets/characters/tripo/enemy/dragon/model2.glb, never overwritten) into
assets/characters/enemy/dragon/model.glb.

The source is a static upright red dragon with raised wings, 0.735 tall, facing -Y in Blender (+Z in
glTF, like the roster). This script
- welds the UV-seam splits (UVs are per loop, so nothing visible changes),
- deletes the stray extra foot Tripo left standing behind the right hind leg (a loose piece on the
  ground, separate from the body),
- fits a dragon skeleton to the mesh (spine, neck, head, six tail bones, four three-bone legs and two
  wings of upper arm, forearm and four fingers), measured from orthographic views and slices,
- weights every vertex to its nearest bones by distance to the bone's surface, only on its own side,
  then smooths the weights over the mesh so joints bend softly,
- keys the clips idle (looping breath, neck and tail sway, wing drift) and roar (rears back, roars,
  beats its wings twice).
The GLB keeps Tripo's size; the Godot scene scales it.

Usage:
    blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_dragon.py
    (add -- --preview <dir> to render a contact sheet of every clip, --no-export to skip the GLB)
"""
import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Quaternion, Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'assets/characters/tripo/enemy/dragon/model2.glb'
OUT = ROOT / 'assets/characters/enemy/dragon/model.glb'
FPS = 30


def mirror(p):
    return (-p[0], p[1], p[2])


# --- Skeleton (source units, Blender axes: head toward -Y, left wing at +X). ---------------------
# (name, head, tail, parent, surface radius used for weighting)
TRUNK = [
    ('Hips', (0, .02, .24), (0, -.08, .26), None, .085),
    ('Spine', (0, -.08, .26), (0, -.18, .29), 'Hips', .09),
    ('Chest', (0, -.18, .29), (0, -.235, .35), 'Spine', .075),
    ('Neck1', (0, -.235, .35), (0, -.245, .41), 'Chest', .045),
    ('Neck2', (0, -.245, .41), (0, -.26, .47), 'Neck1', .04),
    ('Head', (0, -.26, .47), (0, -.39, .49), 'Neck2', .04),
]
TAIL = [(0, .02, .24), (.03, .09, .17), (.10, .19, .10), (.19, .29, .055), (.27, .355, .06), (.305, .38, .11), (.28, .355, .155)]
TAIL_R = [.06, .045, .03, .022, .016, .012]
# Legs: shoulder/hip, elbow/knee, wrist/ankle, toe tip. The right legs stand further forward.
LEGS = {
    'Front.L': ([(.07, -.17, .29), (.08, -.185, .17), (.062, -.235, .06), (.07, -.31, .01)], 'Chest'),
    'Front.R': ([(-.075, -.205, .29), (-.087, -.23, .17), (-.072, -.285, .06), (-.085, -.36, .01)], 'Chest'),
    'Hind.L': ([(.065, -.01, .25), (.085, -.05, .15), (.10, .035, .06), (.12, -.03, .01)], 'Hips'),
    'Hind.R': ([(-.065, -.06, .25), (-.07, -.11, .15), (-.077, -.05, .06), (-.08, -.12, .01)], 'Hips'),
}
LEG_R = [.04, .028, .02]
WING_ROOT, WING_ELBOW, WING_WRIST = (.07, -.17, .38), (.19, -.05, .51), (.266, 0, .715)
WING_TIPS = [(.454, .277, .565), (.48, .304, .43), (.454, .34, .168), (.30, .154, .178)]


def bones():
    out = list(TRUNK)
    for i in range(len(TAIL) - 1):
        out.append((f'Tail{i + 1}', TAIL[i], TAIL[i + 1], 'Hips' if i == 0 else f'Tail{i}', TAIL_R[i]))
    for leg, (points, parent) in LEGS.items():
        kind, tag = leg.split('.')
        names = [f'{kind}Upper.{tag}', f'{kind}Lower.{tag}', f'{kind}Foot.{tag}']
        for i, name in enumerate(names):
            out.append((name, points[i], points[i + 1], parent if i == 0 else names[i - 1], LEG_R[i]))
    for tag, side in (('L', lambda p: p), ('R', mirror)):
        out.append((f'WingUpper.{tag}', side(WING_ROOT), side(WING_ELBOW), 'Chest', .025))
        out.append((f'WingFore.{tag}', side(WING_ELBOW), side(WING_WRIST), f'WingUpper.{tag}', .015))
        for i, tip in enumerate(WING_TIPS):
            out.append((f'Finger{i + 1}.{tag}', side(WING_WRIST), side(tip), f'WingFore.{tag}', .006))
    return out


BONES = bones()


# --- Source clean-up --------------------------------------------------------------------------

def islands(bm):
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen: continue
        stack, ids = [v], []
        seen.add(v.index)
        while stack:
            a = stack.pop()
            ids.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        out.append(ids)
    return sorted(out, key=len, reverse=True)


def import_source():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    obj = next(o for o in bpy.data.objects if o.type == 'MESH')
    obj.data.transform(obj.matrix_world)
    obj.parent = None
    obj.matrix_world.identity()
    for o in list(bpy.data.objects):
        if o != obj: bpy.data.objects.remove(o)
    obj.name = obj.data.name = 'Dragon'
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bm.verts.ensure_lookup_table()
    # The stray foot: the only loose piece besides the body that reaches the ground.
    strays = [ids for ids in islands(bm)[1:] if min(v.co.z for v in ids) < .01 and len(ids) > 20]
    assert len(strays) == 1, f'expected one stray foot, found {len(strays)}'
    lo = np.min([v.co[:] for v in strays[0]], 0)
    hi = np.max([v.co[:] for v in strays[0]], 0)
    print('STRAY_FOOT removed', len(strays[0]), 'verts, bounds', lo.round(3), hi.round(3))
    bmesh.ops.delete(bm, geom=strays[0], context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons: p.use_smooth = True
    return obj


# --- Rig and weights ----------------------------------------------------------------------------

def build_armature():
    arm = bpy.data.armatures.new('DragonRig')
    rig = bpy.data.objects.new('DragonRig', arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for name, head, tail, parent, _ in BONES:
        b = arm.edit_bones.new(name)
        b.head, b.tail = head, tail
        b.roll = 0
        if parent:
            b.parent = arm.edit_bones[parent]
            b.use_connect = (Vector(head) - arm.edit_bones[parent].tail).length < 1e-6
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def segment_distances(co, a, b):
    ab = b - a
    t = np.clip(((co - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(co - (a + t[:, None] * ab), axis=1)


def skin(obj, rig, smooth_steps=6):
    mesh = obj.data
    co = np.array([v.co[:] for v in mesh.vertices])
    names = [b[0] for b in BONES]
    # Distance from each vertex to each bone's surface; a bone of the other side is out of reach.
    dist = np.empty((len(co), len(BONES)))
    for j, (name, head, tail, _, radius) in enumerate(BONES):
        d = segment_distances(co, np.array(head), np.array(tail)) - radius
        if name.endswith('.L'): d[co[:, 0] < -.01] = np.inf
        if name.endswith('.R'): d[co[:, 0] > .01] = np.inf
        dist[:, j] = np.maximum(d, .002)
    w = dist ** -4
    # Keep the three nearest bones per vertex.
    cut = np.sort(w, axis=1)[:, -3][:, None]
    w[w < cut] = 0
    w /= w.sum(1, keepdims=True)
    # Smooth over the mesh (Laplacian on edges) so bends blend across the joints.
    edges = np.array([e.vertices[:] for e in mesh.edges])
    count = np.bincount(edges.ravel(), minlength=len(co)).astype(float)[:, None]
    for _ in range(smooth_steps):
        acc = np.zeros_like(w)
        np.add.at(acc, edges[:, 0], w[edges[:, 1]])
        np.add.at(acc, edges[:, 1], w[edges[:, 0]])
        w = .5 * w + .5 * np.where(count > 0, acc / np.maximum(count, 1), w)
    w[w < .01] = 0
    w /= w.sum(1, keepdims=True)
    for j, name in enumerate(names):
        group = obj.vertex_groups.new(name=name)
        for i in np.nonzero(w[:, j])[0]:
            group.add([int(i)], float(w[i, j]), 'REPLACE')
    mod = obj.modifiers.new('Armature', 'ARMATURE')
    mod.object = rig
    obj.parent = rig


# --- Clips --------------------------------------------------------------------------------------
# A pose maps a bone to a rotation vector in armature space (axis * radians, applied in the bone's
# rest frame on top of its parent), plus 'Hips@loc', an armature-space offset of the whole body.
# +X tips forward-pointing bones down (head, chest), -X lifts them. Clips are written for the left
# wing; the right one mirrors it. Keys are baked from these FK poses with the feet held by IK.

# The wing plane's normal: turning the forearm about -n folds the wrist in toward the body, the
# fingers about +n close the fan behind it (a bat-like zig-zag).
_A = np.array(WING_WRIST) - np.array(WING_ROOT)
_F = np.array(WING_TIPS[2]) - np.array(WING_WRIST)
WING_NORMAL = np.cross(_A, _F) / np.linalg.norm(np.cross(_A, _F))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def mirror_rotation(v):
    """A rotation vector reflected across the YZ plane (left wing to right)."""
    return (v[0], -v[1], -v[2])


def add(*poses):
    out = {}
    for pose in poses:
        for k, v in pose.items():
            out[k] = tuple(a + b for a, b in zip(out.get(k, (0, 0, 0)), v))
    return out


def scale(pose, s):
    return {k: tuple(c * s for c in v) for k, v in pose.items()}


def blend(a, b, t):
    return add(scale(a, 1 - t), scale(b, t))


def body_only(pose):
    return {k: v for k, v in pose.items() if not k.startswith(('Wing', 'Finger'))}


def wing(raise_=0.0, fold=0.0, fore_raise=0.0, tip_raise=0.0, spread=0.0):
    """Both wings. raise_ lifts the whole wing about the body's long axis (+ up); fold folds the
    elbow and closes the fan (+ folded, - stretched); fore_raise / tip_raise lift the forearm /
    fingers on top (for lead and lag); spread fans the fingers apart."""
    n = WING_NORMAL
    left = {
        'WingUpper.L': tuple(np.array((0, -raise_, 0)) - n * fold * .25),
        'WingFore.L': tuple(np.array((0, -fore_raise, 0)) - n * fold * .9),
    }
    for i in range(1, 5):
        left[f'Finger{i}.L'] = tuple(np.array((0, -tip_raise * (.6 + .15 * i), 0))
            + n * (fold * (.2 + .14 * i) - spread * (i - 2.5) * .12))
    pose = dict(left)
    for k, v in left.items():
        pose[k[:-1] + 'R'] = mirror_rotation(v)
    return pose


FOLDED = wing(raise_=-.42, fold=.95)
SPREAD = wing(raise_=.5, fold=-.1, spread=.3)

# Standing pose: body low and pitched forward, the neck pushed forward and curving back up so the
# head hangs low and level like a stalking predator, tail lowered, wings half-folded at its sides.
CROUCH = add({
    'Hips@loc': (0, -.005, -.03), 'Hips': (.1, 0, 0), 'Spine': (.12, 0, 0), 'Chest': (.1, 0, 0),
    'Neck1': (.62, 0, 0), 'Neck2': (-.12, 0, 0), 'Head': (-.42, 0, 0),
    'Tail1': (-.16, 0, 0), 'Tail2': (.04, 0, 0), 'Tail3': (.05, 0, 0),
}, FOLDED)


def idle(frame, frames):
    """Breathing (chest swells, body lifts a little), a slow look to each side with the head
    leading the neck, a lazy tail swish and wings resettling with each breath."""
    t = 2 * math.pi * frame / frames
    b = math.sin(2 * t)  # two breaths per loop
    pose = {
        'Hips@loc': (0, 0, .002 * b), 'Chest': (-.025 * b, 0, 0), 'Spine': (-.01 * b, 0, 0),
        'Neck1': (.03 * math.sin(2 * t + .6), 0, .12 * math.sin(t - .5)),
        'Neck2': (0, 0, .12 * math.sin(t - .25)), 'Head': (-.03 * b, 0, .16 * math.sin(t)),
    }
    for i in range(6):
        pose[f'Tail{i + 1}'] = (.01 * math.sin(2 * t - i), 0, .09 * math.sin(t - .6 * i - .8))
    return add(CROUCH, pose, wing(raise_=.025 * b, fold=-.04 * b))


def stroke(p):
    """Wing height over a beat from the top: down fast (40%), back up slower."""
    p %= 1.0
    if p < .4: return .5 - 1.05 * smooth(p / .4)
    return -.55 + 1.05 * smooth((p - .4) / .6)


def beat(phase):
    """One wingbeat: a hard downstroke on the stretched wing, then the upstroke with the elbow
    folded and the fan closed, the wrist leading and the tips trailing. Returns the wing pose and
    the lift (+ while the downstroke pushes the body up)."""
    p = phase % 1.0
    up = p >= .4
    fold = .65 * math.sin(math.pi * (p - .4) / .6) if up else -.12 * math.sin(math.pi * p / .4)
    lead = stroke(phase + .06) - stroke(phase)
    lag = stroke(phase - .1) - stroke(phase)
    lift = -.35 * math.sin(math.pi * (p - .4) / .6) if up else math.sin(math.pi * p / .4)
    return wing(raise_=stroke(phase), fold=fold, fore_raise=.5 * lead, tip_raise=.9 * lag, spread=0 if up else .4), lift


def lift_body(lift, lift_late):
    """The body answering a beat: lifted on the downstroke with the chest rising, the neck holding
    the head steady against it, the tail swinging after."""
    pose = {'Hips@loc': (0, 0, .008 * lift), 'Chest': (-.05 * lift, 0, 0), 'Spine': (-.02 * lift, 0, 0),
        'Neck1': (.06 * lift, 0, 0), 'Head': (.04 * lift, 0, 0)}
    for i in range(1, 7):
        pose[f'Tail{i}'] = (-.035 * lift_late, 0, 0)
    return pose


# Raised for display: chest up, neck straightened, head lifted, wings opened wide above the back.
RISE = {'Hips@loc': (0, .005, .012), 'Hips': (-.08, 0, 0), 'Spine': (-.1, 0, 0), 'Chest': (-.12, 0, 0),
    'Neck1': (-.4, 0, 0), 'Neck2': (.05, 0, 0), 'Head': (.25, 0, 0), 'Tail1': (.06, 0, 0)}


def flap(frame, frames):
    """Rises, opens the wings and gives three full beats, then settles back into its crouch."""
    rest = body_only(idle(0, 1))
    start, period, end = 24, 36, 24 + 3 * 36
    risen = smooth(frame / start) * (1 - smooth((frame - end) / (frames - end)))
    lift = late = 0.0
    if frame < start:
        wings_pose = blend(FOLDED, SPREAD, smooth(frame / start))
    elif frame < end:
        wings_pose, lift = beat((frame - start) / period)
        late = beat((frame - start) / period - .15)[1]
    else:
        wings_pose = blend(SPREAD, FOLDED, smooth((frame - end) / (frames - end)))
    return add(rest, scale(RISE, risen), wings_pose, lift_body(lift, late))


# Roar: crouches and draws the head back, rears up with the wings flung open, then thrusts the head
# forward and down at the foe, holding it with a shudder while the wings stay spread.
COIL = {'Hips@loc': (0, .006, -.012), 'Chest': (.06, 0, 0), 'Neck1': (-.25, 0, 0), 'Neck2': (.15, 0, 0),
    'Head': (.2, 0, 0), 'Tail2': (-.04, 0, .05)}
REAR = add(RISE, {'Neck1': (-.15, 0, 0), 'Head': (-.15, 0, 0), 'Tail2': (-.06, 0, 0), 'Tail3': (-.08, 0, 0)})
THRUST = {'Hips@loc': (0, -.012, -.004), 'Hips': (.04, 0, 0), 'Spine': (.06, 0, 0), 'Chest': (.1, 0, 0),
    'Neck1': (.28, 0, 0), 'Neck2': (.15, 0, 0), 'Head': (.05, 0, 0), 'Tail2': (-.1, 0, .1), 'Tail3': (-.1, 0, .14)}
ROAR_KEYS = [(0, {}), (16, COIL), (34, REAR), (40, REAR), (48, THRUST), (100, THRUST)]


def roar(frame, frames):
    keys = ROAR_KEYS + [(frames, {})]
    body = keys[-1][1]
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            body = blend(a, b, smooth((frame - f0) / (f1 - f0)))
            break
    held = smooth((frame - 48) / 6) * (1 - smooth((frame - 96) / 6))
    tremble = .03 * math.sin(frame * 1.7) * held
    shake = .05 * math.sin(frame * 2.3) * held
    # Wings: folded, flung open on the rear, held spread and trembling, then folded away.
    opened = smooth((frame - 18) / 18) * (1 - smooth((frame - 104) / (frames - 104)))
    wings_pose = blend(FOLDED, wing(raise_=.32 + tremble, fold=-.15, tip_raise=-2 * tremble, spread=.4), opened)
    return add(body_only(idle(0, 1)), body, {'Head': (0, 0, shake), 'Neck2': (0, 0, -.5 * shake)}, wings_pose)


CLIPS = [('idle', 150, idle), ('roar', 140, roar), ('flap', 170, flap)]


def setup_leg_ik(rig):
    """Holds each foot where it stands: IK on the shin reaching the ankle, the foot keeping its rest
    orientation, so the body can crouch and heave while the legs bend under it."""
    targets = []
    for leg in LEGS:
        kind, tag = leg.split('.')
        foot, lower = f'{kind}Foot.{tag}', f'{kind}Lower.{tag}'
        target = bpy.data.objects.new(f'IK_{foot}', None)
        bpy.context.scene.collection.objects.link(target)
        target.matrix_world = rig.matrix_world @ rig.data.bones[foot].matrix_local
        ik = rig.pose.bones[lower].constraints.new('IK')
        ik.target = target
        ik.chain_count = 2
        rig.pose.bones[foot].constraints.new('COPY_ROTATION').target = target
        targets.append(target)
    return targets


def apply_pose(rig, pose):
    for p in rig.pose.bones:
        rest = p.bone.matrix_local.to_quaternion()
        vec = Vector(pose.get(p.name, (0, 0, 0)))
        q = Quaternion(vec.normalized(), vec.length) if vec.length > 1e-6 else Quaternion()
        p.rotation_quaternion = rest.inverted() @ q @ rest
        p.location = rest.inverted() @ Vector(pose.get(p.name + '@loc', (0, 0, 0)))


def create_animations(rig):
    """Poses every frame with the leg IK live, records each bone's resulting local transform, then
    drops the IK and keys those transforms (only plain keys reach the GLB)."""
    scene = bpy.context.scene
    scene.render.fps = FPS
    rig.animation_data_create()
    for p in rig.pose.bones:
        p.rotation_mode = 'QUATERNION'
    targets = setup_leg_ik(rig)
    baked = {}
    for name, frames, pose_at in CLIPS:
        baked[name] = []
        for frame in range(frames + 1):
            apply_pose(rig, pose_at(frame, frames))
            bpy.context.view_layer.update()
            baked[name].append({p.name: rig.convert_space(pose_bone=p, matrix=p.matrix, from_space='POSE', to_space='LOCAL')
                for p in rig.pose.bones})
    for p in rig.pose.bones:
        for c in list(p.constraints): p.constraints.remove(c)
    for target in targets: bpy.data.objects.remove(target)
    for name, frames, _ in CLIPS:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        previous = {}
        for frame, matrices in enumerate(baked[name]):
            for p in rig.pose.bones:
                p.matrix_basis = matrices[p.name]
                q = p.rotation_quaternion.copy()
                if p.name in previous and previous[p.name].dot(q) < 0: q.negate()
                p.rotation_quaternion = previous[p.name] = q
                p.keyframe_insert('rotation_quaternion', frame=frame + 1, group=p.name)
                p.keyframe_insert('location', frame=frame + 1, group=p.name)
    rig.animation_data.action = bpy.data.actions['idle']
    scene.frame_set(1)


def export(rig, mesh):
    OUT.parent.mkdir(parents=True, exist_ok=True)
    rig['looping_clips'] = ['idle']
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(OUT), use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False, export_extras=True, export_yup=True)
    print('DRAGON_EXPORT', OUT)


def preview(rig, directory):
    """Rows: idle over its loop, roar (coil, rear, thrust, hold) and one wingbeat of flap (rising,
    downstroke, bottom, folded upstroke), from the front-left above and from the side."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    size = 360
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.world = bpy.data.worlds.new('PreviewWorld')
    scene.world.color = (.75, .75, .75)
    camera = bpy.data.objects.new('PreviewCamera', bpy.data.cameras.new('PreviewCamera'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 1.15
    target = Vector((0, 0, .38))
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    samples = {'idle': [0, 38, 75, 112, 150], 'roar': [0, 16, 36, 60, 120], 'flap': [12, 31, 38, 46, 53]}
    rows = []
    for view in ((-.7, -1, .45), (1, 0, .1)):
        direction = Vector(view).normalized()
        camera.location = target + direction * 4
        camera.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
        for name, _, _ in CLIPS:
            rig.animation_data.action = bpy.data.actions[name]
            row = []
            for frame in samples[name]:
                scene.frame_set(1 + frame)
                path = directory / '_frame.png'
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                image = bpy.data.images.load(str(path))
                row.append(np.array(image.pixels[:]).reshape(size, size, 4))
                bpy.data.images.remove(image)
            rows.append(np.concatenate(row, axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)
    image = bpy.data.images.new('sheet', sheet.shape[1], sheet.shape[0])
    image.pixels[:] = sheet.ravel()
    image.filepath_raw = str(directory / 'dragon_clips.png')
    image.file_format = 'PNG'
    image.save()
    print('PREVIEW', directory / 'dragon_clips.png')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--preview')
    parser.add_argument('--no-export', action='store_true')
    args = parser.parse_args(argv)
    mesh = import_source()
    rig = build_armature()
    skin(mesh, rig)
    create_animations(rig)
    if not args.no_export: export(rig, mesh)
    if args.preview: preview(rig, args.preview)


main()
