"""Make humanoid_v1 left/right symmetric: the right side becomes the mirror image of the left.

Body001's Tripo rig bent the right forearm ~13 cm forward with a different roll, left the right
finger bones collapsed at the wrist and set the right knee 7 mm back. Every Body shared that rest,
so the right hand swung and twisted unlike the left in walk/run. This rewrites the shared rig:

1. The donor's right arm geometry is turned about the shoulder/elbow onto the mirrored left arm, then
   the right forearm+hand (about the elbow) and the right shoe (about the ankle) are fitted to the
   mirrored left shapes. Otherwise the right toe is raised ~4 degrees.
2. Every Right* bone takes the mirrored head/tail/roll of its Left* counterpart (midline = hips X).
3. Donor vertices right of the midline take the mirrored left weights (Left/Right groups swapped).
4. In the idle arm pose, the right forearm (about the elbow) and then the right fist (about the wrist)
   are turned to point the way the mirrored left ones do, and the weights are mirrored again.

Run once in a fresh Blender process; it overwrites assets/characters/_shared/rigs/humanoid_v1.glb:
  blender -b --factory-startup --python symmetrize_reference_rig.py
Then rebuild every Body with build_modular_parts.py.
"""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_characters import align_arms, rotate_region, smoothstep
from build_golden_path import arm_hang

ROOT = Path(__file__).resolve().parents[3]
REFERENCE_RIG = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"


def mirror_name(name):
    if "Left" in name:
        return name.replace("Left", "Right")
    if "Right" in name:
        return name.replace("Right", "Left")
    return name


def mirrored_copy(mesh, x0):
    """A static copy of mesh reflected across the plane x = x0 (faces flipped back outward)."""
    copy = bpy.data.objects.new(mesh.name + "_mirror", mesh.data.copy())
    bpy.context.scene.collection.objects.link(copy)
    copy.data.transform(Matrix.Translation((x0, 0, 0)) @ Matrix.Diagonal((-1, 1, 1, 1)) @ Matrix.Translation((-x0, 0, 0)))
    copy.data.flip_normals()
    return copy


def fit_rotation(mesh, x0, select, pivot):
    """Rotation about pivot (on the left side) that best lays the mirrored right selection onto the left."""
    points = np.array([v.co[:] for v in mesh.data.vertices])
    offset = points[:, 0] - x0
    right = points[select(-offset, points)].copy()
    right[:, 0] = 2 * x0 - right[:, 0]
    return icp_rotation(points[select(offset, points)], right, pivot)


def icp_rotation(left, right, pivot, iterations=40):
    """Rotation about pivot that best lays the point set right onto left.

    Rigid ICP with rotation only; the farthest 15% of pairs each round are ignored, since the two sides
    are not identical shapes (the right glove is a different fist).
    """
    tree = kdtree.KDTree(len(left))
    for index, point in enumerate(left):
        tree.insert(point, index)
    tree.balance()
    pivot = np.array(pivot[:])
    rotation = np.eye(3)
    moved = np.array(right, dtype=float)
    for _ in range(iterations):
        nearest = np.array([tree.find(point)[0][:] for point in moved])
        distance = np.linalg.norm(nearest - moved, axis=1)
        keep = distance < np.percentile(distance, 85)
        u, _, vt = np.linalg.svd((moved[keep] - pivot).T @ (nearest[keep] - pivot))
        step = vt.T @ np.diag([1, 1, np.sign(np.linalg.det(vt.T @ u.T))]) @ u.T
        moved = (step @ (moved - pivot).T).T + pivot
        rotation = step @ rotation
    return Matrix(rotation.tolist())


