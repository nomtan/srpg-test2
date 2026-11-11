"""Rigs a whole-character Tripo model (one static T-pose mesh, not the Body + Face standard).

Source (never overwritten): assets/characters/tripo/characters/<id>/model.glb
Output: assets/characters/standalone/<id>/model.glb, with a skeleton of its own fitted to the
model (not humanoid_v1) and the in-place clips idle, walk and run. No weapon sockets.

    blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_rigged_character.py -- --id test --preview artifacts/rigged_character_preview

Blender axes: the character faces -Y, its left is +X, up is +Z. Pose angles are radians about the
armature axes (see build_enemy.py): +X pitches an upward bone forward and swings a downward bone
back, +Z turns toward the character's left.
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_enemy as be  # noqa: E402

ROOT = be.ROOT
FPS = be.FPS
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)

# Bone: (head, tail, parent, distance radius). Root is the non-deforming ground pivot. The cape
# and the tabard hang from chains of their own so the legs do not drag the cloth.
TEST_BONES = {
    'Root': ((0, -.03, 0), (0, -.03, .15), None, None),
    'Hips': ((0, -.03, .47), (0, -.035, .54), 'Root', .07),
    'Spine': ((0, -.035, .54), (0, -.04, .62), 'Hips', .07),
    'Chest': ((0, -.04, .62), (0, -.035, .74), 'Spine', .08),
    'Neck': ((0, -.035, .74), (0, -.035, .79), 'Chest', .03),
    'Head': ((0, -.035, .79), (0, -.035, .97), 'Neck', .08),
    'LeftShoulder': ((.03, -.01, .71), (.12, 0, .715), 'Chest', .03),
    'LeftArm': ((.12, 0, .715), (.26, .03, .695), 'LeftShoulder', .035),
    'LeftForeArm': ((.26, .03, .695), (.39, .048, .677), 'LeftArm', .03),
    'LeftHand': ((.39, .048, .677), (.485, .06, .677), 'LeftForeArm', .025),
    'RightShoulder': ((-.03, -.01, .71), (-.12, 0, .715), 'Chest', .03),
    'RightArm': ((-.12, 0, .715), (-.26, .03, .695), 'RightShoulder', .035),
    'RightForeArm': ((-.26, .03, .695), (-.39, .048, .677), 'RightArm', .03),
    'RightHand': ((-.39, .048, .677), (-.485, .06, .677), 'RightForeArm', .025),
    'LeftUpLeg': ((.09, -.03, .46), (.10, -.04, .27), 'Hips', .05),
    'LeftLeg': ((.10, -.04, .27), (.095, -.02, .06), 'LeftUpLeg', .04),
    'LeftFoot': ((.095, -.02, .06), (.095, -.13, .01), 'LeftLeg', .03),
    'RightUpLeg': ((-.09, -.03, .46), (-.10, -.04, .27), 'Hips', .05),
    'RightLeg': ((-.10, -.04, .27), (-.095, -.02, .06), 'RightUpLeg', .04),
    'RightFoot': ((-.095, -.02, .06), (-.095, -.13, .01), 'RightLeg', .03),
    'Cape1': ((0, .07, .62), (0, .09, .43), 'Chest', None),
    'Cape2': ((0, .09, .43), (0, .11, .24), 'Cape1', None),
    'Cape3': ((0, .11, .24), (0, .13, .05), 'Cape2', None),
    'Tabard1': ((0, -.12, .44), (0, -.125, .25), 'Hips', None),
    'Tabard2': ((0, -.125, .25), (0, -.13, .04), 'Tabard1', None),
}

CHARACTERS = {
    'test': {
        'bones': TEST_BONES,
        # Above head_full everything is Head; from head_blend it blends in within head_reach of the
        # centre line (the hood).
        'head_blend': .76, 'head_full': .81, 'head_reach': .14,
        # Between `floor` and `top`: the cape is everything behind `back_y`, plus what lies beyond
        # `side_x` and further than `leg_radius` from its side's leg; the tabard is what hangs in
        # front of `front_y` within `tabard_x` of the centre line, away from the legs.
        'cloth': {'top': .64, 'blend': .08, 'floor': .065, 'leg_radius': .085, 'back_y': .04, 'front_y': -.085,
                  'tabard_x': .075, 'side_x': .18, 'cape': ['Cape1', 'Cape2', 'Cape3'], 'tabard': ['Tabard1', 'Tabard2']},
        'preview': {'scale': 1.25, 'target': (0, 0, .5)},
    },
}


# --- Mesh and skin ----------------------------------------------------------------------------

def import_source(character_id):
    source = ROOT / f'assets/characters/tripo/characters/{character_id}/model.glb'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    assert len(meshes) == 1, f'expected one mesh, got {[o.name for o in meshes]}'
    mesh = meshes[0]
    mesh.data.transform(mesh.matrix_world)
    mesh.matrix_world = Matrix.Identity(4)
    mesh.name = mesh.data.name = character_id
    return mesh


def chain_weights(z, bones, names, chain):
    """Weights along a hanging chain by height: each bone holds its own span, eased across joints."""
    rows = np.zeros((len(z), len(names)))
    joints = [bones[b][0][2] for b in chain[1:]]
    index = np.zeros(len(z))
    for joint in joints:
        index += np.clip((joint + .04 - z) / .08, 0, 1)
    for k, bone in enumerate(chain):
        rows[:, names.index(bone)] = np.clip(1 - np.abs(index - k), 0, 1)
    return rows


def skin(mesh, rig, spec):
    bones = spec['bones']
    names = [n for n, b in bones.items() if b[2] is not None]
    body = [n for n in names if bones[n][3] is not None]
    co = np.array([v.co[:] for v in mesh.data.vertices])
    d = np.full((len(co), len(names)), np.inf)
    for name in body:
        head, tail, _, radius = bones[name]
        dist = be.segment_distance(co, np.array(head), np.array(tail))
        # Limb bones only reach across the centre line reluctantly.
        side = 1 if name.startswith('Left') else -1 if name.startswith('Right') else 0
        if side:
            dist += np.maximum(0, -side * co[:, 0] + .02) * 4
        d[:, names.index(name)] = np.maximum(dist - radius, .005)
    w = d ** -4
    w[w < np.sort(w, axis=1)[:, -4:-3]] = 0
    w /= w.sum(1, keepdims=True)

    head = np.zeros(len(names))
    head[names.index('Head')] = 1
    z, reach = co[:, 2], np.abs(co[:, 0]) < spec['head_reach']
    t = np.clip((z - spec['head_blend']) / (spec['head_full'] - spec['head_blend']), 0, 1)
    t = np.where(z >= spec['head_full'], 1, np.where(reach, t * t * (3 - 2 * t), 0))
    w = w * (1 - t[:, None]) + head * t[:, None]

    cloth = spec['cloth']
    leg_distance = np.full(len(co), np.inf)
    for side, sign in (('Left', 1), ('Right', -1)):
        mine = co[:, 0] * sign >= 0
        for part in ('UpLeg', 'Leg', 'Foot'):
            a, b = bones[side + part][0], bones[side + part][1]
            # Horizontal distance: the armour plates sit on the leg at any height.
            flat = np.linalg.norm(co[:, :2] - np.array(a[:2]), axis=1) if part != 'Foot' else be.segment_distance(co, np.array(a), np.array(b))
            leg_distance = np.where(mine, np.minimum(leg_distance, flat), leg_distance)
    loose = (leg_distance > cloth['leg_radius']) & (z > cloth['floor']) & (z < cloth['top'])
    # Only the hanging tabard is loose in front; the cuirass and tassets around it stay on the body.
    front = loose & (co[:, 1] < cloth['front_y']) & (np.abs(co[:, 0]) < cloth['tabard_x']) & (z < bones[cloth['tabard'][0]][0][2] + .02)
    # The cape hangs behind the body and wraps around its sides.
    back = (z < cloth['top']) & ((co[:, 1] > cloth['back_y']) | (loose & (np.abs(co[:, 0]) > cloth['side_x']) & (co[:, 1] > cloth['front_y'])))
    # The cloth eases onto its chain below `top`, so it stays attached to the torso above.
    ease = np.clip((cloth['top'] - z) / cloth['blend'], 0, 1)
    ease = (ease * ease * (3 - 2 * ease))[:, None]
    cape = chain_weights(z, bones, names, cloth['cape'])
    tabard = chain_weights(z, bones, names, cloth['tabard'])
    w[back] = w[back] * (1 - ease[back]) + cape[back] * ease[back]
    w[front] = tabard[front]
    print('Cloth: cape', int(back.sum()), 'tabard', int(front.sum()), 'of', len(co))

    # Tripo meshes are many loose islands; smoothing across a small radius keeps neighbours together.
    kd = KDTree(len(co))
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    near = [[j for _, j, _ in kd.find_range(p, .02)] for p in co]
    for _ in range(3):
        w = np.array([w[n].mean(0) for n in near])
    w[w < .01] = 0
    w[w < np.sort(w, axis=1)[:, -4:-3]] = 0
    w /= w.sum(1, keepdims=True)
    for k, name in enumerate(names):
        group = mesh.vertex_groups.new(name=name)
        for i in np.nonzero(w[:, k])[0]:
            group.add([int(i)], float(w[i, k]), 'REPLACE')
    mesh.parent = rig
    modifier = mesh.modifiers.new('Armature', 'ARMATURE')
    modifier.object = rig
    feet = w[:, [names.index(n) for n in names if n.endswith(('Foot', 'Leg'))]].sum(1) > .6
    print('Skinned', len(co), 'vertices to', len(names), 'bones')
    return np.nonzero(feet)[0]


# --- Clips ------------------------------------------------------------------------------------

def rot(axis, angle):
    return Quaternion(axis, angle)


def arms(pose, swing_left, swing_right, down, elbow_left, elbow_right, forward=0.0):
    """Arms lowered from the T-pose by `down`, swung about the shoulders (+ is back), elbows bent."""
    pose['LeftArm'] = rot(X, swing_left) @ rot(Z, -forward) @ rot(Y, down)
    pose['RightArm'] = rot(X, swing_right) @ rot(Z, forward) @ rot(Y, -down)
    # The elbow hinges about the rest pose's vertical, which the lowered arm carries to face forward.
    pose['LeftForeArm'] = rot(Z, -elbow_left)
    pose['RightForeArm'] = rot(Z, elbow_right)
    pose['LeftHand'] = rot(Z, -.12)
    pose['RightHand'] = rot(Z, .12)


def idle(frame, frames):
    phase = 2 * math.pi * frame / frames
    w, c = math.sin(phase), math.cos(phase)
    pose = {'loc': (0, 0, -.004 * (1 - c)), 'Spine': (.012 * w, 0, 0), 'Chest': (.02 * w, 0, 0),
            'Neck': (-.01 * w, 0, 0), 'Head': (-.02 * w, 0, .03 * math.sin(phase + 1)),
            'LeftUpLeg': (-.012 * (1 - c), 0, 0), 'LeftLeg': (.03 * (1 - c), 0, 0), 'LeftFoot': (-.018 * (1 - c), 0, 0),
            'RightUpLeg': (-.012 * (1 - c), 0, 0), 'RightLeg': (.03 * (1 - c), 0, 0), 'RightFoot': (-.018 * (1 - c), 0, 0),
            'Cape1': (.02 + .015 * w, 0, .01 * math.sin(phase + .6)), 'Cape2': (.02 * math.sin(phase - .8), 0, 0),
            'Cape3': (.03 * math.sin(phase - 1.6), 0, 0), 'Tabard1': (.01 * w, 0, 0), 'Tabard2': (.02 * math.sin(phase - .8), 0, 0)}
    arms(pose, .02 * w, .02 * w, 1.16 + .01 * w, .22, .22, .06)
    return pose


# amplitude/bias: thigh swing and its forward offset. knee: stance bend, extra bend in the swing.
# lean: torso pitch. yaw: pelvis turn with the leading leg. arm: swing. down/elbow: arm carriage.
# cape: how far the cape streams back, and its flutter. hop: flight height (run only).
WALK = {'amplitude': .42, 'bias': .03, 'knee': (.08, .85), 'knee_lag': .35, 'toe': (.22, .32), 'lean': .03, 'yaw': .07,
        'roll': .03, 'arm': .38, 'arm_bias': .05, 'down': 1.2, 'elbow': (.3, .25), 'cape': (.1, .05), 'tabard': (.1, .06),
        'hop': 0.0, 'head': -.02}
RUN = {'amplitude': .6, 'bias': .16, 'knee': (.18, 1.4), 'knee_lag': .45, 'toe': (.1, .5), 'lean': .17, 'yaw': .1,
       'roll': .03, 'arm': .55, 'arm_bias': 0.0, 'down': 1.3, 'elbow': (1.2, .2), 'cape': (.2, .06), 'tabard': (.25, .08),
       'hop': .035, 'head': -.12}


def gait(style):
    """A stride starting at the left heel strike, like the humanoid_v1 gait clips."""
    def pose_at(frame, frames):
        phase = 2 * math.pi * frame / frames
        c, s = math.cos(phase), math.sin(phase)
        lean, yaw = style['lean'], style['yaw'] * c
        # Each side's leg leads at its own heel strike: left at 0, right half a stride later.
        pose = {'Hips': (lean * .25, style['roll'] * s, -yaw), 'Spine': (lean * .4, 0, yaw * .9),
                'Chest': (lean * .35, 0, yaw * 1.1), 'Neck': (style['head'] * .4, 0, -yaw * .4),
                'Head': (style['head'] * .6, 0, -yaw * .6)}
        for side, lead in (('Left', c), ('Right', -c)):
            swing = math.sin(phase - style['knee_lag']) * (-1 if side == 'Left' else 1)
            thigh = -style['bias'] - style['amplitude'] * lead - lean * .25
            knee = style['knee'][0] + style['knee'][1] * max(0.0, swing) ** 1.5
            # The foot stays near level: toes up into the heel strike, heel up at the push-off.
            foot = -style['toe'][0] * max(0.0, lead) + style['toe'][1] * max(0.0, -lead) ** 2
            pose[side + 'UpLeg'] = (thigh, 0, 0)
            pose[side + 'Leg'] = (knee, 0, 0)
            pose[side + 'Foot'] = (foot - thigh - knee - lean * .25, 0, 0)
        # Each arm swings with the opposite leg, bending more on the forward swing.
        swing = style['arm'] * c
        elbow, extra = style['elbow']
        arms(pose, style['arm_bias'] + swing, style['arm_bias'] - swing, style['down'],
             elbow + extra * max(0.0, -c), elbow + extra * max(0.0, c), .08)
        back, flutter = style['cape']
        pose['Cape1'] = (back + flutter * math.sin(2 * phase), 0, yaw * .5)
        pose['Cape2'] = (back * .35 + flutter * 1.4 * math.sin(2 * phase - .9), 0, 0)
        pose['Cape3'] = (back * .25 + flutter * 1.8 * math.sin(2 * phase - 1.8), 0, 0)
        front, flap = style['tabard']
        pose['Tabard1'] = (-front - flap * math.cos(2 * phase) - lean * .25, 0, 0)
        pose['Tabard2'] = (front * .8 + flap * math.sin(2 * phase - .6), 0, 0)
        return pose
    return pose_at


def flight(style):
    """Extra hip height: the run leaves the ground between one push-off and the next strike."""
    return lambda frame, frames: style['hop'] * max(0.0, math.cos(4 * math.pi * frame / frames - 5.4))


# (name, frames, pose function, flight function). All loop.
CLIPS = [
    ('idle', 60, idle, None),
    ('walk', 27, gait(WALK), None),
    ('run', 19, gait(RUN), flight(RUN)),
]


def apply_pose(rig, pose, lift=0.0):
    for p in rig.pose.bones:
        basis = p.bone.matrix_local.to_quaternion()
        value = pose.get(p.name, (0, 0, 0))
        turn = value if isinstance(value, Quaternion) else be.euler_quaternion(value)
        p.rotation_quaternion = basis.inverted() @ turn @ basis
        p.location = (0, 0, 0)
    hips = rig.pose.bones['Hips']
    hips.location = hips.bone.matrix_local.to_quaternion().inverted() @ (Vector(pose.get('loc', (0, 0, 0))) + Vector((0, 0, lift)))


def lowest_foot(mesh, feet):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    co = np.empty(len(data.vertices) * 3)
    data.vertices.foreach_get('co', co)
    evaluated.to_mesh_clear()
    return co[2::3][feet].min()


def create_animations(rig, mesh, feet):
    scene = bpy.context.scene
    scene.render.fps = FPS
    rig.animation_data_create()
    for p in rig.pose.bones:
        be.enum(p, 'rotation_mode', 'QUATERNION')
    for name, frames, pose_at, hop in CLIPS:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        # The lower foot rests on the ground on every frame, so the hips rise and sink with the stride.
        lifts = []
        for frame in range(frames):
            apply_pose(rig, pose_at(frame, frames))
            bpy.context.view_layer.update()
            lifts.append(-lowest_foot(mesh, feet))
        lifts = np.array(lifts)
        lifts = (np.roll(lifts, 1) + 2 * lifts + np.roll(lifts, -1)) / 4
        for frame in range(frames + 1):
            lift = lifts[frame % frames] + (hop(frame, frames) if hop else 0)
            apply_pose(rig, pose_at(frame, frames), lift)
            for p in rig.pose.bones:
                p.keyframe_insert('rotation_quaternion', frame=frame + 1, group=p.name)
                p.keyframe_insert('location', frame=frame + 1, group=p.name)
    rig.animation_data.action = bpy.data.actions['idle']
    apply_pose(rig, {})
    scene.frame_set(1)
    print('Clips:', [(name, frames) for name, frames, _, _ in CLIPS])


# --- Output -----------------------------------------------------------------------------------

def export(character_id, rig, mesh):
    out = ROOT / f'assets/characters/standalone/{character_id}/model.glb'
    out.parent.mkdir(parents=True, exist_ok=True)
    rig['looping_clips'] = [name for name, *_ in CLIPS]
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(out), use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False, export_extras=True, export_yup=True)
    print('RIGGED_CHARACTER_EXPORT', out)


def preview(rig, mesh, character_id, directory):
    """One sheet per view (front-left, side, back-left): a row per clip, six frames each."""
    be.ENEMIES[character_id] = CHARACTERS[character_id]
    be.CLIPS[character_id] = [(name, frames, True, pose_at) for name, frames, pose_at, _ in CLIPS]
    # Absolute: Blender resolves a relative render path against the drive root.
    directory = Path(directory).resolve()
    for view, direction in (('front', (-.7, -1, .25)), ('side', (-1, 0, .05)), ('back', (-.6, 1, .25))):
        be.ENEMIES[character_id]['preview']['direction'] = direction
        be.preview(rig, mesh, character_id, directory)
        target = directory / f'{character_id}_{view}.png'
        target.unlink(missing_ok=True)
        (directory / 'clips.png').rename(target)
        scene = bpy.context.scene
        bpy.data.objects.remove(scene.camera)
    (directory / '_frame.png').unlink(missing_ok=True)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', required=True, choices=sorted(CHARACTERS))
    parser.add_argument('--preview')
    parser.add_argument('--no-export', action='store_true')
    args = parser.parse_args(argv)
    spec = CHARACTERS[args.id]
    mesh = import_source(args.id)
    rig = be.build_armature(spec['bones'], Vector((0, 0, 0)))
    feet = skin(mesh, rig, spec)
    create_animations(rig, mesh, feet)
    if not args.no_export:
        export(args.id, rig, mesh)
    if args.preview:
        preview(rig, mesh, args.id, args.preview)


if __name__ == '__main__':
    main()
