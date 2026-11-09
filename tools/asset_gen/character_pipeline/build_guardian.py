"""Rig and animate a static Tripo guardian mesh into a Godot-ready GLB.

Guardians are the stand-like spirits a character can equip (one each). The source
(assets/characters/tripo/guardian/<id>/model.glb) is read only. A small skeleton fitted to the
model's own floating pose is added (after dropping loose strays and, for some, sharpening the tendril
ends into brush-stroke flicks) (body column, tail wisp, head with a hinged Jaw, two clawed arms
with a Fingers bone for the claws), the mesh is skinned by distance to the bones with explicit
jaw / head regions, and in-place clips are keyed. The result goes to
assets/characters/guardian/<id>/model.glb.

    blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_guardian.py -- --id shadow1   (or shadow2)
    (add --preview <dir> to render a contact sheet of every clip)

Helpers (armature, keyed poses, apply_pose, preview camera conventions) come from build_enemy.py:
Blender metres, Z-up, the model faces -Y. Bone rotations are in armature axes: +X pitches an upward
bone forward / swings a downward bone back (and opens the forward-pointing Jaw), +Z turns toward the
character's left (+X). A guardian floats: nothing is kept on the ground.
"""
import argparse
import heapq
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_enemy as be  # noqa: E402

ROOT = be.ROOT

# Bone: (head, tail, parent, distance radius). Root is the non-deforming pivot under the tail tip.
# The right hand reaches forward (y -.18), the left one hangs back (y +.08): Tripo's own pose.
SHADOW_BONES = {
    'Root': ((0, 0, 0), (0, 0, .15), None, None),
    'Hips': ((0, -.03, .30), (0, -.01, .45), 'Root', .07),
    'Tail': ((0, -.04, .30), (0, -.045, .17), 'Hips', .05),
    'Tail1': ((0, -.045, .17), (-.01, -.02, .08), 'Tail', .045),
    'Tail2': ((-.01, -.02, .08), (-.03, 0, 0), 'Tail1', .035),
    'Spine': ((0, -.01, .45), (0, .01, .56), 'Hips', .07),
    'Chest': ((0, .01, .56), (0, .03, .645), 'Spine', .08),
    'Head': ((0, .03, .645), (0, .06, .88), 'Chest', .1),
    'Jaw': ((0, -.08, .655), (0, -.27, .55), 'Head', .05),
    'RightShoulder': ((-.05, .02, .60), (-.157, .03, .60), 'Chest', .04),
    'RightArm': ((-.157, .03, .60), (-.293, -.005, .52), 'RightShoulder', .035),
    'RightForeArm': ((-.293, -.005, .52), (-.34, -.15, .42), 'RightArm', .03),
    'RightHand': ((-.34, -.15, .42), (-.35, -.2, .34), 'RightForeArm', .035),
    'RightFingers': ((-.35, -.2, .34), (-.36, -.22, .24), 'RightHand', .04),
    'LeftShoulder': ((.05, .04, .60), (.156, .07, .61), 'Chest', .04),
    'LeftArm': ((.156, .07, .61), (.244, .163, .54), 'LeftShoulder', .035),
    'LeftForeArm': ((.244, .163, .54), (.33, .10, .43), 'LeftArm', .03),
    'LeftHand': ((.33, .10, .43), (.345, .06, .35), 'LeftForeArm', .035),
    'LeftFingers': ((.345, .06, .35), (.34, .03, .24), 'LeftHand', .04),
}

