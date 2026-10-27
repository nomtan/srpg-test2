"""Rig and animate a static Tripo enemy mesh into a Godot-ready GLB.

The source (assets/characters/tripo/enemy/<id>/model.glb) is read only. Stray pieces Tripo left
floating around the model are dropped, the held weapon and shield (if any) are cut out into their own
GLBs, a small skeleton fitted to the model's own pose is added, the body is skinned by distance to the
bones, and in-place clips are keyed: idle / walk / attack / guard / hit / death. Each enemy has its own
skeleton and clip set (CLIPS): the goblin is a biped, the wolf a quadruped without equipment.

Equipment is swappable at runtime. Every weapon GLB is posed in one grip frame (origin in the fist,
+Y along the blade, +X across it) and every shield GLB in one shield frame (origin on the back face,
+Z out of the face, +Y up). The body GLB records where those frames sit in rest space as armature
extras ("weapon_socket" / "shield_socket": bone, origin, basis columns, all in glTF/Godot axes).
The cut-out weapon and shield, plus project weapons re-posed into the same frames (EQUIPMENT), go to
assets/characters/enemy/equipment/{weapon,shield}/<id>/model.glb.

    blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_enemy.py -- --id goblin
    (--id wolf for the wolf; add --preview <dir> to render a contact sheet of every clip)

Blender is metres and Z-up, the model faces -Y (glTF/Godot +Z). Bone rotations below are given in
armature axes: +X pitches an upward bone forward and swings a downward bone back, +Z turns toward
the character's left (+X).
"""
import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
FPS = 30

# Bone: (head, tail, parent, distance radius). Root is the non-deforming ground pivot.
GOBLIN_BONES = {
    'Root': ((0, .05, 0), (0, .05, .15), None, None),
    'Hips': ((0, .06, .38), (0, .05, .46), 'Root', .06),
    'Spine': ((0, .05, .46), (0, .01, .54), 'Hips', .06),
    'Chest': ((0, .01, .54), (-.02, -.04, .61), 'Spine', .07),
    'Neck': ((-.02, -.04, .61), (-.03, -.08, .66), 'Chest', .03),
    'Head': ((-.03, -.08, .66), (-.04, -.12, .86), 'Neck', .08),
    'LeftShoulder': ((.03, 0, .58), (.13, 0, .60), 'Chest', .02),
    'LeftArm': ((.13, 0, .60), (.22, -.08, .52), 'LeftShoulder', .025),
    'LeftForeArm': ((.22, -.08, .52), (.28, -.16, .45), 'LeftArm', .02),
    'LeftHand': ((.28, -.16, .45), (.31, -.21, .42), 'LeftForeArm', .02),
    'RightShoulder': ((-.03, 0, .58), (-.13, .02, .56), 'Chest', .02),
    'RightArm': ((-.13, .02, .56), (-.22, .04, .46), 'RightShoulder', .025),
    'RightForeArm': ((-.22, .04, .46), (-.28, -.04, .39), 'RightArm', .02),
    'RightHand': ((-.28, -.04, .39), (-.31, -.10, .36), 'RightForeArm', .02),
    'LeftUpLeg': ((.08, .06, .37), (.15, -.06, .22), 'Hips', .035),
    'LeftLeg': ((.15, -.06, .22), (.28, .02, .08), 'LeftUpLeg', .03),
    'LeftFoot': ((.28, .02, .08), (.32, -.08, .02), 'LeftLeg', .02),
    'RightUpLeg': ((-.08, .08, .37), (-.22, .03, .26), 'Hips', .035),
    'RightLeg': ((-.22, .03, .26), (-.21, .17, .09), 'RightUpLeg', .03),
    'RightFoot': ((-.21, .17, .09), (-.33, .08, .01), 'RightLeg', .02),
}

# Quadruped: the spine runs forward from the pelvis to the head, front legs hang from the chest
# (Shoulder = shoulder blade, Arm / ForeArm / Hand = upper arm, forearm, paw) and hind legs from the
# hips (UpLeg / Leg / Foot = thigh, shin, hock to toe).
WOLF_BONES = {
    'Root': ((-.01, 0, 0), (-.01, 0, .15), None, None),
    'Hips': ((.05, .2, .30), (0, .04, .33), 'Root', .09),
    'Spine': ((0, .04, .33), (-.07, -.12, .35), 'Hips', .1),
    'Chest': ((-.07, -.12, .35), (-.09, -.24, .36), 'Spine', .1),
    'Neck': ((-.09, -.24, .36), (-.1, -.33, .35), 'Chest', .07),
    'Head': ((-.1, -.33, .35), (-.1, -.49, .26), 'Neck', .05),
    'Jaw': ((-.1, -.35, .25), (-.1, -.46, .21), 'Head', .01),
    'Tail': ((.07, .24, .33), (.13, .32, .33), 'Hips', .04),
    'Tail1': ((.13, .32, .33), (.22, .42, .33), 'Tail', .05),
    'Tail2': ((.22, .42, .33), (.26, .47, .16), 'Tail1', .05),
    'LeftShoulder': ((-.05, -.14, .42), (.01, -.18, .30), 'Chest', .04),
    'LeftArm': ((.01, -.18, .30), (.04, -.10, .19), 'LeftShoulder', .03),
    'LeftForeArm': ((.04, -.10, .19), (.05, -.23, .06), 'LeftArm', .02),
    'LeftHand': ((.05, -.23, .06), (.065, -.33, .01), 'LeftForeArm', .02),
    'RightShoulder': ((-.1, -.14, .42), (-.15, -.18, .30), 'Chest', .04),
    'RightArm': ((-.15, -.18, .30), (-.18, -.08, .19), 'RightShoulder', .03),
    'RightForeArm': ((-.18, -.08, .19), (-.235, -.24, .06), 'RightArm', .02),
    'RightHand': ((-.235, -.24, .06), (-.27, -.34, .01), 'RightForeArm', .02),
    'LeftUpLeg': ((.10, .19, .32), (.13, .13, .2), 'Hips', .04),
    'LeftLeg': ((.13, .13, .2), (.195, .235, .09), 'LeftUpLeg', .025),
    'LeftFoot': ((.195, .235, .09), (.24, .13, .01), 'LeftLeg', .02),
    'RightUpLeg': ((0, .2, .32), (-.07, .14, .19), 'Hips', .04),
    'RightLeg': ((-.07, .14, .19), (-.035, .29, .09), 'RightUpLeg', .025),
    'RightFoot': ((-.035, .29, .09), (-.11, .21, .01), 'RightLeg', .02),
}

# Antlered quadruped standing hunched on its long front legs, the head low in front and the hind legs
# curled up off the ground under the rump (the left one folded forward, the right one trailing back),
# with a tail that arches up and hangs down behind. Each antler rides on two stiff bones off the head.
GRIMM_BONES = {
    'Root': ((0, 0, 0), (0, 0, .15), None, None),
    'Hips': ((0, .20, .47), (0, .06, .56), 'Root', .09),
    'Spine': ((0, .06, .56), (0, -.08, .60), 'Hips', .12),
    'Chest': ((0, -.08, .60), (0, -.20, .58), 'Spine', .12),
    'Neck': ((0, -.20, .58), (.02, -.30, .50), 'Chest', .07),
    'Head': ((.02, -.30, .50), (.03, -.47, .38), 'Neck', .06),
    'Jaw': ((.03, -.36, .40), (.04, -.45, .32), 'Head', .015),
    'LeftAntler': ((.06, -.30, .52), (.24, -.28, .68), 'Head', .05),
    'LeftAntler1': ((.24, -.28, .68), (.27, -.18, .90), 'LeftAntler', .06),
    'RightAntler': ((-.04, -.30, .52), (-.22, -.30, .68), 'Head', .05),
    'RightAntler1': ((-.22, -.30, .68), (-.27, -.18, .90), 'RightAntler', .06),
    'Tail': ((0, .20, .48), (0, .30, .53), 'Hips', .03),
    'Tail1': ((0, .30, .53), (0, .40, .46), 'Tail', .03),
    'Tail2': ((0, .40, .46), (0, .45, .20), 'Tail1', .03),
    'LeftShoulder': ((.05, -.14, .60), (.15, -.13, .50), 'Chest', .05),
    'LeftArm': ((.15, -.13, .50), (.21, -.16, .30), 'LeftShoulder', .035),
    'LeftForeArm': ((.21, -.16, .30), (.24, -.19, .08), 'LeftArm', .03),
    'LeftHand': ((.24, -.19, .08), (.21, -.26, .01), 'LeftForeArm', .025),
    'RightShoulder': ((-.05, -.12, .60), (-.16, -.10, .50), 'Chest', .05),
    'RightArm': ((-.16, -.10, .50), (-.25, -.10, .31), 'RightShoulder', .035),
    'RightForeArm': ((-.25, -.10, .31), (-.26, -.11, .08), 'RightArm', .03),
    'RightHand': ((-.26, -.11, .08), (-.31, -.18, .01), 'RightForeArm', .025),
    'LeftUpLeg': ((.05, .15, .45), (.15, .11, .22), 'Hips', .04),
    'LeftLeg': ((.15, .11, .22), (.03, .27, .22), 'LeftUpLeg', .03),
    'LeftFoot': ((.03, .27, .22), (.11, .18, .05), 'LeftLeg', .025),
    'RightUpLeg': ((-.04, .16, .43), (-.11, .28, .23), 'Hips', .04),
    'RightLeg': ((-.11, .28, .23), (-.05, .42, .27), 'RightUpLeg', .03),
    'RightFoot': ((-.05, .42, .27), (-.10, .48, .09), 'RightLeg', .025),
}

