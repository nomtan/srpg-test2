"""Meshy hero: fitted skin, authored in-place idle/walk/run, and Godot export.

Run in the inspected Blender 5.1 scene through Blender MCP, in stages:
    build(); bind(); animate(); validate(); save_and_export()
The original mesh, UVs and packed textures are retained. Blender faces -Y;
the exported wrapper faces +X and measures 2.2 units from sole to hair tip.
"""
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/meshy_hero'
ARTIFACTS = ROOT / 'artifacts/meshy_hero'
GROUND = -0.9503881335258484
RIG = 'Hero_Rig'
MESH = 'Mesh_0'
PERIODS = {'idle': 60, 'walk': 30, 'run': 20}


def smooth(a, b, value):
    t = min(1., max(0., (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def blend(a, b, t):
    result = {k: v * (1 - t) for k, v in a.items()}
    for k, v in b.items():
        result[k] = result.get(k, 0) + v * t
    return result


def enum_value(owner, property_name, value):
    """Check the live RNA before assigning version-dependent enum values."""
    valid = [e.identifier for e in owner.bl_rna.properties[property_name].enum_items]
    if value not in valid:
        raise ValueError((property_name, value, valid))
    setattr(owner, property_name, value)


def mode(value):
    valid = [e.identifier for e in bpy.ops.object.mode_set.get_rna_type().properties['mode'].enum_items]
    assert value in valid
    bpy.ops.object.mode_set(mode=value)


def build():
    assert RIG not in bpy.data.objects, 'Hero rig already exists.'
    mesh = bpy.data.objects[MESH]
    arm = bpy.data.armatures.new('Hero_Skeleton')
    rig = bpy.data.objects.new(RIG, arm)
    mesh.users_collection[0].objects.link(rig)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    mode('EDIT')

    def bone(name, head, tail, parent=None, deform=True):
        b = arm.edit_bones.new(name)
        b.head, b.tail = head, tail
        b.use_deform = deform
        if parent:
            b.parent = arm.edit_bones[parent]

    bone('root', (0, 0, GROUND), (0, 0, GROUND + .15), deform=False)
    bone('pelvis', (0, -.015, -.44), (0, -.015, -.30), 'root')
    bone('spine', (0, -.015, -.30), (0, 0, -.15), 'pelvis')
    bone('chest', (0, 0, -.15), (0, 0, .045), 'spine')
    bone('neck', (0, 0, .045), (0, 0, .17), 'chest')
    bone('head', (0, 0, .17), (0, 0, .66), 'neck')
    for side, sign in [('L', 1), ('R', -1)]:
        bone('clavicle.' + side, (sign * .07, 0, .015), (sign * .30, 0, -.025), 'chest')
        bone('upper_arm.' + side, (sign * .30, 0, -.025), (sign * .435, -.025, -.21), 'clavicle.' + side)
        bone('forearm.' + side, (sign * .435, -.025, -.21), (sign * .565, -.055, -.35), 'upper_arm.' + side)
        bone('hand.' + side, (sign * .565, -.055, -.35), (sign * .60, -.08, -.445), 'forearm.' + side)
        bone('thigh.' + side, (sign * .19, -.015, -.44), (sign * .225, -.07, -.695), 'pelvis')
        bone('shin.' + side, (sign * .225, -.07, -.695), (sign * .235, -.005, -.86), 'thigh.' + side)
        bone('foot.' + side, (sign * .235, -.005, -.86), (sign * .235, -.15, -.913), 'shin.' + side)
        bone('toe.' + side, (sign * .235, -.15, -.913), (sign * .235, -.235, -.913), 'foot.' + side)
        bone('cape.' + side, (sign * .16, .23, .015), (sign * .24, .29, -.38), 'chest')
        bone('cape_tip.' + side, (sign * .24, .29, -.38), (sign * .34, .37, -.76), 'cape.' + side)
    mode('OBJECT')
    enum_value(arm, 'display_type', 'STICK')
    rig.show_in_front = True
    for pb in rig.pose.bones:
        enum_value(pb, 'rotation_mode', 'QUATERNION')
    mesh.parent = rig
    mesh.matrix_parent_inverse = rig.matrix_world.inverted()
    valid = [e.identifier for e in bpy.types.Modifier.bl_rna.properties['type'].enum_items]
    assert 'ARMATURE' in valid
    modifier = mesh.modifiers.new('Hero Skin', 'ARMATURE')
    modifier.object = rig
    # Linear skinning matches the glTF/Godot deformation exactly.
    modifier.use_deform_preserve_volume = False
    rig['source_model'] = 'Meshy hero: original geometry, UVs and three packed PBR textures.'
    rig['animation_notes'] = 'In-place, 30 fps. idle 1-61; walk 1-31; run 1-21. Matching loop endpoints. Front -Y.'
    print('Created', len(arm.bones), 'bones, including four cape bones.')


def bind():
    mesh, rig = bpy.data.objects[MESH], bpy.data.objects[RIG]
    mesh.vertex_groups.clear()
    for bone in rig.data.bones:
        if bone.use_deform:
            mesh.vertex_groups.new(name=bone.name)
    weights = []
    for vertex in mesh.data.vertices:
        x, y, z = vertex.co
        ax = abs(x)
        side = 'L' if x >= 0 else 'R'
        torso = blend({'pelvis': 1}, {'spine': 1}, smooth(-.31, -.22, z))
        torso = blend(torso, {'chest': 1}, smooth(-.19, -.08, z))
        torso = blend(torso, {'neck': 1}, smooth(.015, .095, z))
        torso = blend(torso, {'head': 1}, smooth(.09, .16, z))

        arm = blend({'upper_arm.' + side: 1}, {'forearm.' + side: 1}, 1 - smooth(-.25, -.17, z))
        arm = blend(arm, {'hand.' + side: 1}, 1 - smooth(-.39, -.325, z))
        arm = blend(arm, {'clavicle.' + side: 1}, smooth(-.055, .045, z))
        boundary = .30 + .28 * max(0, -z)
        arm_amount = smooth(boundary - .025, boundary + .045, ax)
        arm_amount *= (1 - smooth(.07, .15, z)) * smooth(-.57, -.51, z)

        leg = blend({'thigh.' + side: 1}, {'shin.' + side: 1}, 1 - smooth(-.745, -.66, z))
        leg = blend(leg, {'foot.' + side: 1}, 1 - smooth(-.86, -.80, z))
        toe = (1 - smooth(-.19, -.14, y)) * (1 - smooth(-.90, -.865, z))
        leg = blend(leg, {'toe.' + side: 1}, toe)
        lower = blend({'pelvis': 1}, leg, (1 - smooth(-.56, -.425, z)) * smooth(.015, .09, ax))
        result = blend(lower, torso, smooth(-.43, -.31, z))
        result = blend(result, arm, arm_amount)

        # The cape overlaps legs in front view: separate it by depth before smoothing.
        cape = blend({'cape.' + side: 1}, {'cape_tip.' + side: 1}, 1 - smooth(-.46, -.32, z))
        if ax < .08:
            other = 'R' if side == 'L' else 'L'
            opposite = {k.replace('.' + side, '.' + other): v for k, v in cape.items()}
            cape = blend(opposite, cape, .5 + .5 * smooth(0, .08, ax))
        cape_amount = smooth(.105 - .10 * z, .18 - .10 * z, y)
        cape_amount *= 1 - smooth(-.055, .075, z)
        result = blend(result, cape, cape_amount)
        weights.append(result)

    adjacency = [{} for _ in mesh.data.vertices]
    for edge in mesh.data.edges:
        a, b = edge.vertices
        distance = (mesh.data.vertices[a].co - mesh.data.vertices[b].co).length
        w = 1 / max(distance, .002) ** 2
        adjacency[a][b] = w
        adjacency[b][a] = w
    for _ in range(4):
        updated = []
        for i, entries in enumerate(weights):
            neighbors = adjacency[i]
            average = {}
            total = sum(neighbors.values())
            for j, w in neighbors.items():
                for name, value in weights[j].items():
                    average[name] = average.get(name, 0) + value * w / total
            updated.append(blend(entries, average, .35) if neighbors else entries)
        weights = updated
    valid = [e.identifier for e in bpy.types.VertexGroup.bl_rna.functions['add'].parameters['type'].enum_items]
    assert 'REPLACE' in valid
    for index, entries in enumerate(weights):
        entries = sorted(((k, v) for k, v in entries.items() if v > .0001), key=lambda e: -e[1])[:4]
        total = sum(v for _, v in entries)
        for name, value in entries:
            mesh.vertex_groups[name].add([index], value / total, 'REPLACE')
    print('Bound all', len(weights), 'vertices; normalized to at most four influences.')


def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def animate():
    rig, mesh = bpy.data.objects[RIG], bpy.data.objects[MESH]
    rig.animation_data_clear()
    rig.animation_data_create()
    for name in PERIODS:
        if name in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[name])
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    vectors = {b.name: b.tail_local - b.head_local for b in rig.data.bones}
    soles = {side: [v.co - rig.data.bones['foot.' + side].head_local for v in mesh.data.vertices
                    if v.co.x * sign > .07 and v.co.z < -.875]
             for side, sign in [('L', 1), ('R', -1)]}

    def inherited(pose, name):
        parent = rig.data.bones[name].parent.name
        return pose[parent] @ rest[parent].inverted() @ rest[name]

    def aim(name, origin, direction):
        q = vectors[name].normalized().rotation_difference(Vector(direction).normalized())
        result = q.to_matrix().to_4x4() @ rest[name]
        result.translation = origin
        return result

    def rotate_at(matrix, angle, axis):
        return Matrix.Translation(matrix.translation) @ Matrix.Rotation(angle, 4, axis) @ matrix.to_3x3().to_4x4()

    for clip, period in PERIODS.items():
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        action['loop'] = True
        rig.animation_data.action = action
        previous = {}
        moving, running = clip != 'idle', clip == 'run'
        for frame in range(1, period + 2):
            cycle = (frame - 1) / period
            theta = math.tau * cycle
            pose = {'root': rest['root'].copy()}
            drop = -.070 if running else (-.037 if moving else -.01)
            bob = (.019 if running else .008) * (1 - math.cos(2 * theta)) if moving else .002 * math.sin(theta)
            shift = Vector((.008 * math.sin(theta) if moving else 0, -.015 if running else 0, drop + bob))
            pose['pelvis'] = rest['pelvis'].copy()
            pose['pelvis'].translation += shift
            if moving:
                pose['pelvis'] = rotate_at(pose['pelvis'], .025 * math.sin(theta), 'Z')
            pose['spine'] = inherited(pose, 'spine')
            pose['spine'] = rotate_at(pose['spine'], math.radians(9 if running else 1.5), 'X')
            pose['chest'] = inherited(pose, 'chest')
            pose['chest'] = rotate_at(pose['chest'], (.045 if running else .025) * math.sin(theta) if moving else 0, 'Z')
            pose['neck'] = inherited(pose, 'neck')
            pose['head'] = rest['head'].copy()
            pose['head'].translation = inherited(pose, 'head').translation
            pose['head'] = rotate_at(pose['head'], math.radians(3 if running else 0), 'X')

            for side, sign, offset in [('L', 1, 0), ('R', -1, .5)]:
                u = (cycle + offset) % 1
                phase = math.tau * u
                stance = .40 if running else .60
                stride = .205 if running else .125
                if not moving:
                    foot_y, lift, pitch = -.005, 0., 0.
                elif u < stance:
                    foot_y = -.005 - stride + 2 * stride * u / stance
                    lift = 0.
                    pitch = math.radians(6) * (1 - smooth(0, .09, u)) - math.radians(14 if running else 9) * smooth(stance - .12, stance, u)
                else:
                    t = (u - stance) / (1 - stance)
                    foot_y = -.005 + stride - 2 * stride * smooth(0, 1, t)
                    lift = (.17 if running else .075) * math.sin(math.pi * t) ** 1.4
                    pitch = math.radians((-14 if running else -9) + (20 if running else 15) * smooth(0, 1, t))
                foot_rotation = Matrix.Rotation(pitch, 4, 'X')
                sole = min((foot_rotation.to_3x3() @ v).z for v in soles[side])
                ankle = Vector((sign * .235, foot_y, GROUND - sole + lift))
                thigh, shin, foot = ('thigh.' + side, 'shin.' + side, 'foot.' + side)
                hip = inherited(pose, thigh).translation
                la, lb = vectors[thigh].length, vectors[shin].length
                delta = ankle - hip
                distance = min(delta.length, la + lb - .0001)
                direction = delta.normalized()
                # Keep both segment lengths fixed if the desired stride is out of reach.
                ankle = hip + direction * distance
                along = (la * la - lb * lb + distance * distance) / (2 * distance)
                bend = Vector((0, -1, 0))
                bend = (bend - direction * bend.dot(direction)).normalized()
                knee = hip + direction * along + bend * math.sqrt(max(0, la * la - along * along))
                pose[thigh] = aim(thigh, hip, knee - hip)
                pose[shin] = aim(shin, knee, ankle - knee)
                pose[foot] = foot_rotation @ rest[foot]
                pose[foot].translation = ankle
                pose['toe.' + side] = inherited(pose, 'toe.' + side)

                clavicle = 'clavicle.' + side
                pose[clavicle] = inherited(pose, clavicle)
                upper, forearm, hand = ('upper_arm.' + side, 'forearm.' + side, 'hand.' + side)
                shoulder = inherited(pose, upper).translation
                swing = (.70 if running else .32) * math.cos(phase) if moving else 0
                upper_dir = Vector((sign * .46, swing, -.88)).normalized()
                lower_dir = Vector((sign * .27, swing - (.88 if running else .20), -.65 if running else -.94)).normalized()
                elbow = shoulder + upper_dir * vectors[upper].length
                wrist = elbow + lower_dir * vectors[forearm].length
                pose[upper] = aim(upper, shoulder, upper_dir)
                pose[forearm] = aim(forearm, elbow, lower_dir)
                pose[hand] = aim(hand, wrist, lower_dir)
                cape, tip = 'cape.' + side, 'cape_tip.' + side
                pose[cape] = inherited(pose, cape)
                flutter = math.sin(2 * theta - .6 + sign * .2)
                angle = (11 if running else 4 if moving else 0) + (2.5 if moving else .4) * flutter
                pose[cape] = rotate_at(pose[cape], math.radians(angle), 'X')
                pose[tip] = inherited(pose, tip)
                pose[tip] = rotate_at(pose[tip], math.radians((7 if running else 2 if moving else 0) + (3 if moving else .6) * math.sin(2 * theta - 1.2 + sign * .3)), 'X')

            for pb in rig.pose.bones:
                if pb.parent:
                    basis = rest[pb.name].inverted() @ rest[pb.parent.name] @ pose[pb.parent.name].inverted() @ pose[pb.name]
                else:
                    basis = rest[pb.name].inverted() @ pose[pb.name]
                loc, quat, _ = basis.decompose()
                if pb.name in previous and quat.dot(previous[pb.name]) < 0:
                    quat.negate()
                previous[pb.name] = quat.copy()
                pb.location, pb.rotation_quaternion, pb.scale = loc, quat, (1, 1, 1)
                pb.keyframe_insert(data_path='location', frame=frame, group=pb.name)
                pb.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=pb.name)
        for curve in curves(action):
            for key in curve.keyframe_points:
                enum_value(key, 'interpolation', 'LINEAR')
        print('Created', clip, 'frames 1..', period + 1)
    scene = bpy.context.scene
    scene.render.fps, scene.render.fps_base = 30, 1
    show('walk', 1)


def show(clip='walk', frame=1, side=False):
    rig = bpy.data.objects[RIG]
    rig.animation_data.action = bpy.data.actions[clip]
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, PERIODS[clip]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            space = area.spaces.active
            enum_value(space.shading, 'type', 'MATERIAL')
            enum_value(space.region_3d, 'view_perspective', 'ORTHO')
            space.region_3d.view_location = (0, 0, -.04)
            space.region_3d.view_distance = 3.1
            space.region_3d.view_rotation = Quaternion((0, 0, 1), math.pi / 2 if side else .35) @ Quaternion((1, 0, 0), math.pi / 2)
            space.overlay.show_overlays = False


def validate():
    mesh, rig = bpy.data.objects[MESH], bpy.data.objects[RIG]
    sums = [sum(g.weight for g in v.groups) for v in mesh.data.vertices]
    result = {'bones': len(rig.data.bones), 'vertices': len(mesh.data.vertices),
              'unweighted_vertices': sum(not v.groups for v in mesh.data.vertices),
              'max_influences': max(len(v.groups) for v in mesh.data.vertices),
              'weight_sum_range': [min(sums), max(sums)], 'clips': {}}
    assert result['unweighted_vertices'] == 0 and result['max_influences'] <= 4
    assert max(abs(s - 1) for s in sums) < .00001
    for clip, period in PERIODS.items():
        rig.animation_data.action = bpy.data.actions[clip]
        endpoints, floors = [], []
        for frame in range(1, period + 2):
            bpy.context.scene.frame_set(frame)
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            data = evaluated.to_mesh()
            points = [v.co.copy() for v in data.vertices]
            assert all(math.isfinite(c) for v in points for c in v)
            floors.append(min(v.z for v in points) - GROUND)
            if frame in (1, period + 1):
                endpoints.append(points)
            evaluated.to_mesh_clear()
        seam = max((a - b).length for a, b in zip(*endpoints))
        assert seam < .00001, (clip, seam)
        assert min(floors) > -.001, (clip, 'ground penetration', min(floors))
        if clip != 'run':
            assert max(floors) < .001, (clip, 'lost ground contact', max(floors))
        result['clips'][clip] = {'duration': period / 30, 'loop_seam': seam, 'floor_range': [min(floors), max(floors)]}
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    (ARTIFACTS / 'validation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    show('walk', 1)
    return result


def save_and_export():
    import io_scene_gltf2

    rig = bpy.data.objects[RIG]
    export_rna = bpy.ops.export_scene.gltf.get_rna_type()
    assert 'ACTIONS' in [e.identifier for e in export_rna.properties['export_animation_mode'].enum_items]
    assert 'GLB' in [e[0] for e in io_scene_gltf2.get_format_items(None, bpy.context)]
    show('walk', 1)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'hero.blend'))
    wrapper = bpy.data.objects.new('MeshyHero', None)
    bpy.context.scene.collection.objects.link(wrapper)
    scale = 2.2 / (0.9498060941696167 - GROUND)
    wrapper.rotation_euler.z = math.pi / 2
    wrapper.scale = (scale,) * 3
    wrapper.location.z = -GROUND * scale
    rig.parent = wrapper
    rig.matrix_parent_inverse = Matrix.Identity(4)
    rig.animation_data.action = bpy.data.actions['idle']
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    try:
        bpy.ops.export_scene.gltf(
            filepath=str(OUT / 'hero.glb'), export_format='GLB', export_yup=True,
            export_animations=True, export_animation_mode='ACTIONS',
            export_frame_range=False, export_force_sampling=True, export_frame_step=1,
            export_anim_slide_to_zero=True, export_skins=True, export_all_influences=False,
            export_apply=False, export_morph=False, export_rest_position_armature=True,
            export_optimize_animation_size=False, export_cameras=False, export_lights=False,
        )
    finally:
        rig.parent = None
        rig.matrix_parent_inverse = Matrix.Identity(4)
        bpy.data.objects.remove(wrapper, do_unlink=True)
        show('walk', 1)
    data = (OUT / 'hero.glb').read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + length])
    clips = {a['name']: max(gltf['accessors'][s['input']]['max'][0] for s in a['samplers']) for a in gltf['animations']}
    assert set(clips) == set(PERIODS), clips
    assert len(gltf['skins']) == 1 and len(gltf['skins'][0]['joints']) == 26
    assert len(gltf['images']) == 3
    print(json.dumps({'export': str(OUT / 'hero.glb'), 'bytes': len(data), 'clips': clips, 'bones': 26, 'textures': 3, 'front': '+X', 'height': 2.2}, indent=2))


if __name__ == '__main__':
    bpy.ops.wm.open_mainfile(filepath=str(ARTIFACTS / 'hero_before_rig.blend'))
    build()
    bind()
    animate()
    validate()
    save_and_export()