# Shadow2: a hulking ink demon with a beaked head thrust forward (snout tip y -.24, z .67), both clawed
# arms hanging down in front (the right one further forward), tendrils streaming off the back and a
# wispy tail whose tip is the origin.
SHADOW2_BONES = {
    'Root': ((0, 0, 0), (0, 0, .15), None, None),
    'Hips': ((0, 0, .36), (0, 0, .48), 'Root', .08),
    'Tail': ((0, 0, .36), (0, .03, .24), 'Hips', .06),
    'Tail1': ((0, .03, .24), (0, -.06, .12), 'Tail', .05),
    'Tail2': ((0, -.06, .12), (-.03, -.13, 0), 'Tail1', .04),
    'Spine': ((0, 0, .48), (0, 0, .58), 'Hips', .08),
    'Chest': ((0, 0, .58), (0, -.03, .68), 'Spine', .09),
    'Head': ((0, -.08, .68), (0, -.2, .88), 'Chest', .08),
    'Jaw': ((0, -.17, .70), (0, -.25, .655), 'Head', .025),
    'RightShoulder': ((-.05, 0, .64), (-.2, 0, .66), 'Chest', .05),
    'RightArm': ((-.2, 0, .66), (-.29, -.06, .52), 'RightShoulder', .045),
    'RightForeArm': ((-.29, -.06, .52), (-.33, -.22, .40), 'RightArm', .04),
    'RightHand': ((-.33, -.22, .40), (-.345, -.27, .31), 'RightForeArm', .04),
    'RightFingers': ((-.345, -.27, .31), (-.33, -.25, .21), 'RightHand', .045),
    'LeftShoulder': ((.05, 0, .64), (.2, 0, .66), 'Chest', .05),
    'LeftArm': ((.2, 0, .66), (.29, -.03, .51), 'LeftShoulder', .045),
    'LeftForeArm': ((.29, -.03, .51), (.355, -.09, .40), 'LeftArm', .04),
    'LeftHand': ((.355, -.09, .40), (.36, -.13, .31), 'LeftForeArm', .04),
    'LeftFingers': ((.36, -.13, .31), (.33, -.15, .21), 'LeftHand', .045),
}

GUARDIANS = {
    'shadow1': {
        'bones': SHADOW_BONES,
        # Lower jaw: in front of the hinge and below the mouth gap (lower teeth z .54-.62, upper .68-.74).
        # The jaw bone never takes vertices behind hinge_y or above top_z (the upper jaw).
        'jaw': {'max_y': -.12, 'blend_y': -.07, 'z': (.47, .665), 'reach': .15, 'hinge_y': -.1, 'upper_reach': .2},
        # Upper jaw and skull: everything above head_from (minus the hands / shoulders, which stay
        # lower) belongs to Head, blending in over head_blend.
        'head_from': .70, 'head_blend': .64,
        'preview': {'scale': 1.25, 'target': (0, 0, .48), 'direction': (-.55, -1, .2)},
    },
    'shadow2': {
        'bones': SHADOW2_BONES,
        # The beak's lower edge, under the teeth line (z ~.70) and in front of the hinge.
        'jaw': {'max_y': -.21, 'blend_y': -.18, 'z': (.635, .70), 'reach': .07, 'hinge_y': -.17, 'upper_reach': .08},
        'head_from': .74, 'head_blend': .69, 'head_width': .19,
        # Back tendrils (y > .06) stay off the arms; above the waist they ride on the Chest.
        'arm_max_y': .06, 'back': {'from_y': .08, 'full_y': .16, 'min_z': .48},
        # A loose strand floating ~8 cm behind the right shoulder (not joined to the body).
        'piece_gap': .004, 'remove_inside': [((-.40, .20, .56), (-.28, .30, .71))],
        # The streaming tendril ends are drawn in to sharp brush-stroke flicks (払い).
        # Pieces smaller than min_island (specks) and tips inside `exclude` (the beak and teeth) are left as is.
        'taper': {'thin': .035, 'length': .09, 'min_branch': .02, 'window': .008, 'curve': .9, 'extend': .35,
                  'min_island': .008, 'exclude': [((-.1, -.35, .62), (.1, -.15, .78))]},
        'preview': {'scale': 1.3, 'target': (0, -.05, .48), 'direction': (-.55, -1, .2)},
    },
}


# --- Mesh -------------------------------------------------------------------------------------