ENEMIES = {
    'goblin': {
        'bones': GOBLIN_BONES,
        # Proximity groups (vertices closer than this join one piece) whose bounds fall inside a
        # box are dropped: the cloth scrap and the sliver floating behind the goblin.
        'piece_gap': .015,
        'remove_inside': [((-.2, .25, .55), (.4, .5, .95)), ((0, .25, .05), (.12, .4, .2))],
        # The curved blade, cut out along the line from butt to tip: the blade (beyond blade_from,
        # in front of blade_max_y), the neck just past the fist and the thin handle through it.
        'weapon': {'id': 'scimitar', 'bone': 'RightHand', 'tip': (-.47, -.49, .72), 'butt': (-.25, 0, .33),
                   'grip_t': .10, 'blade_from': .22, 'blade_radius': .12, 'blade_max_y': -.1,
                   'neck_from': .15, 'neck_radius': .035, 'handle_radius': .02},
        # The round shield is a separate proximity piece inside this box.
        'shield': {'id': 'round', 'bone': 'LeftHand', 'box': ((.18, -.35, .1), (.5, .02, .65))},
        # Above head_full everything is Head; between head_blend and head_full within head_reach of
        # the centre line it blends in (hood, ears).
        'head_full': .70, 'head_blend': .63, 'head_reach': .12,
    },
    'wolf': {
        'bones': WOLF_BONES,
        'piece_gap': .015,
        'remove_inside': [],
        # The body is turned a little: the chest is centred at x -.1, the hips at x .07. Left / right
        # limbs are kept to their side of this line instead of x = 0 ((y, x) points, interpolated).
        'midline': ((-.2, -.1), (.2, .07)),
        # Tripo painted the right flank much darker than the left (mean luminance .12 against .20).
        'even_sides': {'radius': .06, 'max_gain': 2.5, 'passes': 3, 'max_contrast': 1.8},
        'preview': {'scale': 1.3, 'target': (0, 0, .28), 'direction': (-1, -.55, .3)},
    },
    'grimm': {
        'bones': GRIMM_BONES,
        'piece_gap': .015,
        # A 3 mm sliver floating inside the mane.
        'remove_inside': [((.05, -.2, .73), (.08, -.16, .76))],
        # Only the front feet reach the ground and they stand off to the right; keep the body's own centre.
        'keep_x': True,
        'preview': {'scale': 2.1, 'target': (0, 0, .42), 'direction': (-1, -.55, .3)},
    },
}


# Project weapons re-posed into the enemy grip / shield frames. Sources stand along +Z (Tripo units,
# about 0.98 tall); grip is the height of the hand on it, blade_down marks a sword standing on its tip.
EQUIPMENT = {
    'weapon': {
        'hand_axe': {'source': 'assets/weapons/gread_sword/002/model.glb', 'grip': .24, 'scale': .52},
        'longsword': {'source': 'assets/weapons/onehand_sword/001/001.glb', 'grip': .855, 'scale': .72, 'blade_down': True},
        'staff': {'source': 'assets/weapons/staff/001/model.glb', 'grip': .40, 'scale': .82},
    },
    'shield': {
        # Its face looks toward -Y; centre is the middle of its height.
        'kite': {'source': 'assets/weapons/shield/001/model.glb', 'center': .49, 'scale': .55},
    },
}


def enum(owner, prop, value):
    try:
        setattr(owner, prop, value)
    except TypeError as error:
        print('enum fallback', prop, error)


# --- Mesh -------------------------------------------------------------------------------------

def import_source(enemy_id):
    source = ROOT / f'assets/characters/tripo/enemy/{enemy_id}/model.glb'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    assert len(meshes) == 1, f'expected one mesh, got {[o.name for o in meshes]}'
    mesh = meshes[0]
    # Bake the import transform so the mesh object is identity.
    mesh.data.transform(mesh.matrix_world)
    mesh.matrix_world = Matrix.Identity(4)
    mesh.name = mesh.data.name = enemy_id
    return mesh


def pieces(co, edges, gap):
    """Vertex index lists of the pieces left when vertices nearer than gap are joined."""
    parent = np.arange(len(co))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[a] = b

    for a, b in edges:
        union(a, b)
    kd = KDTree(len(co))
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    for i, p in enumerate(co):
        for _, j, _ in kd.find_range(p, gap):
            union(i, j)
    groups = {}
    for i in range(len(co)):
        groups.setdefault(find(i), []).append(i)
    return sorted(groups.values(), key=len, reverse=True)


def inside(points, box):
    lo, hi = np.array(box[0]), np.array(box[1])
    return bool(np.all(points.min(0) >= lo) and np.all(points.max(0) <= hi))


def remove_strays(mesh, spec):
    co = np.array([v.co[:] for v in mesh.data.vertices])
    drop = [g for g in pieces(co, [e.vertices[:] for e in mesh.data.edges], spec['piece_gap'])
            if any(inside(co[g], box) for box in spec['remove_inside'])]
    assert len(drop) == len(spec['remove_inside']), f'expected {len(spec["remove_inside"])} strays, found {len(drop)}'
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bm.verts.ensure_lookup_table()
    doomed = [bm.verts[i] for g in drop for i in g]
    bmesh.ops.delete(bm, geom=doomed, context='VERTS')
    bm.to_mesh(mesh.data)
    bm.free()
    print('Removed stray pieces:', [len(g) for g in drop], 'vertices')


def neighbour_mean(co, values, radius):
    kd = KDTree(len(co))
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    return np.array([values[[j for _, j, _ in kd.find_range(p, radius)]].mean(0) for p in co]), kd


def uv_gain_map(mesh, uv, gain, w, h):
    """Per-vertex gain interpolated over every triangle in UV space; 1 where no triangle lies."""
    total, count = np.zeros((h, w)), np.zeros((h, w))
    mesh.data.calc_loop_triangles()
    for tri in mesh.data.loop_triangles:
        corners = uv[list(tri.loops)] * (w, h) - .5
        g = gain[list(tri.vertices)]
        lo = np.floor(corners.min(0)).astype(int)
        hi = np.ceil(corners.max(0)).astype(int) + 1
        xs, ys = np.meshgrid(np.arange(max(lo[0], 0), min(hi[0], w)), np.arange(max(lo[1], 0), min(hi[1], h)))
        if xs.size == 0:
            continue
        (ax, ay), (bx, by), (cx, cy) = corners
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-9:
            continue
        b0 = ((bx - xs) * (cy - ys) - (cx - xs) * (by - ys)) / area
        b1 = ((cx - xs) * (ay - ys) - (ax - xs) * (cy - ys)) / area
        b2 = 1 - b0 - b1
        # A little past the edges so texels the sampler blends in at seams are covered too.
        inside = (b0 > -.15) & (b1 > -.15) & (b2 > -.15)
        total[ys[inside], xs[inside]] += (b0 * g[0] + b1 * g[1] + b2 * g[2])[inside]
        count[ys[inside], xs[inside]] += 1
    return np.where(count > 0, total / np.maximum(count, 1), 1)


def even_sides(mesh, spec):
    """Brightens the painted texture wherever a side is darker than the mirrored point on the other side
    (across the midline). The ratio of the two smoothed brightnesses becomes a gain per vertex, which is
    interpolated over each triangle in UV space and multiplied into a copy of the texture, so the painted
    pattern is kept and only its overall level rises. Smoothing the gain softens it near the midline, so
    the measurement is repeated on the corrected texture for a few passes. Only ever brightens."""
    settings = spec['even_sides']
    node = next(n for n in mesh.data.materials[0].node_tree.nodes if n.type == 'TEX_IMAGE')
    source = node.image
    w, h = source.size
    px = np.array(source.pixels[:]).reshape(h, w, 4)
    co = np.array([v.co[:] for v in mesh.data.vertices])
    uv = np.array([d.uv[:] for d in mesh.data.uv_layers.active.data])
    loop_vertex = np.array([l.vertex_index for l in mesh.data.loops])
    rows, cols = np.clip((uv[:, 1] * h).astype(int), 0, h - 1), np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
    (y0, x0), (y1, x1) = spec['midline']
    mirrored = co.copy()
    mirrored[:, 0] = 2 * np.interp(co[:, 1], (y0, y1), (x0, x1)) - co[:, 0]
    darker = co[:, 0] < mirrored[:, 0]
    total_gain = np.ones(len(co))
    out = px.copy()
    for _ in range(settings['passes']):
        texel = out[rows, cols, :3] @ np.array((.299, .587, .114))
        vertex_lum = np.bincount(loop_vertex, texel, len(co)) / np.maximum(np.bincount(loop_vertex, minlength=len(co)), 1)
        smooth_lum, kd = neighbour_mean(co, vertex_lum, settings['radius'])
        other = smooth_lum[[kd.find(p)[1] for p in mirrored]]
        gain = np.clip(other / np.maximum(smooth_lum, 1e-3), 1, settings['max_gain'] / total_gain)
        gain = np.minimum(neighbour_mean(co, gain, settings['radius'])[0], settings['max_gain'] / total_gain)
        total_gain *= gain
        out[..., :3] = np.clip(out[..., :3] * uv_gain_map(mesh, uv, gain, w, h)[..., None], 0, 1)
    # The darker side is also flatter (fewer light patches): spread its texels around their local mean
    # until the local spread of brightness matches the mirrored side too.
    if settings.get('max_contrast', 1) > 1:
        texel = out[rows, cols, :3] @ np.array((.299, .587, .114))
        count = np.maximum(np.bincount(loop_vertex, minlength=len(co)), 1)
        vertex_lum = np.bincount(loop_vertex, texel, len(co)) / count
        local_mean, kd = neighbour_mean(co, vertex_lum, settings['radius'])
        local_square, _ = neighbour_mean(co, vertex_lum ** 2, settings['radius'])
        spread = np.sqrt(np.maximum(local_square - local_mean ** 2, 1e-6))
        other = spread[[kd.find(p)[1] for p in mirrored]]
        contrast = neighbour_mean(co, np.clip(other / spread, 1, settings['max_contrast']), settings['radius'])[0]
        mean_map = uv_gain_map(mesh, uv, local_mean, w, h)[..., None]
        out[..., :3] = np.clip(mean_map + (out[..., :3] - mean_map) * uv_gain_map(mesh, uv, contrast, w, h)[..., None], 0, 1)
        print('Evened contrast: mean %.2f on the darker side' % contrast[darker].mean())

    image = bpy.data.images.new(source.name + '_even', w, h, alpha=True)
    image.pixels[:] = out.ravel()
    image.file_format = 'PNG'
    image.pack()
    node.image = image
    print('Evened sides: mean gain %.2f on the darker side, max %.2f' % (total_gain[darker].mean(), total_gain.max()))


