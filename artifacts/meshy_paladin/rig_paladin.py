"""Build a texture-preserving FK rig and in-place walk for the open Meshy paladin.

Run in Blender's Python context, then call build(), bind(), animate().
The original mesh/UVs/materials are preserved. Assumes the inspected T-pose.
"""
import bpy
import json
import math
from mathutils import Matrix, Vector

RIG_NAME = 'Paladin_Rig'
MESH_NAME = 'output_unwrapped'
PERIOD = 32
GROUND = -0.95002400875


def smooth(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def blend(a, b, t):
    result = {k: v * (1.0 - t) for k, v in a.items()}
    for k, v in b.items():
        result[k] = result.get(k, 0.0) + v * t
    return result


def build():
    obj = bpy.data.objects[MESH_NAME]
    if RIG_NAME in bpy.data.objects:
        raise RuntimeError('Rig already exists; use bind/animate for refinements.')
    arm = bpy.data.armatures.new('Paladin_Skeleton')
    rig = bpy.data.objects.new(RIG_NAME, arm)
    obj.users_collection[0].objects.link(rig)
    for selected in list(bpy.context.selected_objects):
        selected.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')

    def bone(name, head, tail, parent=None, deform=True):
        b = arm.edit_bones.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = arm.edit_bones[parent]
        b.use_deform = deform
        return b

    bone('root', (0, 0, GROUND), (0, 0, GROUND + .16), deform=False)
    bone('pelvis', (0, 0, -.32), (0, 0, -.20), 'root')
    bone('spine', (0, 0, -.20), (0, 0, -.06), 'pelvis')
    bone('chest', (0, 0, -.06), (0, 0, .12), 'spine')
    bone('neck', (0, 0, .12), (0, 0, .24), 'chest')
    bone('head', (0, 0, .24), (0, 0, .72), 'neck')
    for side, sign in [('L', 1), ('R', -1)]:
        bone('clavicle.' + side, (sign * .09, 0, .085), (sign * .29, 0, .035), 'chest')
        bone('upper_arm.' + side, (sign * .29, 0, .035), (sign * .505, 0, .022), 'clavicle.' + side)
        bone('forearm.' + side, (sign * .505, 0, .022), (sign * .685, 0, .02), 'upper_arm.' + side)
        bone('hand.' + side, (sign * .685, 0, .02), (sign * .80, 0, .02), 'forearm.' + side)
        bone('thigh.' + side, (sign * .17, 0, -.32), (sign * .19, -.055, -.585), 'pelvis')
        bone('shin.' + side, (sign * .19, -.055, -.585), (sign * .20, 0, -.845), 'thigh.' + side)
        bone('foot.' + side, (sign * .20, 0, -.845), (sign * .20, -.145, -.91), 'shin.' + side)
        bone('toe.' + side, (sign * .20, -.145, -.91), (sign * .20, -.235, -.91), 'foot.' + side)
    bone('tabard', (0, -.235, -.27), (0, -.25, -.47), 'pelvis')
    bone('tabard_tip', (0, -.25, -.47), (0, -.265, -.68), 'tabard')
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.display_type = 'STICK'
    rig.show_in_front = True
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    mod = obj.modifiers.new('Paladin skin', 'ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = True
    rig['animation_notes'] = 'Walk_InPlace: 24 fps, frames 1-32; matching loop endpoint at 33. Front is -Y. FK bones; root translates the whole character.'
    rig['source_model'] = 'Meshy Blue Plume Paladin; original geometry, UVs, and packed textures.'
    print('Created', len(arm.bones), 'bones.')


def bind():
    obj = bpy.data.objects[MESH_NAME]
    rig = bpy.data.objects[RIG_NAME]
    obj.vertex_groups.clear()
    for bone in rig.data.bones:
        if bone.use_deform:
            obj.vertex_groups.new(name=bone.name)
    weights = []
    for v in obj.data.vertices:
        x, y, z = v.co
        ax = abs(x)
        side = 'L' if x >= 0 else 'R'
        torso = blend({'pelvis': 1}, {'spine': 1}, smooth(-.25, -.15, z))
        torso = blend(torso, {'chest': 1}, smooth(-.14, -.025, z))
        torso = blend(torso, {'neck': 1}, smooth(.10, .19, z))
        torso = blend(torso, {'head': 1}, smooth(.13, .235, z))

        arm = blend({'upper_arm.' + side: 1}, {'forearm.' + side: 1}, smooth(.465, .535, ax))
        arm = blend(arm, {'hand.' + side: 1}, smooth(.66, .71, ax))
        shoulder_cap = smooth(.045, .13, z) * (1 - smooth(.34, .415, ax))
        arm = blend(arm, {'clavicle.' + side: 1}, shoulder_cap)
        arm_amount = smooth(.225, .345, ax) * (1 - smooth(.145, .25, z)) * smooth(-.21, -.11, z)
        upper = blend(torso, arm, arm_amount)

        leg = blend({'thigh.' + side: 1}, {'shin.' + side: 1}, 1 - smooth(-.64, -.545, z))
        leg = blend(leg, {'foot.' + side: 1}, 1 - smooth(-.865, -.795, z))
        toe_amount = (1 - smooth(-.205, -.14, y)) * (1 - smooth(-.88, -.83, z))
        leg = blend(leg, {'toe.' + side: 1}, toe_amount)
        lower = blend({'pelvis': 1}, leg, 1 - smooth(-.39, -.255, z))
        cloth_amount = (1 - smooth(.12, .175, ax)) * (1 - smooth(-.225, -.165, y))
        cloth_amount *= smooth(-.745, -.685, z) * (1 - smooth(-.30, -.235, z))
        cloth = blend({'tabard': 1}, {'tabard_tip': 1}, 1 - smooth(-.53, -.42, z))
        lower = blend(lower, cloth, cloth_amount)
        result = blend(lower, upper, smooth(-.255, -.145, z))
        weights.append(result)

    # Relax transitions across the connected generated surface, retaining rigid interiors.
    adjacency = [{} for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        distance = (obj.data.vertices[a].co - obj.data.vertices[b].co).length
        influence = 1.0 / max(distance, .002) ** 2
        adjacency[a][b] = influence
        adjacency[b][a] = influence
    for _ in range(5):
        updated = []
        for idx, current in enumerate(weights):
            neighbors = adjacency[idx]
            if not neighbors:
                updated.append(current)
                continue
            mean = {}
            normalization = sum(neighbors.values())
            for j, influence in neighbors.items():
                for name, value in weights[j].items():
                    mean[name] = mean.get(name, 0.0) + value * influence / normalization
            updated.append(blend(current, mean, .45))
        weights = updated
    for idx, entries in enumerate(weights):
        kept = sorted(((n, w) for n, w in entries.items() if w > .0001), key=lambda item: -item[1])[:4]
        total = sum(w for _, w in kept)
        for name, value in kept:
            obj.vertex_groups[name].add([idx], value / total, 'REPLACE')
    print('Bound', len(weights), 'vertices with normalized weights, max 4 influences.')


def action_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def animate():
    rig = bpy.data.objects[RIG_NAME]
    obj = bpy.data.objects[MESH_NAME]
    rig.animation_data_clear()
    rig.animation_data_create()
    action = bpy.data.actions.new('Walk_InPlace')
    action.use_fake_user = True
    rig.animation_data.action = action
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    vectors = {b.name: b.tail_local - b.head_local for b in rig.data.bones}
    soles = {}
    for side, sign in [('L', 1), ('R', -1)]:
        ankle = rig.data.bones['foot.' + side].head_local
        soles[side] = [v.co - ankle for v in obj.data.vertices if v.co.x * sign > .07 and v.co.z < -.86]

    def aim(name, head, direction):
        q = vectors[name].normalized().rotation_difference(Vector(direction).normalized())
        result = q.to_matrix().to_4x4() @ rest[name]
        result.translation = head
        return result

    def inherited(matrices, name):
        bone = rig.data.bones[name]
        return matrices[bone.parent.name] @ rest[bone.parent.name].inverted() @ rest[name]

    previous_quats = {}
    for frame in range(1, PERIOD + 2):
        cycle = (frame - 1) / PERIOD
        theta = 2 * math.pi * cycle
        matrices = {'root': rest['root'].copy()}
        hip_shift = Vector((.011 * math.sin(theta), 0, -.035 + .008 * math.cos(2 * theta)))
        pelvis_rot = Matrix.Rotation(math.radians(1.5) * math.sin(theta), 4, 'Y')
        matrices['pelvis'] = Matrix.Translation(rest['pelvis'].translation + hip_shift) @ pelvis_rot @ rest['pelvis'].to_3x3().to_4x4()
        for name in ['spine', 'chest', 'neck', 'head']:
            matrices[name] = inherited(matrices, name)
        chest_head = matrices['chest'].translation.copy()
        torso_rotation = Matrix.Rotation(math.radians(2.2) * math.sin(theta), 4, 'Z') @ Matrix.Rotation(math.radians(1.2), 4, 'X')
        matrices['chest'] = Matrix.Translation(chest_head) @ torso_rotation @ matrices['chest'].to_3x3().to_4x4()
        matrices['neck'] = inherited(matrices, 'neck')
        matrices['head'] = rest['head'].copy()
        matrices['head'].translation = (matrices['neck'] @ rest['neck'].inverted() @ rest['head']).translation

        for side, sign, offset in [('L', 1, 0.0), ('R', -1, .5)]:
            u = (cycle + offset) % 1.0
            phase = 2 * math.pi * u
            if u < .6:
                foot_y = -.135 + .27 * u / .6
                lift = 0.0
                pitch = math.radians(7) * (1 - smooth(0, .12, u)) - math.radians(11) * smooth(.45, .60, u)
            else:
                t = (u - .6) / .4
                foot_y = .135 - .27 * smooth(0, 1, t)
                lift = .092 * math.sin(math.pi * t) ** 1.5
                pitch = math.radians(-11 + 18 * smooth(0, 1, t))
            foot_rotation = Matrix.Rotation(pitch, 4, 'X')
            sole_min = min((foot_rotation.to_3x3() @ v).z for v in soles[side])
            ankle = Vector((sign * .20, foot_y, GROUND - sole_min + lift))
            thigh_name, shin_name = 'thigh.' + side, 'shin.' + side
            hip = (matrices['pelvis'] @ rest['pelvis'].inverted() @ rest[thigh_name]).translation
            length_a, length_b = vectors[thigh_name].length, vectors[shin_name].length
            delta = ankle - hip
            distance = min(delta.length, length_a + length_b - .0001)
            direction = delta.normalized()
            along = (length_a ** 2 - length_b ** 2 + distance ** 2) / (2 * distance)
            height = math.sqrt(max(0, length_a ** 2 - along ** 2))
            bend = Vector((0, -1, 0))
            bend = (bend - direction * bend.dot(direction)).normalized()
            knee = hip + direction * along + bend * height
            matrices[thigh_name] = aim(thigh_name, hip, knee - hip)
            matrices[shin_name] = aim(shin_name, knee, ankle - knee)
            foot_name = 'foot.' + side
            matrices[foot_name] = foot_rotation @ rest[foot_name]
            matrices[foot_name].translation = ankle
            matrices['toe.' + side] = inherited(matrices, 'toe.' + side)

            clavicle = 'clavicle.' + side
            matrices[clavicle] = inherited(matrices, clavicle)
            upper_name, lower_name, hand_name = 'upper_arm.' + side, 'forearm.' + side, 'hand.' + side
            shoulder = (matrices[clavicle] @ rest[clavicle].inverted() @ rest[upper_name]).translation
            swing = .24 * math.cos(phase)
            upper_direction = Vector((sign * .40, swing, -.92)).normalized()
            elbow = shoulder + upper_direction * vectors[upper_name].length
            lower_direction = Vector((sign * .12, swing - .20, -.98)).normalized()
            wrist = elbow + lower_direction * vectors[lower_name].length
            matrices[upper_name] = aim(upper_name, shoulder, upper_direction)
            matrices[lower_name] = aim(lower_name, elbow, lower_direction)
            matrices[hand_name] = aim(hand_name, wrist, lower_direction)

        matrices['tabard'] = inherited(matrices, 'tabard')
        cloth_pivot = matrices['tabard'].translation.copy()
        cloth_rotation = Matrix.Rotation(math.radians(-7 + 2 * math.sin(2 * theta - .6)), 4, 'X')
        matrices['tabard'] = Matrix.Translation(cloth_pivot) @ cloth_rotation @ matrices['tabard'].to_3x3().to_4x4()
        matrices['tabard_tip'] = inherited(matrices, 'tabard_tip')
        tip_pivot = matrices['tabard_tip'].translation.copy()
        tip_rotation = Matrix.Rotation(math.radians(-3 + 2 * math.sin(2 * theta - 1)), 4, 'X')
        matrices['tabard_tip'] = Matrix.Translation(tip_pivot) @ tip_rotation @ matrices['tabard_tip'].to_3x3().to_4x4()

        for pb in rig.pose.bones:
            if pb.parent:
                basis = rest[pb.name].inverted() @ rest[pb.parent.name] @ matrices[pb.parent.name].inverted() @ matrices[pb.name]
            else:
                basis = rest[pb.name].inverted() @ matrices[pb.name]
            loc, quat, scale = basis.decompose()
            if pb.name in previous_quats and quat.dot(previous_quats[pb.name]) < 0:
                quat.negate()
            previous_quats[pb.name] = quat.copy()
            pb.location = loc
            pb.rotation_quaternion = quat
            pb.scale = (1, 1, 1)
            pb.keyframe_insert(data_path='location', frame=frame, group=pb.name)
            pb.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=pb.name)
    for curve in action_curves(action):
        for point in curve.keyframe_points:
            point.interpolation = 'LINEAR'
        curve.modifiers.new('CYCLES')
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.render.fps_base = 1.0
    scene.frame_start, scene.frame_end = 1, PERIOD
    scene.frame_set(1)
    bpy.context.view_layer.update()
    print('Created', action.name, 'with', len(list(action_curves(action))), 'channels; frames 1-32 at 24 fps.')


def inspect():
    rig, obj = bpy.data.objects[RIG_NAME], bpy.data.objects[MESH_NAME]
    scene = bpy.context.scene
    original = scene.frame_current
    stats = []
    endpoints = []
    for frame in [1, 5, 9, 13, 17, 21, 25, 29, 33]:
        scene.frame_set(frame)
        graph = bpy.context.evaluated_depsgraph_get()
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        points = [v.co.copy() for v in mesh.vertices]
        stats.append({'frame': frame, 'min_z': min(v.z for v in points), 'max_z': max(v.z for v in points), 'width': max(v.x for v in points) - min(v.x for v in points)})
        if frame in [1, 33]:
            endpoints.append(points)
        evaluated.to_mesh_clear()
    scene.frame_set(original)
    sums = [sum(g.weight for g in v.groups) for v in obj.data.vertices]
    result = {'bone_count': len(rig.data.bones), 'unweighted_vertices': sum(1 for v in obj.data.vertices if not v.groups), 'weight_sum_range': [min(sums), max(sums)], 'loop_max_vertex_delta': max((a - b).length for a, b in zip(*endpoints)), 'samples': stats}
    print(json.dumps(result, indent=2))
    return result