def import_source(guardian_id):
    source = ROOT / f'assets/characters/tripo/guardian/{guardian_id}/model.glb'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    assert len(meshes) == 1, f'expected one mesh, got {[o.name for o in meshes]}'
    mesh = meshes[0]
    mesh.data.transform(mesh.matrix_world)
    mesh.matrix_world = Matrix.Identity(4)
    mesh.name = mesh.data.name = guardian_id
    co = np.array([v.co[:] for v in mesh.data.vertices])
    # Tail tip on z=0, centred left/right on the body column (the arms are not symmetric).
    shift = Vector((0, 0, -co[:, 2].min()))
    mesh.data.transform(Matrix.Translation(shift))
    return mesh


def skin(mesh, rig, spec):
    bones = spec['bones']
    names = [n for n, b in bones.items() if b[2] is not None]
    co = np.array([v.co[:] for v in mesh.data.vertices])
    d = np.empty((len(co), len(names)))
    for k, name in enumerate(names):
        head, tail, _, radius = bones[name]
        dist = be.segment_distance(co, np.array(head), np.array(tail))
        side = 1 if name.startswith('Left') else -1 if name.startswith('Right') else 0
        if side:
            dist += np.maximum(0, -side * co[:, 0] + .03) * 4
            if 'arm_max_y' in spec:
                dist += np.maximum(0, co[:, 1] - spec['arm_max_y']) * 4
        if name == 'Jaw':
            # The jaw never reaches behind its hinge or into the upper jaw.
            jaw = spec['jaw']
            dist += np.maximum(0, co[:, 1] - jaw['hinge_y']) * 6 + np.maximum(0, co[:, 2] - jaw['z'][1]) * 8
        d[:, k] = np.maximum(dist - radius, .005)
    w = d ** -4
    w[w < np.sort(w, axis=1)[:, -4:-3]] = 0
    w /= w.sum(1, keepdims=True)

    def one_hot(name):
        row = np.zeros(len(names))
        row[names.index(name)] = 1
        return row

    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    if 'back' in spec:
        back = spec['back']
        tb = np.clip((y - back['from_y']) / (back['full_y'] - back['from_y']), 0, 1) * np.clip((z - back['min_z']) / .06, 0, 1)
        tb = tb * tb * (3 - 2 * tb)
        w = w * (1 - tb[:, None]) + one_hot('Chest') * tb[:, None]
    # Skull / upper jaw: above head_from, anything near the centre column.
    centre = np.abs(x) < spec.get('head_width', .24)
    t = np.clip((z - spec['head_blend']) / (spec['head_from'] - spec['head_blend']), 0, 1)
    t = np.where(centre | (z > .78), t * t * (3 - 2 * t), 0)
    w = w * (1 - t[:, None]) + one_hot('Head') * t[:, None]
    # Lower jaw region.
    jaw = spec['jaw']
    ty = np.clip((jaw['blend_y'] - y) / (jaw['blend_y'] - jaw['max_y']), 0, 1)
    tz = ((z > jaw['z'][0]) & (z < jaw['z'][1])).astype(float)
    tz *= np.clip((z - jaw['z'][0]) / .04, 0, 1)
    tj = ty * tz * (np.abs(x) < jaw['reach'])
    tj = tj * tj * (3 - 2 * tj)
    w = w * (1 - tj[:, None]) + one_hot('Jaw') * tj[:, None]
    # Upper jaw in front of the hinge, above the gap: firmly Head so the mouth opens cleanly.
    upper = (y < jaw['max_y']) & (z >= jaw['z'][1]) & (np.abs(x) < jaw['upper_reach'])
    w[upper] = one_hot('Head')

    kd = KDTree(len(co))
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    # Smooth across loose islands, but not across the mouth gap (upper / lower teeth stay apart).
    near = [[j for _, j, _ in kd.find_range(p, .018)] for p in co]
    lower = tj > .5
    keep_apart = upper | lower
    for _ in range(3):
        w = np.array([w[n].mean(0) for n in near])
        w[upper] = one_hot('Head')
        w[lower] = w[lower] * .3 + one_hot('Jaw') * .7
    w[w < .01] = 0
    w /= w.sum(1, keepdims=True)
    for k, name in enumerate(names):
        group = mesh.vertex_groups.new(name=name)
        for i in np.nonzero(w[:, k])[0]:
            group.add([int(i)], float(w[i, k]), 'REPLACE')
    mesh.parent = rig
    modifier = mesh.modifiers.new('Armature', 'ARMATURE')
    modifier.object = rig
    print('Skinned', len(co), 'vertices to', len(names), 'bones; jaw', int(lower.sum()), 'upper', int(upper.sum()),
          'kept apart', int(keep_apart.sum()))