def match_right_extremities(mesh, rig, x0):
    """Turn the right forearm+hand about the elbow and the right shoe about the ankle onto the mirrored left."""
    flip = Matrix.Diagonal((-1, 1, 1))
    reflect = lambda point: Vector((2 * x0 - point.x, point.y, point.z))
    elbow = rig.data.bones["mixamorig:LeftForeArm"].head_local
    ankle = rig.data.bones["mixamorig:LeftFoot"].head_local
    elbow_x, reach = elbow.x - x0, 0.03
    regions = (
        # T-pose arm beyond the elbow, above the belt pouches.
        ("forearm_hand", elbow, lambda off, p: (off > elbow_x + 0.01) & (p[:, 2] > 0.64),
         lambda co: smoothstep(elbow_x - reach, elbow_x + reach, x0 - co.x) * smoothstep(0.60, 0.66, co.z)),
        # The shoe up to the ankle cuff; the boot shaft above blends back to rest.
        ("shoe", ankle, lambda off, p: (off > 0.03) & (p[:, 2] < 0.12),
         lambda co: (1 - smoothstep(0.10, 0.16, co.z)) * smoothstep(0.01, 0.04, x0 - co.x)),
    )
    report = {}
    for name, pivot, select, weight in regions:
        rotation = flip @ fit_rotation(mesh, x0, select, pivot) @ flip
        moved = rotate_region(mesh, reflect(pivot), rotation.to_quaternion(), weight)
        report[name] = dict(angle_degrees=round(math.degrees(rotation.to_quaternion().angle), 2), moved_vertices=moved)
    return report


def fit_right_forearm(mesh, rig, x0):
    """Turn the right T-pose forearm+hand about the elbow onto the mirrored left one (rest space, by ICP).

    Unlike match_right_extremities it reaches down to the hips' height, for a glove that droops below
    the arm line (Body004). The drooping glove hangs against the belt pouch, so position alone cannot
    tell them apart: below the arm line a vertex moves only when the turn brings it nearer the mirrored
    left surface.
    """
    flip = Matrix.Diagonal((-1, 1, 1))
    elbow = rig.data.bones["mixamorig:LeftForeArm"].head_local
    elbow_x = elbow.x - x0
    select = lambda off, p: (off > elbow_x + 0.02) & (p[:, 2] > 0.45)
    rotation = (flip @ fit_rotation(mesh, x0, select, elbow) @ flip).to_quaternion()
    pivot = Vector((2 * x0 - elbow.x, elbow.y, elbow.z))
    mirror = mirrored_copy(mesh, x0)
    mirror.data.calc_loop_triangles()
    tree = BVHTree.FromPolygons([v.co.copy() for v in mirror.data.vertices],
                                [tuple(t.vertices) for t in mirror.data.loop_triangles], all_triangles=True)
    bpy.data.objects.remove(mirror, do_unlink=True)
    fits = lambda co: tree.find_nearest(pivot + rotation @ (co - pivot))[3] < tree.find_nearest(co)[3]
    moved = rotate_region(mesh, pivot, rotation, lambda co: smoothstep(
        elbow_x - 0.03, elbow_x + 0.03, x0 - co.x) * (co.z > 0.60 or (co.z > 0.25 and fits(co))))
    return dict(angle_degrees=round(math.degrees(rotation.angle), 2), moved_vertices=moved)


def hang_arms(rig, hang):
    """Pose the arms as the shared clips hang them (None for the rest pose)."""
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        rotation = hang.get(pose_bone.name) if hang else None
        if rotation is None:
            pose_bone.matrix_basis = Matrix.Identity(4)
        else:
            basis = pose_bone.bone.matrix_local.to_quaternion()
            pose_bone.rotation_quaternion = basis.inverted() @ rotation @ basis
    bpy.context.view_layer.update()