def center_on_feet(mesh, spec):
    """Puts the ground centre of the model at the origin (feet on z=0)."""
    co = np.array([v.co[:] for v in mesh.data.vertices])
    low = co[co[:, 2] < co[:, 2].min() + .03]
    x = 0 if spec.get('keep_x') else -(low[:, 0].min() + low[:, 0].max()) / 2
    shift = Vector((x, 0, -co[:, 2].min()))
    mesh.data.transform(Matrix.Translation(shift))
    print('Centred by', tuple(round(v, 4) for v in shift))
    return shift


# --- Equipment --------------------------------------------------------------------------------

def to_gltf(v):
    """Blender (Z-up) to glTF/Godot (Y-up) axes."""
    return [float(v[0]), float(v[2]), -float(v[1])]


def socket_extras(bone, origin, axes):
    return {'bone': bone, 'origin': to_gltf(origin), 'basis': [c for axis in axes for c in to_gltf(axis)]}


def cut_out(mesh, keep, name):
    """A new object holding only the vertices in keep; they are removed from mesh."""
    part = mesh.copy()
    part.data = mesh.data.copy()
    part.name = part.data.name = name
    bpy.context.scene.collection.objects.link(part)
    for obj, drop in ((part, ~keep), (mesh, keep)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.nonzero(drop)[0]], context='VERTS')
        bm.to_mesh(obj.data)
        bm.free()
    return part


def into_frame(obj, origin, axes):
    """Re-expresses obj's vertices in the frame (origin, X/Y/Z axes, Blender coordinates) so that the
    exported glTF node has the frame's axes as its own +X/+Y/+Z."""
    x, y, z = (np.array(a) for a in axes)
    co = np.array([v.co[:] for v in obj.data.vertices]) - np.array(origin)
    local = np.stack([co @ x, co @ y, co @ z], 1)
    blender = np.stack([local[:, 0], -local[:, 2], local[:, 1]], 1)
    obj.data.vertices.foreach_set('co', blender.ravel())
    obj.data.update()


def split_equipment(mesh, spec):
    """Cuts the weapon and shield out of the body. Returns the parts and their socket frames."""
    co = np.array([v.co[:] for v in mesh.data.vertices])
    w = spec['weapon']
    tip, butt = np.array(w['tip']), np.array(w['butt'])
    length = np.linalg.norm(tip - butt)
    axis = (tip - butt) / length
    rel = co - butt
    t = rel @ axis
    d = np.linalg.norm(rel - np.outer(t, axis), axis=1)
    blade = (t > w['blade_from']) & (t < length + .02) & (d < w['blade_radius']) & (co[:, 1] < w['blade_max_y'])
    weapon = blade | ((t > w['neck_from']) & (t <= w['blade_from']) & (d < w['neck_radius'])) \
        | ((t > -.03) & (t < length) & (d < w['handle_radius']))
    across = co[blade] - co[blade].mean(0)
    across -= np.outer(across @ axis, axis)
    x = np.linalg.svd(across, full_matrices=False)[2][0]
    weapon_axes = (x, axis, np.cross(x, axis))
    weapon_origin = butt + axis * w['grip_t']

    groups = pieces(co, [e.vertices[:] for e in mesh.data.edges], spec['piece_gap'])
    match = [g for g in groups if inside(co[g], spec['shield']['box'])]
    assert len(match) == 1, f'shield: {len(match)} matches'
    shield = np.zeros(len(co), bool)
    shield[match[0]] = True
    disc = co[shield]
    center = disc.mean(0)
    normal = np.linalg.svd(disc - center, full_matrices=False)[2][2]
    # Out of the face: away from the body's centre line.
    if normal @ (center - np.array((0, 0, center[2]))) < 0:
        normal = -normal
    up = np.array((0., 0., 1.)) - normal * normal[2]
    up /= np.linalg.norm(up)
    shield_axes = (np.cross(up, normal), up, normal)
    shield_origin = center + normal * ((disc - center) @ normal).min()

    weapon &= ~shield
    shield_part = cut_out(mesh, shield, spec['shield']['id'])
    keep = np.ones(len(co), bool)
    keep[shield] = False
    weapon_part = cut_out(mesh, weapon[keep], w['id'])
    into_frame(weapon_part, weapon_origin, weapon_axes)
    into_frame(shield_part, shield_origin, shield_axes)
    print('Cut out weapon', int(weapon.sum()), 'and shield', int(shield.sum()), 'vertices')
    return weapon_part, shield_part, {
        'weapon_socket': (w['bone'], weapon_origin, weapon_axes),
        'shield_socket': (spec['shield']['bone'], shield_origin, shield_axes)}


