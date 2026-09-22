"""Fitted FK skin for the modular adventurer. Execute stages via Blender MCP.

build(); bind(); animate(); validate(); export()
No mesh reshaping, remeshing, UV0 edits or texture repainting. Face expressions
remain morph targets; all four interchangeable parts use the same named skin.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/meshy_adventure'
ART = ROOT / 'artifacts/meshy_adventure/rig'
RIG = 'Adventurer_Rig'
PARTS = {'AdventurerBody': 'adventurer_body.glb', 'Face': 'face_default.glb',
         'Hair_Tousled': 'hair_tousled.glb', 'Hair_Swept': 'hair_swept.glb'}
CLIPS = {'idle': 90, 'rig_check': 120}


def enum(owner, prop, value):
    assert value in [e.identifier for e in owner.bl_rna.properties[prop].enum_items], (prop, value)
    setattr(owner, prop, value)


def mode(value):
    assert value in [e.identifier for e in bpy.ops.object.mode_set.get_rna_type().properties['mode'].enum_items]
    bpy.ops.object.mode_set(mode=value)


def digest(value):
    return hashlib.sha256(json.dumps(value, separators=(',', ':')).encode()).hexdigest()


def fingerprint():
    result = {}
    for name in PARTS:
        mesh = bpy.data.objects[name].data
        result[name] = {
            'vertices': digest([list(v.co) for v in mesh.vertices]),
            'polygons': digest([list(p.vertices) for p in mesh.polygons]),
            'uv0': digest([list(l.uv) for l in mesh.uv_layers[0].data]),
            'normals': digest([list(n.vector) for n in mesh.corner_normals]),
            'shape_keys': {k.name: digest([list(v.co) for v in k.data])
                           for k in mesh.shape_keys.key_blocks} if mesh.shape_keys else {},
        }
    result['images'] = {i.name: hashlib.sha256(i.packed_file.data).hexdigest()
                        for i in bpy.data.images if i.packed_file}
    return result


def build():
    assert RIG not in bpy.data.objects, 'Rig exists; do not overwrite edited poses/weights.'
    assert bpy.context.scene.name == 'Adventure_Modular'
    ART.mkdir(parents=True, exist_ok=True)
    (ART / 'before.json').write_text(json.dumps(fingerprint(), indent=2), encoding='utf-8')
    arm = bpy.data.armatures.new('Adventurer_Skeleton')
    rig = bpy.data.objects.new(RIG, arm)
    bpy.context.scene.collection.objects.link(rig)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    mode('EDIT')

    def bone(name, head, tail, parent=None):
        b = arm.edit_bones.new(name)
        b.head, b.tail = head, tail
        b.use_deform = name != 'root'
        if parent:
            b.parent = arm.edit_bones[parent]

    bone('root', (0, 0, 0), (0, 0, .16))
    bone('pelvis', (0, 0, .69), (0, 0, .82), 'root')
    bone('spine', (0, 0, .82), (0, 0, .96), 'pelvis')
    bone('chest', (0, 0, .96), (0, 0, 1.14), 'spine')
    bone('neck', (0, 0, 1.14), (0, 0, 1.26), 'chest')
    bone('head', (0, 0, 1.26), (0, 0, 1.90), 'neck')
    for side, sign in [('L', 1), ('R', -1)]:
        bone('clavicle.' + side, (sign * .07, 0, 1.12), (sign * .389, 0, 1.117), 'chest')
        bone('upper_arm.' + side, (sign * .389, 0, 1.117), (sign * .50, -.012, .95), 'clavicle.' + side)
        bone('forearm.' + side, (sign * .50, -.012, .95), (sign * .584, -.025, .825), 'upper_arm.' + side)
        bone('hand.' + side, (sign * .584, -.025, .825), (sign * .638, -.04, .735), 'forearm.' + side)
        bone('thigh.' + side, (sign * .185, 0, .69), (sign * .195, -.025, .36), 'pelvis')
        bone('shin.' + side, (sign * .195, -.025, .36), (sign * .205, 0, .145), 'thigh.' + side)
        bone('foot.' + side, (sign * .205, 0, .145), (sign * .205, -.17, .08), 'shin.' + side)
        bone('toe.' + side, (sign * .205, -.17, .08), (sign * .205, -.27, .065), 'foot.' + side)
        bone('cape.' + side, (sign * .13, .22, 1.16), (sign * .26, .28, .75), 'chest')
        bone('cape_tip.' + side, (sign * .26, .28, .75), (sign * .32, .34, .35), 'cape.' + side)
        bone('coat_front.' + side, (sign * .15, -.12, .80), (sign * .22, -.17, .49), 'pelvis')
        bone('coat_back.' + side, (sign * .15, .14, .80), (sign * .22, .20, .49), 'pelvis')
    mode('OBJECT')
    enum(arm, 'display_type', 'OCTAHEDRAL')
    rig.show_in_front = True
    for pb in rig.pose.bones:
        enum(pb, 'rotation_mode', 'QUATERNION')
    rig['rig_version'] = 1
    rig['controls'] = 'FK: root, pelvis/spine/chest/neck/head, L/R limbs, cape and coat. Pose Mode: R to rotate, Alt-R/Alt-G to reset.'
    rig['part_contract'] = 'adventurer_v1_feet_origin_y_up_2.2m_gltf'
    for name in PARTS:
        obj = bpy.data.objects[name]
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        assert 'ARMATURE' in [e.identifier for e in bpy.types.Modifier.bl_rna.properties['type'].enum_items]
        mod = obj.modifiers.new('Adventurer Skin', 'ARMATURE')
        mod.object = rig
        mod.use_deform_preserve_volume = False
    print('Created fitted FK rig:', len(arm.bones), 'bones')


def smooth(a, b, value):
    t = min(1, max(0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    result = {k: v * (1 - t) for k, v in a.items()}
    for k, v in b.items():
        result[k] = result.get(k, 0) + v * t
    return result


def texture_colors(obj):
    mat = obj.data.materials[0]
    image = next(n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE')
    pixels = np.empty(len(image.pixels), dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((image.size[1], image.size[0], 4))
    colors = np.zeros((len(obj.data.vertices), 3))
    counts = np.zeros(len(obj.data.vertices))
    for loop in obj.data.loops:
        u, v = obj.data.uv_layers[0].data[loop.index].uv
        colors[loop.vertex_index] += pixels[round(v * (image.size[1] - 1)), round(u * (image.size[0] - 1)), :3]
        counts[loop.vertex_index] += 1
    return colors / np.maximum(counts, 1)[:, None]


def vertex_weights(co, color):
    x, y, z = co
    ax, side = abs(x), 'L' if x >= 0 else 'R'
    torso = mix({'pelvis': 1}, {'spine': 1}, smooth(.76, .89, z))
    torso = mix(torso, {'chest': 1}, smooth(.92, 1.04, z))
    torso = mix(torso, {'neck': 1}, smooth(1.10, 1.19, z))
    torso = mix(torso, {'head': 1}, smooth(1.17, 1.25, z))
    # All head seams evaluate the same spatial function across separate parts.
    if z >= 1.19:
        return torso
    leg = mix({'thigh.' + side: 1}, {'shin.' + side: 1}, 1 - smooth(.31, .41, z))
    leg = mix(leg, {'foot.' + side: 1}, 1 - smooth(.12, .20, z))
    toe = (1 - smooth(-.21, -.14, y)) * (1 - smooth(.09, .14, z))
    leg = mix(leg, {'toe.' + side: 1}, toe)
    result = mix(leg, torso, smooth(.56, .73, z))
    # Leather coat panels sit in front of / behind the short legs.
    coat = (1 - smooth(.76, .86, z)) * smooth(.38, .51, z)
    coat *= smooth(.09, .18, abs(y)) * (1 - smooth(.34, .44, ax))
    coat_name = ('coat_front.' if y < 0 else 'coat_back.') + side
    result = mix(result, {coat_name: 1}, coat)
    r, g, b = color
    red = r > 1.6 * g and b > 1.02 * g
    cape_amount = smooth(.035, .12, y) * (1 - smooth(1.05, 1.17, z)) if red else 0
    cape = mix({'cape.' + side: 1}, {'cape_tip.' + side: 1}, 1 - smooth(.63, .82, z))
    if ax < .09:
        opposite = {k.replace('.' + side, '.R' if side == 'L' else '.L'): v for k, v in cape.items()}
        cape = mix(opposite, cape, .5 + .5 * smooth(0, .09, ax))
    result = mix(result, cape, cape_amount)
    arm = mix({'upper_arm.' + side: 1}, {'forearm.' + side: 1}, 1 - smooth(.91, .99, z))
    arm = mix(arm, {'hand.' + side: 1}, 1 - smooth(.79, .85, z))
    arm = mix(arm, {'clavicle.' + side: 1}, smooth(1.065, 1.135, z))
    boundary = .32 + .30 * max(0, 1.05 - z)
    arm_amount = smooth(boundary, boundary + .10, ax) * smooth(.57, .68, z) * (1 - smooth(1.14, 1.22, z))
    return mix(result, arm, arm_amount)


def bind():
    rig = bpy.data.objects[RIG]
    assert 'REPLACE' in [e.identifier for e in bpy.types.VertexGroup.bl_rna.functions['add'].parameters['type'].enum_items]
    for name in PARTS:
        obj = bpy.data.objects[name]
        obj.vertex_groups.clear()
        for bone in rig.data.bones:
            if bone.use_deform:
                obj.vertex_groups.new(name=bone.name)
        colors = texture_colors(obj)
        for v in obj.data.vertices:
            weights = vertex_weights(v.co, colors[v.index])
            weights = sorted(((k, w) for k, w in weights.items() if w > .00001), key=lambda p: -p[1])[:4]
            total = sum(w for _, w in weights)
            for bone, value in weights:
                obj.vertex_groups[bone].add([v.index], value / total, 'REPLACE')
        print('Skinned', name, len(obj.data.vertices), 'vertices')
    # Stable rest-space mouth coordinates: GLES3 feeds pre-skinned vertices to
    # user shaders. UV2 keeps the cel mouth attached to the face when head turns.
    face = bpy.data.objects['Face']
    layer = face.data.uv_layers.get('ExpressionRest') or face.data.uv_layers.new(name='ExpressionRest')
    for loop in face.data.loops:
        x, y, z = face.data.vertices[loop.vertex_index].co
        layer.data[loop.index].uv = (x + .5 if y < -.23 else 10 + x, 1 - z)
    face['adventure_expression_uv'] = True


def curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                yield from bag.fcurves


def rotate(pb, axis, angle):
    local_axis = pb.bone.matrix_local.to_3x3().inverted() @ Vector(axis)
    pb.rotation_quaternion = Quaternion(local_axis, math.radians(angle))


def animate():
    rig = bpy.data.objects[RIG]
    rig.animation_data_create()
    assert not any(name in bpy.data.actions for name in CLIPS), 'Do not overwrite existing actions.'
    for clip, period in CLIPS.items():
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        action['loop'] = True
        rig.animation_data.action = action
        for frame in range(1, period + 2):
            t = (frame - 1) / period
            for pb in rig.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.scale = (1, 1, 1)
            if clip == 'idle':
                phase = math.tau * t
                rotate(rig.pose.bones['chest'], (1, 0, 0), .6 * math.sin(phase))
                rotate(rig.pose.bones['head'], (0, 0, 1), 1.6 * math.sin(phase))
                for side, sign in [('L', 1), ('R', -1)]:
                    rotate(rig.pose.bones['upper_arm.' + side], (0, 1, 0), sign * .6 * math.sin(phase))
                    rotate(rig.pose.bones['cape.' + side], (1, 0, 0), .7 * math.sin(phase))
                    rotate(rig.pose.bones['cape_tip.' + side], (1, 0, 0), 1.0 * math.sin(phase))
            else:
                # One foot stays planted while the other lifts; no root motion.
                side, sign = ('L', 1) if t < .5 else ('R', -1)
                amount = math.sin(math.tau * (t if t < .5 else t - .5)) ** 2
                rotate(rig.pose.bones['head'], (0, 0, 1), sign * 18 * amount)
                rotate(rig.pose.bones['chest'], (0, 0, 1), sign * 3 * amount)
                rotate(rig.pose.bones['upper_arm.' + side], (0, 1, 0), -sign * 42 * amount)
                rotate(rig.pose.bones['forearm.' + side], (0, 1, 0), -sign * 36 * amount)
                rotate(rig.pose.bones['hand.' + side], (1, 0, 0), 12 * amount)
                rotate(rig.pose.bones['thigh.' + side], (1, 0, 0), -22 * amount)
                rotate(rig.pose.bones['shin.' + side], (1, 0, 0), 35 * amount)
                rotate(rig.pose.bones['foot.' + side], (1, 0, 0), -8 * amount)
                rotate(rig.pose.bones['coat_front.' + side], (1, 0, 0), -12 * amount)
                rotate(rig.pose.bones['coat_back.' + side], (1, 0, 0), 6 * amount)
                rotate(rig.pose.bones['cape.' + side], (1, 0, 0), 7 * amount)
                rotate(rig.pose.bones['cape_tip.' + side], (1, 0, 0), 9 * amount)
            for pb in rig.pose.bones:
                pb.keyframe_insert(data_path='location', frame=frame, group=pb.name)
                pb.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=pb.name)
        for curve in curves(action):
            for key in curve.keyframe_points:
                enum(key, 'interpolation', 'LINEAR')
    bpy.context.scene.render.fps = 30
    show('idle', 1)


def show(clip='idle', frame=1, bones=False):
    rig = bpy.data.objects[RIG]
    rig.animation_data.action = bpy.data.actions[clip]
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, CLIPS[clip]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            enum(area.spaces.active.shading, 'type', 'MATERIAL')
            enum(area.spaces.active.region_3d, 'view_perspective', 'ORTHO')
            area.spaces.active.region_3d.view_location = (0, 0, 1.10)
            area.spaces.active.region_3d.view_distance = 3.8
            area.spaces.active.region_3d.view_rotation = Quaternion((0, 0, 1), .12) @ Quaternion((1, 0, 0), math.pi / 2)
            area.spaces.active.overlay.show_overlays = bones


def validate():
    rig = bpy.data.objects[RIG]
    before = json.loads((ART / 'before.json').read_text(encoding='utf-8'))
    assert before == fingerprint(), 'Rest mesh, UV0, normals, expression targets and packed images must be preserved.'
    report = {'bones': len(rig.data.bones), 'parts': {}, 'clips': {}, 'source_preserved': True}
    assert report['bones'] == 30
    shared = {}
    for name in PARTS:
        obj = bpy.data.objects[name]
        sums = [sum(g.weight for g in v.groups) for v in obj.data.vertices]
        assert all(abs(s - 1) < .00001 for s in sums)
        assert max(len(v.groups) for v in obj.data.vertices) <= 4
        assert obj.modifiers[0].object == rig
        report['parts'][name] = {'vertices': len(sums), 'unweighted': sum(s == 0 for s in sums), 'max_influences': max(len(v.groups) for v in obj.data.vertices)}
        for v in obj.data.vertices:
            if v.co.z < 1.19:
                continue
            co = tuple(round(c, 5) for c in v.co)
            weights = {obj.vertex_groups[g.group].name: g.weight for g in v.groups}
            if co in shared:
                assert shared[co] == weights, (name, 'part seam weights differ', co)
            shared[co] = weights
    body = bpy.data.objects['AdventurerBody']
    for clip, period in CLIPS.items():
        rig.animation_data.action = bpy.data.actions[clip]
        floors, endpoints = [], []
        for frame in range(1, period + 2):
            bpy.context.scene.frame_set(frame)
            evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            points = [v.co.copy() for v in mesh.vertices]
            assert all(math.isfinite(c) for co in points for c in co)
            floors.append(min(co.z for co in points))
            if frame in (1, period + 1):
                endpoints.append(points)
            evaluated.to_mesh_clear()
        seam = max((a - b).length for a, b in zip(*endpoints))
        assert seam < 1e-5, (clip, seam)
        assert min(floors) > -.012, (clip, 'ground penetration', min(floors))
        report['clips'][clip] = {'duration': period / 30, 'loop_seam': seam, 'floor_range': [min(floors), max(floors)]}
    show('idle', 1)
    (ART / 'validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


def export():
    import io_scene_gltf2
    assert 'GLB' in [x[0] for x in io_scene_gltf2.get_format_items(None, bpy.context)]
    assert 'ACTIONS' in [x.identifier for x in bpy.ops.export_scene.gltf.get_rna_type().properties['export_animation_mode'].enum_items]
    rig = bpy.data.objects[RIG]
    show('idle', 1)
    source_mat = bpy.data.objects['Mesh_0'].data.materials[0]
    portable = source_mat.copy()
    portable.name = 'Adventure_Export_Matte'
    bsdf = next(n for n in portable.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    for socket in ['Metallic', 'Roughness', 'Normal', 'Specular IOR Level']:
        for link in list(bsdf.inputs[socket].links):
            portable.node_tree.links.remove(link)
    bsdf.inputs['Metallic'].default_value = 0
    bsdf.inputs['Roughness'].default_value = 1
    bsdf.inputs['Specular IOR Level'].default_value = 0
    report = {}
    try:
        for name, filename in PARTS.items():
            obj = bpy.data.objects[name]
            for other in bpy.context.selected_objects:
                other.select_set(False)
            hidden = obj.hide_get()
            obj.hide_set(False)
            previous = obj.data.materials[0]
            obj.data.materials[0] = portable
            obj.select_set(True)
            rig.select_set(True)
            bpy.context.view_layer.objects.active = rig
            try:
                bpy.ops.export_scene.gltf(filepath=str(OUT / filename), export_format='GLB',
                    use_selection=True, use_active_scene=True, export_yup=True, export_extras=True,
                    export_animations=name == 'AdventurerBody', export_animation_mode='ACTIONS',
                    export_frame_range=False, export_force_sampling=True, export_frame_step=1,
                    export_anim_slide_to_zero=True, export_skins=True, export_all_influences=False,
                    export_apply=False, export_morph=True, export_rest_position_armature=True,
                    export_optimize_animation_size=False, export_cameras=False, export_lights=False)
            finally:
                obj.data.materials[0] = previous
                obj.select_set(False)
                obj.hide_set(hidden)
            data = (OUT / filename).read_bytes()
            length = struct.unpack_from('<I', data, 12)[0]
            gltf = json.loads(data[20:20 + length])
            assert len(gltf['meshes']) == 1 and len(gltf['skins']) == 1
            assert len(gltf['skins'][0]['joints']) == 30
            assert len(gltf['images']) == 1
            view = gltf['bufferViews'][gltf['images'][0]['bufferView']]
            blob = data[28 + length:]
            image = blob[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]
            base = next(n.image for n in source_mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image.name == 'Image_0')
            assert hashlib.sha256(image).digest() == hashlib.sha256(base.packed_file.data).digest()
            report[filename] = {'bones': 30, 'meshes': 1, 'texture_unchanged': True,
                                'clips': [a['name'] for a in gltf.get('animations', [])]}
    finally:
        bpy.data.materials.remove(portable)
    show('idle', 1, bones=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'Adventure_modular.blend'))
    (ART / 'export.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