def match_right_hand(mesh, rig, x0):
    """Lay the idle right forearm, then the right fist, the way the mirrored left ones lie.

    The left glove is curled down at the wrist while the right one is held nearly straight and reaches
    ~5 cm farther, so the idle right fist hung lower, in front of the belt pouch, and bent at another
    angle and twist. Each step fits, in the hung pose (build_golden_path.arm_hang), the right span beyond
    its joint onto the mirrored left one by ICP about the joint, then turns the rest geometry beyond that
    joint by the same amount. Needs the (mirrored) weights already.
    """
    hang = arm_hang(rig)
    flip = Matrix.Diagonal((-1, 1, 1))
    elbow_x = rig.data.bones["mixamorig:LeftForeArm"].head_local.x - x0
    wrist_x = rig.data.bones["mixamorig:LeftHand"].head_local.x - x0
    # (joint bone, T-pose span fitted beyond it, as a distance from the midline)
    steps = (("ForeArm", elbow_x + 0.01), ("Hand", wrist_x - 0.005))
    report = {}
    for bone_name, lo in steps:
        hang_arms(rig, hang)
        posed = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices
        joint = rig.pose.bones["mixamorig:Right" + bone_name]
        spans = []
        for side in (1, -1):
            span = np.array([posed[v.index].co[:] for v in mesh.data.vertices if side * (v.co.x - x0) > lo and v.co.z > 0.64])
            if side < 0:
                span[:, 0] = 2 * x0 - span[:, 0]
            spans.append(span)
        pivot = Vector((2 * x0 - joint.head.x, joint.head.y, joint.head.z))
        turn = (flip @ icp_rotation(spans[0], spans[1], pivot) @ flip).to_quaternion()
        # Back to rest space through the posed bone's turn, about the rest joint.
        posed_turn = (joint.matrix.to_3x3() @ joint.bone.matrix_local.to_3x3().inverted()).to_quaternion()
        rotation = posed_turn.inverted() @ turn @ posed_turn
        hang_arms(rig, None)
        pivot_x = x0 - joint.bone.head_local.x
        reach = 0.03 if bone_name == "ForeArm" else 0.015
        moved = rotate_region(mesh, joint.bone.head_local, rotation, lambda co: smoothstep(
            pivot_x - reach, pivot_x + reach, x0 - co.x) * smoothstep(0.60, 0.66, co.z))
        report[bone_name] = dict(angle_degrees=round(math.degrees(rotation.angle), 2), moved_vertices=moved)
    # Now pointing the same way, the longer right arm would still hang the fist ~4 cm low behind the pouch:
    # shorten the forearm and hand along the forearm until the fist is as far from the elbow as the left one.
    hang_arms(rig, hang)
    posed = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices
    in_fist = lambda co, side: side * (co.x - x0) > wrist_x - 0.005 and co.z > 0.64
    reach = []
    for side, prefix in ((1, "mixamorig:Left"), (-1, "mixamorig:Right")):
        fist = [posed[v.index].co for v in mesh.data.vertices if in_fist(v.co, side)]
        reach.append((sum(fist, Vector()) / len(fist) - rig.pose.bones[prefix + "ForeArm"].head).length)
    hang_arms(rig, None)
    forearm = rig.data.bones["mixamorig:RightForeArm"]
    # Along the elbow-to-fist line, which the turns above already point the left one's way.
    fist = [v.co for v in mesh.data.vertices if in_fist(v.co, -1)]
    axis = (sum(fist, Vector()) / len(fist) - forearm.head_local).normalized()
    scale = reach[0] / reach[1]
    pivot_x = x0 - forearm.head_local.x
    for vertex in mesh.data.vertices:
        weight = smoothstep(pivot_x - 0.03, pivot_x + 0.03, x0 - vertex.co.x) * smoothstep(0.60, 0.66, vertex.co.z)
        along = (vertex.co - forearm.head_local).dot(axis)
        if weight > 0 and along > 0:
            vertex.co -= axis * along * (1 - scale) * weight
    mesh.data.update()
    report["shorten"] = round(scale, 3)
    return report


def symmetrize_bones(rig, x0):
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = rig.data.edit_bones
    reflect = lambda point: Vector((2 * x0 - point.x, point.y, point.z))
    moved = []
    for bone in bones:
        if "Right" not in bone.name:
            continue
        left = bones[mirror_name(bone.name)]
        bone.head = reflect(left.head)
        bone.tail = reflect(left.tail)
        bone.roll = -left.roll
        moved.append(bone.name)
    bpy.ops.object.mode_set(mode="OBJECT")
    return moved