def taper_tips(mesh, spec):
    """Draws every tendril end in to a sharp point, like the flick (払い) at the end of a brush stroke.

    Geodesic distance g runs over the surface from each piece's most central vertex (nearest a bone).
    Tendril tips are the peaks of g; sweeping g downward, a peak's branch grows until it meets a higher
    one, and only peaks that stood out by at least `min_branch` (persistence) count, so surface noise is
    ignored. Along a branch, vertices at the same g form a ring around the tendril; within `length` of the
    tip (shorter for a short spike, and only while the ring stays thinner than `thin`) each vertex is
    pulled in to its ring's centre, fully at the tip, and the tip is drawn out a little further."""
    cfg = spec['taper']
    me = mesh.data
    n = len(me.vertices)
    co = np.array([v.co[:] for v in me.vertices])
    # The import splits vertices along UV seams; coincident copies are joined (weld) for the walk.
    kd = KDTree(n)
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    weld = np.array([min(j for _, j, _ in kd.find_range(p, 1e-6)) for p in co])
    adjacency = [[] for _ in range(n)]
    for e in me.edges:
        a, b = weld[e.vertices[0]], weld[e.vertices[1]]
        if a == b:
            continue
        length = float(np.linalg.norm(co[a] - co[b]))
        adjacency[a].append((b, length))
        adjacency[b].append((a, length))

    # Seed each piece at the vertex nearest a bone; tiny pieces (teeth, specks) are left alone.
    bones = [(np.array(b[0]), np.array(b[1])) for b in spec['bones'].values() if b[2] is not None]
    to_bone = np.min([be.segment_distance(co, h, t) for h, t in bones], axis=0)
    g = np.full(n, np.inf)
    heap = []
    for piece in be.pieces(co, [e.vertices[:] for e in me.edges], 1e-6):
        if np.linalg.norm(np.ptp(co[piece], axis=0)) < cfg['min_island']:
            continue
        seed = weld[piece[int(np.argmin(to_bone[piece]))]]
        g[seed] = 0
        heap.append((0.0, seed))
    heapq.heapify(heap)
    while heap:
        d, i = heapq.heappop(heap)
        if d > g[i]:
            continue
        for j, length in adjacency[i]:
            if d + length < g[j]:
                g[j] = d + length
                heapq.heappush(heap, (d + length, j))

    # Persistence sweep from the top: components are branches, each owned by its peak.
    parent = np.full(n, -1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    own = {}          # peak -> vertices of that branch alone
    persistence = {}  # peak -> how far it stood out before meeting a higher branch
    order = [i for i in np.argsort(-g) if np.isfinite(g[i]) and weld[i] == i]
    for v in order:
        roots = {find(j) for j, _ in adjacency[v] if parent[j] >= 0}
        if not roots:
            parent[v] = v
            own[v] = [v]
            continue
        top = max(roots, key=lambda r: g[r])
        for r in roots - {top}:
            parent[r] = top
            persistence[r] = g[r] - g[v]
            if persistence[r] < cfg['min_branch']:
                own[top].extend(own.pop(r))  # a bump on the branch, not a tendril of its own
        parent[v] = top
        own[top].append(v)
    for r in own:
        persistence.setdefault(r, g[r])
    out = co.copy()
    tapered = moved = 0
    window = cfg['window']
    for tip, members in own.items():
        if persistence[tip] < cfg['min_branch'] or any(be.inside(co[[tip]], box) for box in cfg.get('exclude', [])):
            continue
        members = np.array(members)
        depth = g[tip] - g[members]
        span = min(cfg['length'], persistence[tip] * .8)
        near_tip = depth < span + window
        members, depth = members[near_tip], depth[near_tip]
        p = co[members]
        # Ring centre and radius at each vertex: the branch's vertices at about the same depth (a window,
        # since the tendrils are coarse and one depth may hold a single vertex).
        same = np.abs(depth[:, None] - depth[None, :]) < window
        axis = (same @ p) / same.sum(1, keepdims=True)
        radius = np.array([np.linalg.norm(p[same[k]] - axis[k], axis=1).max() for k in range(len(p))])
        # Stop where the ring gets thick (the tendril has opened into the body).
        thick = depth[radius > cfg['thin']]
        if len(thick):
            span = min(span, thick.min())
        if span < cfg['min_branch'] * .5:
            continue
        keep = depth < span
        members, depth, p, axis = members[keep], depth[keep], p[keep], axis[keep]
        base = axis[np.argmax(depth)]
        direction = co[tip] - base
        direction /= max(np.linalg.norm(direction), 1e-6)
        u = depth / span
        keep_ratio = u ** cfg['curve']
        out[members] = axis + (p - axis) * keep_ratio[:, None] + direction * (span * cfg['extend'] * (1 - u) ** 2)[:, None]
        tapered += 1
        moved += len(members)
    for i, v in enumerate(me.vertices):
        v.co = out[weld[i]]
    me.update()
    print('Tapered', tapered, 'tendril tips,', moved, 'vertices')


# --- Animation --------------------------------------------------------------------------------

def wave(frame, frames, phase=0.0, cycles=1):
    return math.sin(2 * math.pi * (cycles * frame / frames + phase))


def shadow_idle(frame, frames):
    """Hovering: a slow bob, the tail wisp rippling, claws flexing, the jaw breathing."""
    w = wave(frame, frames)
    return {'loc': (0, 0, .012 * wave(frame, frames, .25)),
            'Hips': (.03 * w, 0, .02 * wave(frame, frames, .4)),
            'Tail': (.12 * wave(frame, frames, .1), .1 * wave(frame, frames, .3), 0),
            'Tail1': (.18 * wave(frame, frames, .3), .16 * wave(frame, frames, .5), 0),
            'Tail2': (.25 * wave(frame, frames, .5), .22 * wave(frame, frames, .7), 0),
            'Spine': (-.02 * w, 0, 0), 'Chest': (-.03 * w, 0, .03 * wave(frame, frames, .2)),
            'Head': (.05 * wave(frame, frames, .15), 0, -.05 * wave(frame, frames, .35)),
            'Jaw': (.06 + .06 * wave(frame, frames, .6, 2), 0, 0),
            'RightArm': (.06 * wave(frame, frames, .1), .05 * w, 0), 'RightForeArm': (.08 * wave(frame, frames, .3), 0, 0),
            'RightFingers': (.12 * wave(frame, frames, .5, 2), 0, 0),
            'LeftArm': (.06 * wave(frame, frames, .6), -.05 * w, 0), 'LeftForeArm': (.08 * wave(frame, frames, .8), 0, 0),
            'LeftFingers': (.12 * wave(frame, frames, 0, 2), 0, 0)}


# Roar on appearing: curl in, then throw the head back, the jaw wide and both arms flung open.
SHADOW_CURL = {'loc': (0, .02, -.04), 'Hips': (.15, 0, 0), 'Spine': (.2, 0, 0), 'Chest': (.25, 0, 0), 'Head': (.3, 0, 0),
               'Jaw': (-.05, 0, 0), 'Tail': (.3, 0, 0), 'Tail1': (.35, 0, 0), 'Tail2': (.4, 0, 0),
               'RightArm': (.3, -.3, 0), 'RightForeArm': (.4, 0, 0), 'RightFingers': (.5, 0, 0),
               'LeftArm': (.3, .3, 0), 'LeftForeArm': (.4, 0, 0), 'LeftFingers': (.5, 0, 0)}
SHADOW_ROAR = {'loc': (0, .03, .04), 'Hips': (-.08, 0, 0), 'Spine': (-.12, 0, 0), 'Chest': (-.18, 0, 0), 'Head': (-.35, 0, 0),
               'Jaw': (.65, 0, 0), 'Tail': (-.2, 0, 0), 'Tail1': (-.25, 0, 0), 'Tail2': (-.3, 0, 0),
               'RightShoulder': (0, .15, 0), 'RightArm': (-.3, .45, 0), 'RightForeArm': (-.2, 0, 0), 'RightFingers': (-.45, 0, 0),
               'LeftShoulder': (0, -.15, 0), 'LeftArm': (-.3, -.45, 0), 'LeftForeArm': (-.2, 0, 0), 'LeftFingers': (-.45, 0, 0)}
SHADOW_ROAR_SHAKE = dict(SHADOW_ROAR, Head=(-.32, 0, .08), Jaw=(.6, 0, 0))

# Claw strike: draw the right claws back over the shoulder, rake them down and across in front.
SHADOW_WINDUP = {'loc': (0, .05, .02), 'Hips': (-.05, 0, -.1), 'Spine': (-.05, 0, -.15), 'Chest': (-.08, 0, -.25),
                 'Head': (.05, 0, .2), 'Jaw': (.25, 0, 0), 'Tail': (-.15, 0, .1), 'Tail1': (-.2, 0, .15),
                 'RightShoulder': (0, .2, 0), 'RightArm': (.6, .8, 0), 'RightForeArm': (-.3, 0, 0), 'RightFingers': (-.5, 0, 0),
                 'LeftArm': (-.3, -.2, 0), 'LeftFingers': (.2, 0, 0)}
SHADOW_RAKE = {'loc': (0, -.12, -.03), 'Hips': (.15, 0, .1), 'Spine': (.12, 0, .15), 'Chest': (.18, 0, .3),
               'Head': (-.05, 0, -.2), 'Jaw': (.45, 0, 0), 'Tail': (.3, 0, -.1), 'Tail1': (.35, 0, -.15), 'Tail2': (.4, 0, 0),
               'RightShoulder': (0, -.1, 0), 'RightArm': (-.9, -.2, .6), 'RightForeArm': (-.2, 0, 0), 'RightFingers': (.6, 0, 0),
               'LeftArm': (.4, .1, 0), 'LeftFingers': (.3, 0, 0)}

# Bite: coil back, lunge with the jaw wide, snap shut, pull back.
SHADOW_COIL = {'loc': (0, .06, .02), 'Spine': (-.1, 0, 0), 'Chest': (-.12, 0, 0), 'Head': (-.15, 0, 0), 'Jaw': (.2, 0, 0),
               'Tail': (-.2, 0, 0), 'Tail1': (-.25, 0, 0),
               'RightArm': (.3, .3, 0), 'RightFingers': (-.3, 0, 0), 'LeftArm': (.3, -.3, 0), 'LeftFingers': (-.3, 0, 0)}
SHADOW_LUNGE = {'loc': (0, -.22, -.02), 'Hips': (.2, 0, 0), 'Spine': (.15, 0, 0), 'Chest': (.15, 0, 0), 'Head': (.1, 0, 0),
                'Jaw': (.75, 0, 0), 'Tail': (.35, 0, 0), 'Tail1': (.4, 0, 0), 'Tail2': (.45, 0, 0),
                'RightArm': (-.6, .4, 0), 'RightFingers': (-.4, 0, 0), 'LeftArm': (-.6, -.4, 0), 'LeftFingers': (-.4, 0, 0)}
SHADOW_SNAP = dict(SHADOW_LUNGE, Head=(.2, 0, 0), Jaw=(-.04, 0, 0), RightFingers=(.6, 0, 0), LeftFingers=(.6, 0, 0))
SHADOW_WRENCH = dict(SHADOW_SNAP, Head=(.2, .2, .25), Chest=(.15, 0, .15))


def settle(pose_at, idle):
    """Ends a one-shot clip on the idle's first pose so it hands back to idle without a pop."""
    def at(frame, frames):
        return be.blend(pose_at(frame, frames), idle(0, 60), be.smooth((frame - frames * .7) / (frames * .3)))
    return at


CLIPS = {
    'shadow1': [
        ('idle', 72, True, shadow_idle),
        ('roar', 48, False, settle(lambda f, n: be.keyed([(0, SHADOW_CURL), (10, SHADOW_CURL), (18, SHADOW_ROAR), (24, SHADOW_ROAR_SHAKE),
                                                           (28, SHADOW_ROAR), (34, SHADOW_ROAR_SHAKE), (48, {})], f), shadow_idle)),
        ('attack', 30, False, settle(lambda f, n: be.keyed([(0, {}), (9, SHADOW_WINDUP), (13, SHADOW_RAKE), (17, SHADOW_RAKE), (30, {})], f),
                                     shadow_idle)),
        ('attack_bite', 30, False, settle(lambda f, n: be.keyed([(0, {}), (7, SHADOW_COIL), (11, SHADOW_LUNGE), (13, SHADOW_SNAP),
                                                                  (16, SHADOW_WRENCH), (19, SHADOW_SNAP), (30, {})], f), shadow_idle)),
    ],
}
# Shadow2 has the same bones and moves the same way.
CLIPS['shadow2'] = CLIPS['shadow1']


def create_animations(rig, guardian_id):
    scene = bpy.context.scene
    scene.render.fps = be.FPS
    rig.animation_data_create()
    for p in rig.pose.bones:
        be.enum(p, 'rotation_mode', 'QUATERNION')
    for name, frames, _, pose_at in CLIPS[guardian_id]:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame in range(frames + 1):
            be.apply_pose(rig, pose_at(frame, frames))
            for p in rig.pose.bones:
                p.keyframe_insert('rotation_quaternion', frame=frame + 1, group=p.name)
                p.keyframe_insert('location', frame=frame + 1, group=p.name)
    rig.animation_data.action = bpy.data.actions['idle']
    be.apply_pose(rig, {})
    scene.frame_set(1)
    print('Clips:', [(name, frames) for name, frames, _, _ in CLIPS[guardian_id]])


# --- Output -----------------------------------------------------------------------------------

def export(guardian_id, rig, mesh):
    out = ROOT / f'assets/characters/guardian/{guardian_id}/model.glb'
    out.parent.mkdir(parents=True, exist_ok=True)
    rig['looping_clips'] = [name for name, _, loops, _ in CLIPS[guardian_id] if loops]
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(out), use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False, export_extras=True, export_yup=True)
    print('GUARDIAN_EXPORT', out)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', required=True, choices=sorted(GUARDIANS))
    parser.add_argument('--preview')
    parser.add_argument('--no-export', action='store_true')
    args = parser.parse_args(argv)
    spec = GUARDIANS[args.id]
    mesh = import_source(args.id)
    if 'remove_inside' in spec:
        be.remove_strays(mesh, spec)
    if 'taper' in spec:
        taper_tips(mesh, spec)
    rig = be.build_armature(spec['bones'], Vector())
    skin(mesh, rig, spec)
    create_animations(rig, args.id)
    if not args.no_export:
        export(args.id, rig, mesh)
    if args.preview:
        # build_enemy's contact sheet reads its own tables; point them at this guardian.
        be.ENEMIES[args.id] = spec
        be.CLIPS[args.id] = CLIPS[args.id]
        be.preview(rig, mesh, args.id, args.preview)


if __name__ == '__main__':
    main()