def library_part(kind, part_id, entry):
    """Imports a project weapon or shield and re-poses it into the enemy grip / shield frame."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / entry['source']))
    meshes = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
    assert len(meshes) == 1, f'{part_id}: expected one mesh'
    obj = meshes[0]
    obj.data.transform(obj.matrix_world)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    for extra in set(bpy.data.objects) - before - {obj}:
        bpy.data.objects.remove(extra)
    obj.name = obj.data.name = part_id
    co = np.array([v.co[:] for v in obj.data.vertices])
    if kind == 'weapon':
        # Grip frame in Blender terms: +Z along the blade (glTF +Y).
        co[:, 2] -= entry['grip']
        if entry.get('blade_down'):
            co[:, 0] *= -1
            co[:, 2] *= -1
    else:
        # Back face on the origin, face toward -Y (glTF +Z).
        co[:, 2] -= entry['center']
        co[:, 1] -= co[:, 1].max()
    obj.data.vertices.foreach_set('co', (co * entry['scale']).ravel())
    obj.data.update()
    return obj


def export_part(obj, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_animations=False,
                              export_extras=True, export_yup=True)
    print('EQUIPMENT_EXPORT', path)


# --- Rig and skin -----------------------------------------------------------------------------

def build_armature(bones, shift):
    data = bpy.data.armatures.new('Armature')
    rig = bpy.data.objects.new('Armature', data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for name, (head, tail, parent, _) in bones.items():
        bone = data.edit_bones.new(name)
        bone.head = Vector(head) + shift
        bone.tail = Vector(tail) + shift
        bone.roll = 0
        bone.use_deform = parent is not None
        if parent:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = (Vector(bones[parent][1]) - Vector(head)).length < 1e-6
    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def segment_distance(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def skin(mesh, rig, spec, shift):
    bones = spec['bones']
    names = [n for n, b in bones.items() if b[2] is not None]
    s = np.array(shift[:])
    co = np.array([v.co[:] for v in mesh.data.vertices])
    if 'midline' in spec:
        (y0, x0), (y1, x1) = spec['midline']
        mid = np.interp(co[:, 1] - s[1], (y0, y1), (x0, x1)) + s[0]
    else:
        mid = np.zeros(len(co))
    d = np.empty((len(co), len(names)))
    for k, name in enumerate(names):
        head, tail, _, radius = bones[name]
        dist = segment_distance(co, np.array(head) + s, np.array(tail) + s)
        # Limb bones only reach across the centre line reluctantly.
        side = 1 if name.startswith('Left') else -1 if name.startswith('Right') else 0
        if side:
            dist += np.maximum(0, -side * (co[:, 0] - mid) + .02) * 4
        d[:, k] = np.maximum(dist - radius, .005)
    w = d ** -4
    w[w < np.sort(w, axis=1)[:, -4:-3]] = 0
    w /= w.sum(1, keepdims=True)

    def one_hot(name):
        row = np.zeros(len(names))
        row[names.index(name)] = 1
        return row

    if 'head_full' in spec:
        head = one_hot('Head')
        z, reach = co[:, 2] - s[2], np.abs(co[:, 0] - s[0]) < spec['head_reach']
        t = np.clip((z - spec['head_blend']) / (spec['head_full'] - spec['head_blend']), 0, 1)
        t = np.where(z >= spec['head_full'], 1, np.where(reach, t * t * (3 - 2 * t), 0))
        w = w * (1 - t[:, None]) + head * t[:, None]
    # Tripo meshes are hundreds of loose islands; smoothing across a small radius keeps
    # neighbouring islands moving together instead of tearing apart.
    kd = KDTree(len(co))
    for i, p in enumerate(co):
        kd.insert(p, i)
    kd.balance()
    near = [[j for _, j, _ in kd.find_range(p, .02)] for p in co]
    for _ in range(3):
        smoothed = np.array([w[n].mean(0) for n in near])
        w = smoothed
    w[w < .01] = 0
    w /= w.sum(1, keepdims=True)
    for k, name in enumerate(names):
        group = mesh.vertex_groups.new(name=name)
        for i in np.nonzero(w[:, k])[0]:
            group.add([int(i)], float(w[i, k]), 'REPLACE')
    mesh.parent = rig
    modifier = mesh.modifiers.new('Armature', 'ARMATURE')
    modifier.object = rig
    print('Skinned', len(co), 'vertices to', len(names), 'bones')


# --- Animation --------------------------------------------------------------------------------

def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def blend(a, b, t):
    """Mixes two poses ({bone: (x, y, z)}, plus 'loc' for the root offset)."""
    keys = set(a) | set(b)
    return {k: tuple(p + (q - p) * t for p, q in zip(a.get(k, (0, 0, 0)), b.get(k, (0, 0, 0)))) for k in keys}


def keyed(keys, frame):
    """Pose at frame from [(frame, pose), ...] with eased transitions."""
    for (f0, p0), (f1, p1) in zip(keys, keys[1:]):
        if f0 <= frame <= f1:
            return blend(p0, p1, smooth((frame - f0) / max(f1 - f0, 1)))
    return keys[-1][1]


def goblin_idle(frame, frames):
    w = math.sin(2 * math.pi * frame / frames)
    return {'loc': (0, 0, -.006 * (1 - math.cos(2 * math.pi * frame / frames))),
            'Chest': (.03 * w, 0, .02 * w), 'Head': (-.03 * w, 0, .05 * math.sin(2 * math.pi * frame / frames + 1)),
            'RightArm': (.06 * w, 0, 0), 'LeftArm': (-.04 * w, 0, 0),
            'LeftUpLeg': (-.03 * w, 0, 0), 'LeftLeg': (.05 * w, 0, 0),
            'RightUpLeg': (-.03 * w, 0, 0), 'RightLeg': (.05 * w, 0, 0)}


def goblin_walk(frame, frames):
    phase = 2 * math.pi * frame / frames
    w, c = math.sin(phase), math.cos(phase)
    return {'loc': (0, 0, -.012 + .012 * math.cos(2 * phase)),
            'Hips': (0, 0, .10 * w), 'Spine': (.06, 0, -.06 * w), 'Chest': (.08, .03 * w, -.08 * w),
            'Head': (-.12, 0, .06 * w),
            'LeftUpLeg': (-.45 * w, 0, 0), 'LeftLeg': (.6 * max(0, c), 0, 0), 'LeftFoot': (-.3 * max(0, c) + .2 * w, 0, 0),
            'RightUpLeg': (.45 * w, 0, 0), 'RightLeg': (.6 * max(0, -c), 0, 0), 'RightFoot': (-.3 * max(0, -c) - .2 * w, 0, 0),
            'RightArm': (-.35 * w, 0, 0), 'RightForeArm': (-.15 - .1 * w, 0, 0),
            'LeftArm': (.2 * w, 0, 0)}


GOBLIN_WINDUP = {'loc': (0, .02, -.02), 'Spine': (-.08, 0, -.2), 'Chest': (-.12, 0, -.35), 'Head': (.1, 0, .25),
                 'RightShoulder': (0, 0, -.1), 'RightArm': (-1.9, -.3, 0), 'RightForeArm': (-.7, 0, 0),
                 'LeftArm': (-.2, 0, -.2), 'LeftUpLeg': (.1, 0, 0), 'RightUpLeg': (-.1, 0, 0), 'RightLeg': (.15, 0, 0)}
GOBLIN_STRIKE = {'loc': (0, -.07, -.04), 'Spine': (.15, 0, .2), 'Chest': (.3, 0, .4), 'Head': (-.3, 0, -.25),
                 'RightShoulder': (0, 0, .1), 'RightArm': (-.25, .2, .3), 'RightForeArm': (-.15, 0, 0), 'RightHand': (.3, 0, 0),
                 'LeftArm': (.25, 0, .1), 'LeftUpLeg': (-.35, 0, 0), 'LeftLeg': (.3, 0, 0),
                 'RightUpLeg': (.25, 0, 0), 'RightLeg': (.15, 0, 0)}
GOBLIN_GUARD = {'loc': (0, .01, -.05), 'Spine': (.1, 0, -.15), 'Chest': (.12, 0, -.3), 'Head': (.12, 0, .3),
         'LeftShoulder': (0, 0, -.15), 'LeftArm': (-.35, 0, -.9), 'LeftForeArm': (-.2, 0, -.5), 'LeftHand': (0, 0, -.2),
         'RightArm': (.25, 0, 0), 'RightForeArm': (-.2, 0, 0),
         'LeftUpLeg': (-.25, 0, 0), 'LeftLeg': (.4, 0, 0), 'LeftFoot': (-.15, 0, 0),
         'RightUpLeg': (-.25, 0, 0), 'RightLeg': (.4, 0, 0), 'RightFoot': (-.15, 0, 0)}
GOBLIN_HIT = {'loc': (0, .05, -.01), 'Spine': (-.2, 0, .05), 'Chest': (-.3, 0, .12), 'Head': (-.35, 0, .2),
       'RightArm': (.35, 0, -.35), 'RightForeArm': (-.3, 0, 0), 'LeftArm': (.2, 0, .35),
       'LeftUpLeg': (.1, 0, 0), 'RightUpLeg': (.1, 0, 0)}
# Dying: the head thrown back to stare at the sky, then the strength drains out (arms go limp, knees
# give) until it sinks to its knees and slumps forward where it kneels.
GOBLIN_LOOK_UP = {'Root': (0, 0, 0), 'loc': (0, .03, -.01), 'Spine': (-.18, 0, 0), 'Chest': (-.35, 0, 0), 'Neck': (-.35, 0, 0),
                  'Head': (-.6, 0, .05), 'RightArm': (.15, 0, .15), 'RightForeArm': (.25, 0, 0),
                  'LeftArm': (.15, 0, -.15), 'LeftForeArm': (.25, 0, 0)}
GOBLIN_SAG = {'Root': (0, 0, 0), 'loc': (0, .03, -.06), 'Spine': (-.08, 0, .04), 'Chest': (-.2, 0, .04), 'Neck': (-.15, 0, 0),
              'Head': (-.45, 0, .1), 'RightShoulder': (0, 0, .1), 'RightArm': (.25, 0, .25), 'RightForeArm': (.5, 0, 0), 'RightHand': (.3, 0, 0),
              'LeftShoulder': (0, 0, -.1), 'LeftArm': (.25, 0, -.25), 'LeftForeArm': (.5, 0, 0),
              'LeftUpLeg': (-.35, 0, 0), 'LeftLeg': (.6, 0, 0), 'LeftFoot': (-.25, 0, 0),
              'RightUpLeg': (-.35, 0, 0), 'RightLeg': (.6, 0, 0), 'RightFoot': (-.25, 0, 0)}
GOBLIN_KNEEL = {'Root': (0, 0, 0), 'loc': (0, .04, -.2), 'Spine': (.05, 0, .06), 'Chest': (-.05, 0, .06), 'Neck': (-.1, 0, .1),
                'Head': (-.3, 0, .2), 'RightShoulder': (0, 0, .15), 'RightArm': (.3, 0, .3), 'RightForeArm': (.6, 0, 0), 'RightHand': (.4, 0, 0),
                'LeftShoulder': (0, 0, -.15), 'LeftArm': (.3, 0, -.3), 'LeftForeArm': (.6, 0, 0),
                'LeftUpLeg': (-1.1, 0, 0), 'LeftLeg': (1.6, 0, 0), 'LeftFoot': (-.5, 0, 0),
                'RightUpLeg': (-1.1, 0, 0), 'RightLeg': (1.6, 0, 0), 'RightFoot': (-.5, 0, 0)}
# Sunk back on its heels where it knelt, slumped forward a little with the head hanging and the arms
# dangling down in front. (The source model already stoops, so the back bends only slightly more.)
GOBLIN_SLUMP = {'Root': (0, 0, 0), 'loc': (0, .06, -.26), 'Spine': (0, 0, .04), 'Chest': (.1, 0, .06), 'Neck': (.05, 0, 0),
                'Head': (.2, 0, .15), 'RightShoulder': (0, 0, .1), 'RightArm': (-.2, 0, .2), 'RightForeArm': (.3, 0, 0), 'RightHand': (.3, 0, 0),
                'LeftShoulder': (0, 0, -.1), 'LeftArm': (-.2, 0, -.2), 'LeftForeArm': (.3, 0, 0),
                'LeftUpLeg': (-1.2, 0, .1), 'LeftLeg': (1.9, 0, 0), 'LeftFoot': (-.6, 0, 0),
                'RightUpLeg': (-1.2, 0, -.1), 'RightLeg': (1.9, 0, 0), 'RightFoot': (-.6, 0, 0)}


def wolf_idle(frame, frames):
    phase = 2 * math.pi * frame / frames
    w = math.sin(phase)
    return {'loc': (0, 0, -.004 * (1 - math.cos(phase))),
            'Spine': (.015 * w, 0, 0), 'Chest': (-.02 * w, 0, 0), 'Neck': (.03 * w, 0, .03 * math.sin(phase + 1)),
            'Head': (-.03 * w, 0, .05 * math.sin(phase + 1)), 'Jaw': (.06 + .06 * math.sin(4 * phase), 0, 0),
            'Tail': (.05 * w, 0, .12 * math.sin(phase + .5)), 'Tail1': (0, 0, .15 * math.sin(phase)),
            'Tail2': (0, 0, .15 * math.sin(phase - .5))}


def wolf_walk(frame, frames):
    """A trot: the left front and right hind leg swing together, then the other diagonal pair."""
    phase = 2 * math.pi * frame / frames
    w, c = math.sin(phase), math.cos(phase)
    pose = {'loc': (0, 0, -.008 + .008 * math.cos(2 * phase)),
            'Spine': (0, .03 * w, 0), 'Chest': (0, -.03 * w, 0), 'Head': (.03 * math.cos(2 * phase), 0, -.03 * w),
            'Tail': (.1, 0, .12 * w), 'Tail1': (0, 0, .12 * math.sin(phase - .6)), 'Tail2': (0, 0, .12 * math.sin(phase - 1.2))}
    # swing > 0 is back; a leg lifts while it swings forward.
    for side, swing, lift in (('Left', w, max(0, -c)), ('Right', -w, max(0, c))):
        other = 'Right' if side == 'Left' else 'Left'
        pose[side + 'Arm'] = (.35 * swing - .1 * lift, 0, 0)
        pose[side + 'ForeArm'] = (-.25 * lift, 0, 0)
        pose[side + 'Hand'] = (.9 * lift, 0, 0)
        pose[other + 'UpLeg'] = (.3 * swing - .25 * lift, 0, 0)
        pose[other + 'Leg'] = (.5 * lift, 0, 0)
        pose[other + 'Foot'] = (-.2 * lift, 0, 0)
    return pose


# attack, the claw: rearing back onto the haunches with the right foreleg raised high, then slamming it
# down and forward with the weight thrown after it.
WOLF_CLAW_RAISE = {'Root': (0, 0, 0), 'loc': (0, .06, .04), 'Hips': (-.3, 0, 0), 'Spine': (-.08, 0, -.05), 'Chest': (-.06, -.15, -.05),
                   'Neck': (0, 0, .05), 'Head': (-.05, 0, .1), 'Jaw': (.3, 0, 0),
                   'RightShoulder': (-.5, 0, 0), 'RightArm': (-2.0, 0, -.15), 'RightForeArm': (.9, 0, 0), 'RightHand': (.9, 0, 0),
                   'LeftArm': (.25, 0, 0), 'LeftForeArm': (.05, 0, 0),
                   'LeftUpLeg': (.15, 0, 0), 'LeftLeg': (.3, 0, 0), 'RightUpLeg': (.15, 0, 0), 'RightLeg': (.3, 0, 0),
                   'Tail': (.15, 0, 0)}
WOLF_CLAW_SLAM = {'Root': (0, 0, 0), 'loc': (0, -.1, -.06), 'Spine': (.04, 0, .05), 'Chest': (.12, .15, .05),
                  'Neck': (.1, 0, -.05), 'Head': (.12, 0, -.1), 'Jaw': (.4, 0, 0),
                  'RightShoulder': (0, 0, 0), 'RightArm': (-.3, 0, .1), 'RightForeArm': (.05, 0, 0), 'RightHand': (0, 0, 0),
                  # The left foreleg folds under the weight instead of propping the body up off the slammed paw.
                  'LeftArm': (.2, 0, 0), 'LeftForeArm': (-.6, 0, 0), 'LeftHand': (.6, 0, 0),
                  'LeftUpLeg': (.15, 0, 0), 'LeftLeg': (.1, 0, 0), 'RightUpLeg': (.15, 0, 0), 'RightLeg': (.1, 0, 0),
                  'Tail': (.05, 0, -.15)}

# attack_bite: crouched back with the jaws wide, it leaps (BITE_REACH forward, nose up, forelegs
# reaching), lands with its teeth in the target and shakes, then pushes off and hops back to its spot.
BITE_REACH = .45
WOLF_WINDUP = {'Root': (0, 0, 0), 'loc': (0, .05, -.04), 'Spine': (-.08, 0, 0), 'Chest': (-.05, 0, 0),
               'Neck': (-.15, 0, 0), 'Head': (-.25, 0, 0), 'Jaw': (.45, 0, 0),
               'LeftArm': (-.3, 0, 0), 'LeftForeArm': (.15, 0, 0), 'RightArm': (-.3, 0, 0), 'RightForeArm': (.15, 0, 0),
               'LeftUpLeg': (-.45, 0, 0), 'LeftLeg': (.45, 0, 0), 'LeftFoot': (-.1, 0, 0),
               'RightUpLeg': (-.45, 0, 0), 'RightLeg': (.45, 0, 0), 'RightFoot': (-.1, 0, 0),
               'Tail': (-.15, 0, 0), 'Tail1': (-.1, 0, 0)}
WOLF_LEAP = {'Root': (-.15, 0, 0), 'loc': (0, -BITE_REACH * .55, .14), 'Spine': (-.03, 0, 0), 'Neck': (-.05, 0, 0),
             'Head': (-.1, 0, 0), 'Jaw': (.55, 0, 0),
             'LeftArm': (-.9, 0, 0), 'LeftForeArm': (-.2, 0, 0), 'LeftHand': (.3, 0, 0),
             'RightArm': (-.9, 0, 0), 'RightForeArm': (-.2, 0, 0), 'RightHand': (.3, 0, 0),
             'LeftUpLeg': (.6, 0, 0), 'LeftLeg': (-.2, 0, 0), 'LeftFoot': (.3, 0, 0),
             'RightUpLeg': (.6, 0, 0), 'RightLeg': (-.2, 0, 0), 'RightFoot': (.3, 0, 0),
             'Tail': (.15, 0, 0), 'Tail1': (.05, 0, 0)}
WOLF_BITE = {'Root': (.05, 0, 0), 'loc': (0, -BITE_REACH, -.02), 'Spine': (.05, 0, 0), 'Chest': (.05, 0, 0),
             'Neck': (.15, 0, 0), 'Head': (.12, 0, 0), 'Jaw': (-.04, 0, 0),
             'LeftArm': (-.35, 0, 0), 'LeftForeArm': (.05, 0, 0), 'RightArm': (-.35, 0, 0), 'RightForeArm': (.05, 0, 0),
             'LeftUpLeg': (.2, 0, 0), 'LeftLeg': (.05, 0, 0), 'RightUpLeg': (.2, 0, 0), 'RightLeg': (.05, 0, 0),
             'Tail': (.1, 0, 0)}
WOLF_BITE_SHAKE = dict(WOLF_BITE, Neck=(.15, 0, .15), Head=(.12, .2, .12), Tail=(.1, 0, -.2))
WOLF_PUSH_OFF = {'Root': (0, 0, 0), 'loc': (0, -BITE_REACH + .02, -.05), 'Neck': (.05, 0, 0), 'Jaw': (.15, 0, 0),
                 'LeftArm': (-.5, 0, 0), 'LeftForeArm': (.15, 0, 0), 'RightArm': (-.5, 0, 0), 'RightForeArm': (.15, 0, 0),
                 'LeftUpLeg': (-.35, 0, 0), 'LeftLeg': (.4, 0, 0), 'RightUpLeg': (-.35, 0, 0), 'RightLeg': (.4, 0, 0),
                 'Tail': (-.1, 0, 0)}
WOLF_HOP_BACK = {'Root': (-.1, 0, 0), 'loc': (0, -BITE_REACH * .45, .12), 'Head': (-.1, 0, 0), 'Jaw': (.1, 0, 0),
                 'LeftArm': (.1, 0, 0), 'LeftForeArm': (-.4, 0, 0), 'LeftHand': (.8, 0, 0),
                 'RightArm': (.1, 0, 0), 'RightForeArm': (-.4, 0, 0), 'RightHand': (.8, 0, 0),
                 'LeftUpLeg': (-.4, 0, 0), 'LeftLeg': (.5, 0, 0), 'LeftFoot': (-.2, 0, 0),
                 'RightUpLeg': (-.4, 0, 0), 'RightLeg': (.5, 0, 0), 'RightFoot': (-.2, 0, 0),
                 'Tail': (.2, 0, 0)}
WOLF_LAND = {'Root': (0, 0, 0), 'loc': (0, .02, -.04), 'LeftArm': (-.2, 0, 0), 'LeftForeArm': (.1, 0, 0),
             'RightArm': (-.2, 0, 0), 'RightForeArm': (.1, 0, 0),
             'LeftUpLeg': (-.3, 0, 0), 'LeftLeg': (.35, 0, 0), 'RightUpLeg': (-.3, 0, 0), 'RightLeg': (.35, 0, 0)}
# Backing off low with the head down and teeth bared, forelegs braced, tail tucked.
WOLF_GUARD = {'Root': (0, 0, 0), 'loc': (0, .06, -.05), 'Spine': (.04, 0, 0), 'Chest': (.06, 0, 0),
              'Neck': (.12, 0, 0), 'Head': (.05, 0, 0), 'Jaw': (.25, 0, 0),
              'LeftArm': (-.35, 0, 0), 'LeftForeArm': (.1, 0, 0), 'LeftHand': (.1, 0, 0),
              'RightArm': (-.35, 0, 0), 'RightForeArm': (.1, 0, 0), 'RightHand': (.1, 0, 0),
              'LeftUpLeg': (-.4, 0, 0), 'LeftLeg': (.45, 0, 0), 'LeftFoot': (-.1, 0, 0),
              'RightUpLeg': (-.4, 0, 0), 'RightLeg': (.45, 0, 0), 'RightFoot': (-.1, 0, 0),
              'Tail': (-.45, 0, 0), 'Tail1': (-.3, 0, 0), 'Tail2': (-.1, 0, 0)}
# Knocked back: the front rears up, the head flies up with a yelp, the tail whips.
WOLF_HIT = {'loc': (0, .05, .01), 'Hips': (-.08, 0, 0), 'Spine': (-.08, 0, .04), 'Chest': (-.05, 0, .06),
            'Neck': (-.2, 0, .1), 'Head': (-.3, 0, .1), 'Jaw': (.35, 0, 0),
            'LeftArm': (.05, 0, 0), 'LeftForeArm': (-.3, 0, 0), 'LeftHand': (.5, 0, 0), 'RightArm': (.2, 0, 0),
            'LeftUpLeg': (.12, 0, 0), 'RightUpLeg': (.12, 0, 0), 'Tail': (.1, 0, -.35), 'Tail1': (0, 0, -.2)}
# Dying: the head flung up to the sky with the jaws slack, then the strength drains away: the hind legs
# give first, the forelegs fold under the chest and, sunk on its belly, its head sags forward to the ground.
WOLF_LOOK_UP = {'Root': (0, 0, 0), 'loc': (0, .03, 0), 'Hips': (-.08, 0, 0), 'Spine': (-.05, 0, 0), 'Chest': (-.1, 0, 0),
                'Neck': (-.55, 0, 0), 'Head': (-.45, 0, .05), 'Jaw': (.25, 0, 0),
                'LeftUpLeg': (.08, 0, 0), 'RightUpLeg': (.08, 0, 0), 'Tail': (-.2, 0, 0)}
WOLF_SAG = {'Root': (0, 0, 0), 'loc': (0, .05, -.05), 'Hips': (-.05, 0, 0), 'Chest': (-.05, 0, .04), 'Neck': (-.5, 0, .05),
            'Head': (-.4, 0, .1), 'Jaw': (.35, 0, 0), 'LeftArm': (-.1, 0, 0), 'LeftForeArm': (.1, 0, 0),
            'RightArm': (-.1, 0, 0), 'RightForeArm': (.1, 0, 0),
            'LeftUpLeg': (-.45, 0, 0), 'LeftLeg': (.55, 0, 0), 'LeftFoot': (-.15, 0, 0),
            'RightUpLeg': (-.45, 0, 0), 'RightLeg': (.55, 0, 0), 'RightFoot': (-.15, 0, 0),
            'Tail': (-.4, 0, 0), 'Tail1': (-.2, 0, 0)}
WOLF_SINK = {'Root': (0, 0, 0), 'loc': (0, .04, -.15), 'Hips': (.05, 0, 0), 'Spine': (.05, 0, 0), 'Neck': (-.2, 0, .1),
             'Head': (-.1, 0, .15), 'Jaw': (.3, 0, 0),
             'LeftArm': (.3, 0, 0), 'LeftForeArm': (-.7, 0, 0), 'LeftHand': (.7, 0, 0),
             'RightArm': (.3, 0, 0), 'RightForeArm': (-.7, 0, 0), 'RightHand': (.7, 0, 0),
             'LeftUpLeg': (-.8, 0, 0), 'LeftLeg': (.9, 0, 0), 'LeftFoot': (-.3, 0, 0),
             'RightUpLeg': (-.8, 0, 0), 'RightLeg': (.9, 0, 0), 'RightFoot': (-.3, 0, 0),
             'Tail': (-.4, 0, 0), 'Tail1': (-.2, 0, 0)}
# Crumpled forward on its belly: the legs folded under it, the head sunk onto the forepaws, tail flat.
WOLF_SLUMP = {'Root': (0, 0, 0), 'loc': (0, .04, -.25), 'Hips': (.05, 0, 0), 'Spine': (.05, 0, 0), 'Neck': (.35, 0, .05),
              'Head': (.3, 0, .1), 'Jaw': (.15, 0, 0),
              'LeftArm': (.4, 0, 0), 'LeftForeArm': (-1.1, 0, 0), 'LeftHand': (.9, 0, 0),
              'RightArm': (.4, 0, 0), 'RightForeArm': (-1.1, 0, 0), 'RightHand': (.9, 0, 0),
              'LeftUpLeg': (-1.2, 0, 0), 'LeftLeg': (2.0, 0, 0), 'LeftFoot': (-.3, 0, 0),
              'RightUpLeg': (-1.2, 0, 0), 'RightLeg': (2.0, 0, 0), 'RightFoot': (-.3, 0, 0),
              'Tail': (-.5, 0, .2), 'Tail1': (-.2, 0, .15)}


def grimm_idle(frame, frames):
    """Heavy breathing over the planted forelegs, the head weaving and the curled hind legs twitching."""
    phase = 2 * math.pi * frame / frames
    w = math.sin(phase)
    return {'loc': (0, 0, -.005 * (1 - math.cos(phase))),
            'Spine': (.02 * w, 0, 0), 'Chest': (-.02 * w, 0, 0),
            'Neck': (.04 * w, 0, .04 * math.sin(phase + 1)), 'Head': (-.03 * w, 0, .06 * math.sin(phase + 1)),
            'Jaw': (.08 + .06 * math.sin(2 * phase), 0, 0),
            'Tail': (.06 * w, 0, .1 * math.sin(phase + .5)), 'Tail1': (0, 0, .12 * math.sin(phase)),
            'Tail2': (0, 0, .15 * math.sin(phase - .5)),
            'LeftUpLeg': (.05 * w, 0, 0), 'LeftFoot': (.12 * math.sin(phase + 1), 0, 0),
            'RightUpLeg': (-.05 * w, 0, 0), 'RightFoot': (-.12 * math.sin(phase + 1), 0, 0)}


def grimm_walk(frame, frames):
    """A lurching stalk on the forelegs; the curled hind legs paddle against them and the head swings low."""
    phase = 2 * math.pi * frame / frames
    w, c = math.sin(phase), math.cos(phase)
    pose = {'loc': (0, 0, -.012 + .012 * math.cos(2 * phase)),
            'Spine': (0, .03 * w, 0), 'Chest': (0, -.05 * w, .04 * w),
            'Neck': (.04 * math.cos(2 * phase), 0, -.05 * w), 'Head': (.03 * math.cos(2 * phase), 0, -.04 * w),
            'Tail': (.08, 0, .15 * w), 'Tail1': (0, 0, .12 * math.sin(phase - .6)), 'Tail2': (0, 0, .15 * math.sin(phase - 1.2))}
    # swing > 0 is back; a foreleg lifts while it swings forward.
    for side, swing, lift in (('Left', w, max(0, -c)), ('Right', -w, max(0, c))):
        other = 'Right' if side == 'Left' else 'Left'
        pose[side + 'Shoulder'] = (.08 * swing, 0, 0)
        pose[side + 'Arm'] = (.3 * swing - .2 * lift, 0, 0)
        pose[side + 'ForeArm'] = (.45 * lift, 0, 0)
        pose[side + 'Hand'] = (.5 * lift, 0, 0)
        pose[other + 'UpLeg'] = (-.25 * swing, 0, 0)
        pose[other + 'Foot'] = (.3 * lift, 0, 0)
    return pose


# attack, the gore: rearing up with the head thrown back and a foreleg pawing the air, then lunging with
# the head down so the antlers drive forward, and tossing them up through the target.
GRIMM_REAR = {'Root': (0, 0, 0), 'loc': (0, .08, 0), 'Hips': (-.2, 0, 0), 'Spine': (-.05, 0, 0), 'Chest': (-.05, 0, 0),
              'Neck': (-.35, 0, 0), 'Head': (-.35, 0, 0), 'Jaw': (.35, 0, 0),
              'LeftArm': (.3, 0, 0), 'LeftForeArm': (-.1, 0, 0),
              'RightArm': (-.5, 0, 0), 'RightForeArm': (.8, 0, 0), 'RightHand': (.6, 0, 0),
              'LeftUpLeg': (.2, 0, 0), 'RightUpLeg': (.2, 0, 0), 'Tail': (.3, 0, 0), 'Tail1': (.15, 0, 0)}
GRIMM_GORE = {'Root': (0, 0, 0), 'loc': (0, -.14, -.03), 'Hips': (.1, 0, 0), 'Spine': (.05, 0, 0), 'Chest': (.08, 0, 0),
              'Neck': (.35, 0, 0), 'Head': (.35, 0, 0), 'Jaw': (.1, 0, 0),
              'LeftArm': (-.1, 0, 0), 'RightArm': (-.35, 0, 0), 'RightForeArm': (.1, 0, 0),
              'LeftUpLeg': (-.2, 0, 0), 'RightUpLeg': (-.2, 0, 0), 'Tail': (-.1, 0, 0)}
GRIMM_TOSS = {'Root': (0, 0, 0), 'loc': (0, -.12, 0), 'Chest': (-.05, 0, 0), 'Neck': (-.15, 0, .1), 'Head': (-.45, 0, .15),
              'Jaw': (.3, 0, 0), 'LeftArm': (-.1, 0, 0), 'RightArm': (-.25, 0, 0),
              'Tail': (.15, 0, -.2), 'Tail1': (0, 0, -.15)}

# attack_bite: drawn back low with the jaws wide, it lunges GRIMM_BITE_REACH forward with the neck
# stretched out, snaps the fangs shut, wrenches its head and pulls back to its spot.
GRIMM_BITE_REACH = .3
GRIMM_COIL = {'Root': (0, 0, 0), 'loc': (0, .06, -.05), 'Spine': (-.05, 0, 0), 'Chest': (-.05, 0, 0),
              'Neck': (-.2, 0, 0), 'Head': (-.15, 0, 0), 'Jaw': (.55, 0, 0),
              'LeftArm': (-.15, 0, 0), 'LeftForeArm': (.3, 0, 0), 'RightArm': (-.15, 0, 0), 'RightForeArm': (.3, 0, 0),
              'LeftUpLeg': (.25, 0, 0), 'RightUpLeg': (.25, 0, 0), 'Tail': (.25, 0, 0)}
GRIMM_LUNGE = {'Root': (0, 0, 0), 'loc': (0, -GRIMM_BITE_REACH, -.03), 'Hips': (.08, 0, 0), 'Chest': (.05, 0, 0),
               'Neck': (.05, 0, 0), 'Head': (-.1, 0, 0), 'Jaw': (.65, 0, 0),
               'LeftArm': (-.35, 0, 0), 'RightArm': (-.45, 0, 0), 'RightForeArm': (.1, 0, 0),
               'LeftUpLeg': (-.25, 0, 0), 'RightUpLeg': (-.25, 0, 0), 'Tail': (-.1, 0, 0)}
GRIMM_SNAP = dict(GRIMM_LUNGE, Neck=(.15, 0, 0), Head=(.12, 0, 0), Jaw=(-.03, 0, 0))
GRIMM_WRENCH = dict(GRIMM_SNAP, Neck=(.15, 0, .2), Head=(.12, .25, .15), Tail=(-.1, 0, -.25))
GRIMM_PULL_BACK = {'Root': (0, 0, 0), 'loc': (0, .03, -.02), 'Neck': (-.1, 0, 0), 'Head': (-.05, 0, 0), 'Jaw': (.15, 0, 0),
                   'LeftArm': (.15, 0, 0), 'RightArm': (.15, 0, 0), 'Tail': (.1, 0, 0)}
# Head down with the antlers levelled at the foe, the forelegs braced wide, backing off with the tail tucked.
GRIMM_GUARD = {'Root': (0, 0, 0), 'loc': (0, .05, -.04), 'Hips': (.05, 0, 0), 'Neck': (.3, 0, 0), 'Head': (.25, 0, 0),
               'Jaw': (.25, 0, 0), 'LeftArm': (-.15, -.12, 0), 'LeftForeArm': (.15, 0, 0),
               'RightArm': (-.15, .12, 0), 'RightForeArm': (.15, 0, 0),
               'LeftUpLeg': (.15, 0, 0), 'RightUpLeg': (.15, 0, 0), 'Tail': (-.3, 0, 0), 'Tail1': (-.2, 0, 0)}
# Struck: the front rears back, the head and antlers jerk up and aside with the jaws gaping, the tail whips.
GRIMM_HIT = {'loc': (0, .05, .01), 'Hips': (-.08, 0, 0), 'Spine': (-.06, 0, .04), 'Chest': (-.06, 0, .06),
             'Neck': (-.25, 0, .12), 'Head': (-.3, 0, .15), 'Jaw': (.4, 0, 0),
             'LeftArm': (.1, 0, 0), 'RightArm': (.15, 0, 0), 'RightForeArm': (-.15, 0, 0),
             'LeftUpLeg': (.15, 0, 0), 'RightUpLeg': (.15, 0, 0), 'Tail': (.2, 0, -.3), 'Tail1': (0, 0, -.2)}
# Dying: the antlers flung back as it howls at the sky, then the forelegs buckle under the chest and it
# sinks onto its belly and slumps forward, the head and antlers sagging down to the ground.
GRIMM_LOOK_UP = {'Root': (0, 0, 0), 'loc': (0, .03, 0), 'Hips': (-.1, 0, 0), 'Spine': (-.05, 0, 0), 'Chest': (-.1, 0, 0),
                 'Neck': (-.6, 0, 0), 'Head': (-.5, 0, .05), 'Jaw': (.45, 0, 0),
                 'LeftArm': (.2, 0, 0), 'RightArm': (.2, 0, 0), 'Tail': (.2, 0, 0)}
GRIMM_SAG = {'Root': (0, 0, 0), 'loc': (0, .04, -.06), 'Hips': (-.05, 0, 0), 'Chest': (-.05, 0, .04),
             'Neck': (-.45, 0, .05), 'Head': (-.35, 0, .1), 'Jaw': (.4, 0, 0),
             'LeftArm': (.05, 0, 0), 'LeftForeArm': (.25, 0, 0), 'RightArm': (.05, 0, 0), 'RightForeArm': (.25, 0, 0),
             'LeftUpLeg': (.2, 0, 0), 'RightUpLeg': (.2, 0, 0), 'Tail': (-.3, 0, 0), 'Tail1': (-.2, 0, 0)}
GRIMM_SINK = {'Root': (0, 0, 0), 'loc': (0, .04, -.25), 'Hips': (.1, 0, 0), 'Neck': (.15, 0, .1), 'Head': (.2, 0, .15),
              'Jaw': (.35, 0, 0), 'LeftArm': (.5, 0, 0), 'LeftForeArm': (-1.2, 0, 0), 'LeftHand': (.7, 0, 0),
              'RightArm': (.5, 0, 0), 'RightForeArm': (-1.2, 0, 0), 'RightHand': (.7, 0, 0),
              'LeftUpLeg': (.3, 0, 0), 'RightUpLeg': (.3, 0, 0), 'Tail': (-.4, 0, 0), 'Tail1': (-.2, 0, 0)}
GRIMM_SLUMP = {'Root': (0, 0, 0), 'loc': (0, .04, -.32), 'Hips': (.15, 0, 0), 'Neck': (.35, 0, .05), 'Head': (.35, 0, .1),
               'Jaw': (.2, 0, 0), 'LeftArm': (1.2, 0, 0), 'LeftForeArm': (-2.4, 0, 0), 'LeftHand': (1.0, 0, 0),
               'RightArm': (1.2, 0, 0), 'RightForeArm': (-2.4, 0, 0), 'RightHand': (1.0, 0, 0),
               # The curled hind legs swing back out from under the rump and the tail trails out behind, so
               # neither props the body up off the ground.
               'LeftUpLeg': (.7, 0, 0), 'LeftFoot': (.3, 0, 0), 'RightUpLeg': (.7, 0, 0), 'RightFoot': (.3, 0, 0),
               'Tail': (.15, 0, 0), 'Tail1': (.2, 0, 0), 'Tail2': (1.1, 0, 0)}

# The death clips slow down for the final fall (38 to 60), as if in slow motion. Their key frames are
# given at normal pace and stretched by DEATH_PACE (1.5 = the whole clip plays half again as slowly).
DEATH_PACE = 1.5


def death_frame(frame):
    return round(frame * DEATH_PACE)


def death_keys(keys):
    return [(death_frame(frame), pose) for frame, pose in keys]


# Per enemy: (name, frames, loops, pose(frame, frames)). Frames run 0..frames; looped clips end on their
# start pose.
CLIPS = {
    'goblin': [
        ('idle', 48, True, goblin_idle),
        ('walk', 24, True, goblin_walk),
        ('attack', 27, False, lambda f, n: keyed([(0, {}), (9, GOBLIN_WINDUP), (13, GOBLIN_STRIKE), (17, GOBLIN_STRIKE), (27, {})], f)),
        ('guard', 30, False, lambda f, n: blend(keyed([(0, {}), (7, GOBLIN_GUARD)], f), goblin_idle(f, 30), .3 * smooth(f / 7))),
        ('hit', 15, False, lambda f, n: keyed([(0, {}), (3, GOBLIN_HIT), (15, {})], f)),
        ('death', death_frame(82), False, lambda f, n: keyed(death_keys([(0, {}), (9, GOBLIN_LOOK_UP), (24, GOBLIN_SAG), (38, GOBLIN_KNEEL), (60, GOBLIN_SLUMP), (65, blend(GOBLIN_SLUMP, GOBLIN_KNEEL, .1)), (70, GOBLIN_SLUMP), (82, GOBLIN_SLUMP)]), f)),
    ],
    'wolf': [
        ('idle', 48, True, wolf_idle),
        ('walk', 20, True, wolf_walk),
        ('attack', 30, False, lambda f, n: keyed([(0, {'Root': (0, 0, 0)}), (11, WOLF_CLAW_RAISE), (15, WOLF_CLAW_SLAM), (20, WOLF_CLAW_SLAM), (30, {'Root': (0, 0, 0)})], f)),
        ('attack_bite', 23, False, lambda f, n: keyed([(0, {'Root': (0, 0, 0)}), (4, WOLF_WINDUP), (6, WOLF_LEAP), (8, WOLF_BITE), (10, WOLF_BITE_SHAKE), (12, WOLF_BITE), (14, WOLF_PUSH_OFF), (16, WOLF_HOP_BACK), (19, WOLF_LAND), (23, {'Root': (0, 0, 0)})], f)),
        ('guard', 30, False, lambda f, n: blend(keyed([(0, {'Root': (0, 0, 0)}), (7, WOLF_GUARD)], f), wolf_idle(f, 30), .3 * smooth(f / 7))),
        ('hit', 15, False, lambda f, n: keyed([(0, {}), (3, WOLF_HIT), (15, {})], f)),
        ('death', death_frame(82), False, lambda f, n: keyed(death_keys([(0, {}), (9, WOLF_LOOK_UP), (24, WOLF_SAG), (38, WOLF_SINK), (60, WOLF_SLUMP), (65, blend(WOLF_SLUMP, WOLF_SINK, .1)), (70, WOLF_SLUMP), (82, WOLF_SLUMP)]), f)),
    ],
    'grimm': [
        ('idle', 54, True, grimm_idle),
        ('walk', 28, True, grimm_walk),
        ('attack', 34, False, lambda f, n: keyed([(0, {'Root': (0, 0, 0)}), (12, GRIMM_REAR), (16, GRIMM_GORE), (20, GRIMM_TOSS), (23, GRIMM_TOSS), (34, {'Root': (0, 0, 0)})], f)),
        ('attack_bite', 26, False, lambda f, n: keyed([(0, {'Root': (0, 0, 0)}), (6, GRIMM_COIL), (9, GRIMM_LUNGE), (11, GRIMM_SNAP), (13, GRIMM_WRENCH), (15, GRIMM_SNAP), (20, GRIMM_PULL_BACK), (26, {'Root': (0, 0, 0)})], f)),
        ('guard', 30, False, lambda f, n: blend(keyed([(0, {'Root': (0, 0, 0)}), (7, GRIMM_GUARD)], f), grimm_idle(f, 30), .3 * smooth(f / 7))),
        ('hit', 15, False, lambda f, n: keyed([(0, {}), (3, GRIMM_HIT), (15, {})], f)),
        ('death', death_frame(82), False, lambda f, n: keyed(death_keys([(0, {}), (9, GRIMM_LOOK_UP), (24, GRIMM_SAG), (38, GRIMM_SINK), (60, GRIMM_SLUMP), (65, blend(GRIMM_SLUMP, GRIMM_SINK, .1)), (70, GRIMM_SLUMP), (82, GRIMM_SLUMP)]), f)),
    ],
}
# Frames from which the death clip keeps the body on the ground instead of only above it: from the
# moment it has sunk to its knees / belly, so it slumps over along the ground rather than in the air.
GROUNDED_FROM = {'goblin': {'death': death_frame(38)}, 'wolf': {'death': death_frame(38)}, 'grimm': {'death': death_frame(38)}}


def euler_quaternion(xyz):
    return Quaternion((0, 0, 1), xyz[2]) @ Quaternion((0, 1, 0), xyz[1]) @ Quaternion((1, 0, 0), xyz[0])


def apply_pose(rig, pose, lift=0.0):
    for p in rig.pose.bones:
        basis = p.bone.matrix_local.to_quaternion()
        p.rotation_quaternion = basis.inverted() @ euler_quaternion(pose.get(p.name, (0, 0, 0))) @ basis
        p.location = (0, 0, 0)
    root = rig.pose.bones['Root']
    loc = Vector(pose.get('loc', (0, 0, 0))) + Vector((0, 0, lift))
    root.location = root.bone.matrix_local.to_quaternion().inverted() @ loc
    # Root-level offsets ride on Hips so Root can stay the fall pivot.
    hips = rig.pose.bones['Hips']
    if 'Root' not in pose:
        root.location = (0, 0, 0)
        hips.location = hips.bone.matrix_local.to_quaternion().inverted() @ loc


def lowest_point(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    z = min(v.co.z for v in data.vertices)
    evaluated.to_mesh_clear()
    return z


def create_animations(rig, mesh, enemy_id):
    scene = bpy.context.scene
    scene.render.fps = FPS
    rig.animation_data_create()
    for p in rig.pose.bones:
        enum(p, 'rotation_mode', 'QUATERNION')
    clips, grounded_from = CLIPS[enemy_id], GROUNDED_FROM[enemy_id]
    for name, frames, _, pose_at in clips:
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for frame in range(frames + 1):
            pose = pose_at(frame, frames)
            apply_pose(rig, pose)
            # Keep feet (or the fallen body) on the ground: never below it, and resting on it
            # once the death fall lands.
            if 'Root' in pose:
                bpy.context.view_layer.update()
                low = lowest_point(mesh)
                if low < 0 or frame >= grounded_from.get(name, frames + 1):
                    apply_pose(rig, pose, -low)
            for p in rig.pose.bones:
                p.keyframe_insert('rotation_quaternion', frame=frame + 1, group=p.name)
                p.keyframe_insert('location', frame=frame + 1, group=p.name)
    rig.animation_data.action = bpy.data.actions['idle']
    apply_pose(rig, {})
    scene.frame_set(1)
    print('Clips:', [(name, frames) for name, frames, _, _ in clips])


# --- Output -----------------------------------------------------------------------------------

def export(enemy_id, rig, mesh, sockets, shift):
    out = ROOT / f'assets/characters/enemy/{enemy_id}/model.glb'
    out.parent.mkdir(parents=True, exist_ok=True)
    rig['looping_clips'] = [name for name, _, loops, _ in CLIPS[enemy_id] if loops]
    for key, (bone, origin, axes) in sockets.items():
        rig[key] = socket_extras(bone, Vector(origin) + shift, axes)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(out), use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False, export_extras=True, export_yup=True)
    print('ENEMY_EXPORT', out)


def preview(rig, mesh, enemy_id, directory):
    """One row per clip, six frames each, seen from the front-left."""
    view = ENEMIES[enemy_id].get('preview', {})
    scene = bpy.context.scene
    enum(scene.render, 'engine', 'BLENDER_WORKBENCH')
    scene.display.shading.light = 'FLAT'
    scene.display.shading.color_type = 'TEXTURE'
    size = 320
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.world = bpy.data.worlds.new('PreviewWorld')
    scene.world.color = (.55, .6, .65)
    camera = bpy.data.objects.new('PreviewCamera', bpy.data.cameras.new('PreviewCamera'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = view.get('scale', 1.6)
    direction = Vector(view.get('direction', (-.7, -1, .25))).normalized()
    camera.location = Vector(view.get('target', (0, .1, .4))) + direction * 5
    camera.rotation_euler = (-direction).to_track_quat('-Z', 'Y').to_euler()
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, frames, _, _ in CLIPS[enemy_id]:
        rig.animation_data.action = bpy.data.actions[name]
        row = []
        for k in range(6):
            scene.frame_set(1 + round(frames * k / 5))
            path = directory / f'_frame.png'
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            image = bpy.data.images.load(str(path))
            row.append(np.array(image.pixels[:]).reshape(size, size, 4))
            bpy.data.images.remove(image)
        rows.append(np.concatenate(row, axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)  # Blender images start at the bottom row.
    image = bpy.data.images.new('sheet', sheet.shape[1], sheet.shape[0])
    image.pixels[:] = sheet.ravel()
    image.filepath_raw = str(directory / 'clips.png')
    image.file_format = 'PNG'
    image.save()
    print('PREVIEW', directory / 'clips.png', 'rows:', [name for name, *_ in CLIPS[enemy_id]])


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', required=True, choices=sorted(ENEMIES))
    parser.add_argument('--preview')
    parser.add_argument('--no-export', action='store_true')
    args = parser.parse_args(argv)
    spec = ENEMIES[args.id]
    mesh = import_source(args.id)
    remove_strays(mesh, spec)
    if 'even_sides' in spec:
        even_sides(mesh, spec)
    # Enemies without equipment (the wolf) have no sockets and export only their body.
    parts, sockets = [], {}
    if 'weapon' in spec:
        weapon, shield, sockets = split_equipment(mesh, spec)
        weapon.hide_render = shield.hide_render = True
        parts = [('weapon', weapon), ('shield', shield)]
    shift = center_on_feet(mesh, spec)
    rig = build_armature(spec['bones'], shift)
    skin(mesh, rig, spec, shift)
    create_animations(rig, mesh, args.id)
    if not args.no_export:
        export(args.id, rig, mesh, sockets, shift)
        equipment = ROOT / 'assets/characters/enemy/equipment'
        for kind, part in parts:
            export_part(part, equipment / f'{kind}/{part.name}/model.glb')
        if parts:
            for kind, entries in EQUIPMENT.items():
                for part_id, entry in entries.items():
                    export_part(library_part(kind, part_id, entry), equipment / f'{kind}/{part_id}/model.glb')
    if args.preview:
        preview(rig, mesh, args.id, args.preview)


if __name__ == '__main__':
    main()