def mirror_weights(mesh, x0):
    """Right-half vertices take the barycentric weights of the mirrored left surface."""
    mirror = mirrored_copy(mesh, x0)
    mirror.data.calc_loop_triangles()
    verts = [v.co.copy() for v in mirror.data.vertices]
    triangles = [tuple(t.vertices) for t in mirror.data.loop_triangles]
    tree = BVHTree.FromPolygons(verts, triangles, all_triangles=True)
    names = {group.index: group.name for group in mesh.vertex_groups}
    by_name = {group.name: group for group in mesh.vertex_groups}
    for name in [mirror_name(name) for name in names.values()]:
        if name not in by_name:
            by_name[name] = mesh.vertex_groups.new(name=name)
    distances = []
    updates = []
    for vertex in mesh.data.vertices:
        if vertex.co.x >= x0:
            continue
        point, _, index, distance = tree.find_nearest(vertex.co)
        distances.append(distance)
        tri = triangles[index]
        bc = barycentric_transform(point, *(verts[i] for i in tri), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        weights = {}
        for vi, influence in zip(tri, bc):
            # The mirror shares vertex indices (and so weights) with the source mesh.
            for group in mesh.data.vertices[vi].groups:
                name = mirror_name(names[group.group])
                weights[name] = weights.get(name, 0) + max(0, influence) * group.weight
        best = sorted(weights.items(), key=lambda pair: pair[1], reverse=True)[:4]
        total = sum(weight for _, weight in best)
        if total <= 0:
            raise ValueError(f"Mirrored weights empty for vertex {vertex.index}")
        updates.append((vertex.index, [(name, weight / total) for name, weight in best if weight > 0]))
    # Write after reading every source weight, so no lookup sees an already mirrored vertex.
    for index, weights in updates:
        for group in list(mesh.data.vertices[index].groups):
            mesh.vertex_groups[group.group].remove([index])
        for name, weight in weights:
            by_name[name].add([index], weight, "REPLACE")
    bpy.data.objects.remove(mirror, do_unlink=True)
    return len(updates), max(distances)


def report_symmetry(rig, x0):
    worst = (0.0, 0.0, "")
    flip = Matrix.Diagonal((-1, 1, 1))
    for bone in rig.data.bones:
        if "Left" not in bone.name:
            continue
        right = rig.data.bones[mirror_name(bone.name)]
        offset = (Vector((2 * x0 - bone.head_local.x, bone.head_local.y, bone.head_local.z)) - right.head_local).length
        left_frame = flip @ bone.matrix_local.to_3x3() @ flip
        # Blender's mirror convention (roll negated): Y along the bone and Z reflect, X reverses.
        right_frame = right.matrix_local.to_3x3()
        angle = max(math.degrees(left_frame.col[1].angle(right_frame.col[1])),
                    math.degrees(left_frame.col[2].angle(right_frame.col[2])))
        if offset + angle > worst[0] + worst[1]:
            worst = (offset, angle, right.name)
    print("SYMMETRY worst head offset %.6f m, axis %.4f deg (%s)" % worst)
    return worst


def main():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(REFERENCE_RIG))
    imported = set(bpy.data.objects) - before
    rig = next(obj for obj in imported if obj.type == "ARMATURE")
    donor = next(obj for obj in rig.children if obj.type == "MESH")
    for obj in imported:
        if obj.type == "MESH" and obj is not donor:
            bpy.data.objects.remove(obj, do_unlink=True)
    for pose_bone in rig.pose.bones:
        pose_bone.custom_shape = None
    if donor.matrix_world != Matrix.Identity(4) or rig.matrix_world != Matrix.Identity(4):
        raise ValueError("Reference rig and donor must have identity transforms")
    x0 = rig.data.bones["mixamorig:Hips"].head_local.x
    target = mirrored_copy(donor, x0)
    print("ARM_ALIGNMENT", align_arms(target, donor, rig, sides=(-1,)))
    bpy.data.objects.remove(target, do_unlink=True)
    print("EXTREMITY_ALIGNMENT", match_right_extremities(donor, rig, x0))
    print("MIRRORED_BONES", len(symmetrize_bones(rig, x0)))
    print("MIRRORED_WEIGHTS vertices=%d max_distance=%.4f" % mirror_weights(donor, x0))
    print("RIGHT_HAND_MATCH", match_right_hand(donor, rig, x0))
    print("MIRRORED_WEIGHTS vertices=%d max_distance=%.4f" % mirror_weights(donor, x0))
    offset, angle, _ = report_symmetry(rig, x0)
    if offset > 1e-4 or angle > 0.05:
        raise ValueError("Rig is not symmetric after mirroring")
    if len(rig.data.bones) != 65 or "head" not in rig.data.bones:
        raise ValueError("Reference asset no longer matches humanoid_v1")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (rig.parent, rig, donor):
        if obj is not None:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(REFERENCE_RIG), use_selection=True, export_animations=False, export_extras=True)
    print("HUMANOID_V1_SYMMETRIC", REFERENCE_RIG)


if __name__ == "__main__":
    main()
