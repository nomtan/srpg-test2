"""Preserve the Tripo source; build an Eevee toon rig and a matching game GLB.

blender --background --factory-startup --python tools/prepare_tripo_knight.py
Append -- --render to render Original/Toon, Standard/AgX, and motion previews.
"""
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/tripo_knight'
ART = ROOT / 'artifacts/tripo_knight/toon'
SOURCE = OUT / 'knight+3d+model.glb'
BANDS = (.68, .84, 1.0)
THRESHOLDS = (0, .28, .60)
PERIODS = {'idle': 60, 'walk': 30, 'run': 20}
OUTLINE_WIDTH = .0018


def digest(value):
    return hashlib.sha256(json.dumps(value, separators=(',', ':')).encode()).hexdigest()


def fingerprint(mesh):
    return {
        'positions': digest([list(v.co) for v in mesh.vertices]),
        'topology': digest([list(p.vertices) for p in mesh.polygons]),
        'uv': digest([[list(v.uv) for v in uv.data] for uv in mesh.uv_layers]),
    }


def enum(owner, prop, value):
    values = [e.identifier for e in owner.bl_rna.properties[prop].enum_items]
    assert value in values, (prop, value, values)
    setattr(owner, prop, value)


def smooth(lo, hi, x):
    t = max(0, min(1, (x - lo) / (hi - lo)))
    return t * t * (3 - 2 * t)


def blend(a, b, t):
    result = {k: v * (1 - t) for k, v in a.items()}
    for k, v in b.items():
        result[k] = result.get(k, 0) + v * t
    return result


def material(name):
    m = bpy.data.materials.new(name)
    m.use_fake_user = True
    m.node_tree.nodes.clear()
    return m, m.node_tree.nodes, m.node_tree.links


def make_materials(base):
    toon, nodes, links = material('Toon')
    tex = nodes.new('ShaderNodeTexImage'); tex.image = base
    tex.label = 'Unchanged Tripo Base Color / sRGB'; tex.location = (-700, 220)
    diffuse = nodes.new('ShaderNodeBsdfDiffuse'); diffuse.location = (-700, -90)
    diffuse.inputs['Color'].default_value = (1, 1, 1, 1)
    rgb = nodes.new('ShaderNodeShaderToRGB'); rgb.location = (-480, -90)
    ramp = nodes.new('ShaderNodeValToRGB'); ramp.location = (-260, -90)
    ramp.label = 'CONSTANT: 68% / 84% / 100% neutral light'
    enum(ramp.color_ramp, 'interpolation', 'CONSTANT')
    ramp.color_ramp.elements.new(THRESHOLDS[1])
    for element, threshold, band in zip(ramp.color_ramp.elements, THRESHOLDS, BANDS):
        element.position = threshold; element.color = (band, band, band, 1)
    multiply = nodes.new('ShaderNodeMixRGB'); multiply.location = (70, 210)
    enum(multiply, 'blend_type', 'MULTIPLY'); multiply.inputs[0].default_value = 1
    emit = nodes.new('ShaderNodeEmission'); emit.location = (290, 210)
    emit.inputs['Strength'].default_value = 1
    output = nodes.new('ShaderNodeOutputMaterial'); output.location = (490, 210)
    for a, b in [(diffuse.outputs[0], rgb.inputs[0]), (rgb.outputs[0], ramp.inputs[0]),
                 (tex.outputs['Color'], multiply.inputs[1]), (ramp.outputs[0], multiply.inputs[2]),
                 (multiply.outputs[0], emit.inputs['Color']), (emit.outputs[0], output.inputs['Surface'])]:
        links.new(a, b)
    toon['normal_map_enabled'] = False
    toon['bands'] = BANDS
    toon['notes'] = 'No PBR, no color correction. Original texture multiplied by neutral stepped light.'
    matte, nodes, links = material('Toon_Export_Matte')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    for key, value in {'Metallic': 0, 'Roughness': 1, 'Specular IOR Level': 0,
                       'Coat Weight': 0, 'Sheen Weight': 0}.items():
        bsdf.inputs[key].default_value = value
    tex = nodes.new('ShaderNodeTexImage'); tex.image = base
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(bsdf.outputs[0], output.inputs['Surface'])
    ink, nodes, links = material('Toon_Outline_Ink')
    ink.use_backface_culling = True
    emit = nodes.new('ShaderNodeEmission'); emit.inputs['Color'].default_value = (.008, .011, .018, 1)
    emit.inputs['Strength'].default_value = 1
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(emit.outputs[0], output.inputs['Surface'])
    return toon, matte, ink


def angle_normals(mesh):
    # glTF splits vertices at UV seams. Average by position without welding,
    # changing topology, or removing any UV seam. Preserve corners over 32 degrees.
    groups = defaultdict(list)
    keys = [tuple(round(c, 6) for c in v.co) for v in mesh.vertices]
    for p in mesh.polygons:
        for vertex in p.vertices:
            groups[keys[vertex]].append((p.normal.copy(), p.area))
    normals = [None] * len(mesh.loops)
    limit = math.cos(math.radians(32))
    for p in mesh.polygons:
        p.use_smooth = True
        for loop in p.loop_indices:
            normal = Vector()
            for other, area in groups[keys[mesh.loops[loop].vertex_index]]:
                if p.normal.dot(other) >= limit:
                    normal += other * area
            normals[loop] = normal.normalized()
    mesh.normals_split_custom_set(normals)
    mesh.update()
    # Continuous extrusion across UV and hard-normal seams for the separate hull.
    return [sum((n * a for n, a in groups[key]), Vector()).normalized() for key in keys]


def make_rig(mesh):
    scene = bpy.context.scene
    arm = bpy.data.armatures.new('Knight_Skeleton')
    rig = bpy.data.objects.new('Knight_Rig', arm); scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True); bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name, head, tail, parent=None, deform=True):
        b = arm.edit_bones.new(name); b.head = head; b.tail = tail; b.use_deform = deform
        if parent: b.parent = arm.edit_bones[parent]
    bone('root', (0, 0, 0), (0, 0, .08), deform=False)
    bone('pelvis', (0, 0, .255), (0, 0, .35), 'root')
    bone('spine', (0, 0, .35), (0, 0, .42), 'pelvis')
    bone('chest', (0, 0, .42), (0, 0, .515), 'spine')
    bone('neck', (0, 0, .515), (0, 0, .605), 'chest')
    bone('head', (0, 0, .605), (0, 0, .90), 'neck')
    for side, sign in [('L', 1), ('R', -1)]:
        bone('clavicle.' + side, (sign * .08, 0, .49), (sign * .225, 0, .47), 'chest')
        bone('upper_arm.' + side, (sign * .225, 0, .47), (sign * .285, -.01, .405), 'clavicle.' + side)
        bone('forearm.' + side, (sign * .285, -.01, .405), (sign * .34, -.025, .365), 'upper_arm.' + side)
        bone('hand.' + side, (sign * .34, -.025, .365), (sign * .38, -.04, .34), 'forearm.' + side)
        bone('thigh.' + side, (sign * .115, 0, .245), (sign * .132, -.01, .128), 'pelvis')
        bone('shin.' + side, (sign * .132, -.01, .128), (sign * .14, .005, .052), 'thigh.' + side)
        bone('foot.' + side, (sign * .14, .005, .052), (sign * .14, -.10, .038), 'shin.' + side)
        bone('cape.' + side, (sign * .11, .095, .51), (sign * .15, .135, .30), 'chest')
        bone('cape_tip.' + side, (sign * .15, .135, .30), (sign * .20, .18, .115), 'cape.' + side)
    bone('tabard', (0, -.105, .33), (0, -.125, .205), 'pelvis')
    bone('tabard_tip', (0, -.125, .205), (0, -.13, .08), 'tabard')
    bpy.ops.object.mode_set(mode='OBJECT')
    enum(arm, 'display_type', 'STICK'); rig.show_in_front = True
    for pb in rig.pose.bones: enum(pb, 'rotation_mode', 'QUATERNION')
    mesh.parent = rig
    mod = mesh.modifiers.new('Knight Skin', 'ARMATURE'); mod.object = rig
    mod.use_deform_preserve_volume = False
    for b in arm.bones:
        if b.use_deform: mesh.vertex_groups.new(name=b.name)
    for vertex in mesh.data.vertices:
        x, y, z = vertex.co; ax = abs(x); side = 'L' if x >= 0 else 'R'
        torso = blend({'pelvis': 1}, {'chest': 1}, smooth(.35, .385, z))
        torso = blend(torso, {'neck': 1}, smooth(.52, .555, z))
        torso = blend(torso, {'head': 1}, smooth(.566, .595, z))
        arm_weights = blend({'upper_arm.' + side: 1}, {'forearm.' + side: 1}, smooth(.277, .294, ax))
        arm_weights = blend(arm_weights, {'hand.' + side: 1}, smooth(.336, .352, ax))
        arm_weights = blend(arm_weights, {'clavicle.' + side: 1}, smooth(.457, .486, z))
        arm_amount = smooth(.17 + max(0, .48 - z) * .7, .215 + max(0, .48 - z) * .7, ax)
        arm_amount *= smooth(.295, .32, z) * (1 - smooth(.535, .59, z))
        leg = blend({'thigh.' + side: 1}, {'shin.' + side: 1}, 1 - smooth(.112, .137, z))
        leg = blend(leg, {'foot.' + side: 1}, 1 - smooth(.066, .082, z))
        result = blend(torso, leg, 1 - smooth(.20, .28, z))
        # Front and side skirt plates follow the pelvis instead of bending like knees.
        skirt = (1 - smooth(.27, .33, z)) * smooth(.092, .13, z)
        front = 1 - smooth(-.075, -.035, y)
        if ax < .092:
            cloth = blend({'tabard': 1}, {'tabard_tip': 1}, 1 - smooth(.185, .23, z))
        else:
            cloth = blend({'pelvis': 1}, {'thigh.' + side: 1}, .18)
        result = blend(result, cloth, skirt * max(front, smooth(.17, .21, ax)))
        # The pointed front hem overlaps the boots in height. Keep its entire
        # connected painted panel on the cloth bones instead of pulling its tip
        # down with the legs when the knee bends.
        if ax < .105 and y < -.082 and .073 < z < .33:
            tabard = blend({'tabard': 1}, {'tabard_tip': 1}, 1 - smooth(.185, .23, z))
            result = blend(tabard, {'pelvis': 1}, smooth(.30, .33, z))
        result = blend(result, arm_weights, arm_amount)
        cape = blend({'cape.' + side: 1}, {'cape_tip.' + side: 1}, 1 - smooth(.27, .33, z))
        if ax < .035:
            other = 'R' if side == 'L' else 'L'
            cape = blend({k.replace('.' + side, '.' + other): v for k, v in cape.items()}, cape, .5 + .5 * smooth(0, .035, ax))
        cape_amount = smooth(.065 if z < .3 else .095, .10 if z < .3 else .13, y)
        cape_amount *= smooth(.075, .10, z) * (1 - smooth(.475, .52, z))
        result = blend(result, cape, cape_amount)
        if z >= .595: result = {'head': 1.0}  # Rigid visor, helmet, crest and ear plates.
        entries = sorted(((k, v) for k, v in result.items() if v > .0001), key=lambda kv: -kv[1])[:4]
        total = sum(v for k, v in entries)
        for name, weight in entries: mesh.vertex_groups[name].add([vertex.index], weight / total, 'REPLACE')
    rig['clips'] = 'idle: 1-61 (2s); walk: 1-31 (1s); run: 1-21 (2/3s). In place, 30fps.'
    rig['preservation'] = 'Rigid helmet. No subdivision, decimation, remesh, UV edit or texture repaint.'
    return rig


def action_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags: yield from bag.fcurves


def animate(rig, mesh):
    scene = bpy.context.scene
    scene.render.fps = 30
    rig.animation_data_create()
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    vectors = {b.name: b.tail_local - b.head_local for b in rig.data.bones}
    def inherited(pose, name):
        parent = rig.data.bones[name].parent.name
        return pose[parent] @ rest[parent].inverted() @ rest[name]
    def rotate(matrix, angle, axis):
        return Matrix.Translation(matrix.translation) @ Matrix.Rotation(angle, 4, axis) @ matrix.to_3x3().to_4x4()
    def aim(name, origin, direction):
        result = vectors[name].normalized().rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4() @ rest[name]
        result.translation = origin
        return result
    def apply_pose(pose):
        for pb in rig.pose.bones:
            basis = rest[pb.name].inverted() @ rest[pb.parent.name] @ pose[pb.parent.name].inverted() @ pose[pb.name] if pb.parent else rest[pb.name].inverted() @ pose[pb.name]
            pb.location, pb.rotation_quaternion, _ = basis.decompose()
            pb.scale = (1, 1, 1)
    for clip, period in PERIODS.items():
        action = bpy.data.actions.new(clip); action.use_fake_user = True
        action['loop'] = True; rig.animation_data.action = action
        moving, running = clip != 'idle', clip == 'run'
        for frame in range(1, period + 2):
            scene.frame_set(frame)
            t = math.tau * (frame - 1) / period
            pose = {'root': rest['root'].copy(), 'pelvis': rest['pelvis'].copy()}
            pose['pelvis'].translation += Vector((.002 * math.sin(t) if moving else 0, 0, -.026 if running else -.014 if moving else 0))
            pose['spine'] = rotate(inherited(pose, 'spine'), math.radians(7 if running else 2 if moving else .4 * math.sin(t)), 'X')
            pose['chest'] = rotate(inherited(pose, 'chest'), .02 * math.sin(t) if moving else 0, 'Z')
            pose['neck'] = inherited(pose, 'neck')
            pose['head'] = rest['head'].copy(); pose['head'].translation = inherited(pose, 'head').translation
            for side, sign, offset in [('L', 1, 0), ('R', -1, .5)]:
                u = ((frame - 1) / period + offset) % 1
                stance = .5 if running else .62
                stride = .07 if running else .045
                if not moving: fy, lift = .005, 0
                elif u < stance: fy, lift = .005 - stride + 2 * stride * u / stance, 0
                else:
                    v = (u - stance) / (1 - stance)
                    fy = .005 + stride - 2 * stride * smooth(0, 1, v)
                    lift = (.06 if running else .025) * math.sin(math.pi * v) ** 1.5
                thigh, shin, foot = ('thigh.' + side, 'shin.' + side, 'foot.' + side)
                hip = inherited(pose, thigh).translation
                ankle = Vector((sign * .14, fy, .052 + lift))
                la, lb = vectors[thigh].length, vectors[shin].length
                direction = (ankle - hip).normalized()
                distance = min((ankle - hip).length, la + lb - .00001)
                ankle = hip + direction * distance
                along = (la * la - lb * lb + distance * distance) / (2 * distance)
                bend = Vector((0, -1, 0)); bend = (bend - direction * bend.dot(direction)).normalized()
                knee = hip + direction * along + bend * math.sqrt(max(0, la * la - along * along))
                pose[thigh] = aim(thigh, hip, knee - hip); pose[shin] = aim(shin, knee, ankle - knee)
                pose[foot] = rest[foot].copy(); pose[foot].translation = ankle
                clav, upper, fore, hand = (prefix + side for prefix in ['clavicle.', 'upper_arm.', 'forearm.', 'hand.'])
                pose[clav] = inherited(pose, clav)
                shoulder = inherited(pose, upper).translation
                swing = (.40 if running else .22) * math.cos(t + offset * math.tau) if moving else .006 * math.sin(t)
                upper_dir = Vector((sign * .63, swing, -.78)).normalized()
                fore_dir = Vector((sign * .72, swing - (.3 if running else .04), -.68)).normalized()
                elbow = shoulder + upper_dir * vectors[upper].length
                wrist = elbow + fore_dir * vectors[fore].length
                pose[upper] = aim(upper, shoulder, upper_dir); pose[fore] = aim(fore, elbow, fore_dir)
                pose[hand] = aim(hand, wrist, fore_dir)
                for name, phase in [('cape.' + side, 0), ('cape_tip.' + side, -.7)]:
                    flutter = (1.8 if moving else .35) * math.sin(2 * t + phase)
                    pose[name] = rotate(inherited(pose, name), math.radians((6 if running else 2 if moving else 0) + flutter), 'X')
            pose['tabard'] = rotate(inherited(pose, 'tabard'), math.radians(-3 if running else -1 if moving else 0), 'X')
            pose['tabard_tip'] = rotate(inherited(pose, 'tabard_tip'), math.radians(1.2 * math.sin(2 * t)) if moving else 0, 'X')
            apply_pose(pose)
            # Correct only the rigid root translation. Do not stretch leg bones.
            bpy.context.view_layer.update()
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            data = evaluated.to_mesh(); floor = min(v.co.z for v in data.vertices); evaluated.to_mesh_clear()
            rig.pose.bones['root'].location += rest['root'].to_3x3().inverted() @ Vector((0, 0, -floor))
            for pb in rig.pose.bones:
                pb.keyframe_insert(data_path='location', frame=frame, group=pb.name)
                pb.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=pb.name)
        for curve in action_curves(action):
            for key in curve.keyframe_points: enum(key, 'interpolation', 'LINEAR')
        print('ANIMATION', clip, 'frames', period + 1, flush=True)
    rig.animation_data.action = bpy.data.actions['idle']; scene.frame_set(1)


def preview_scene(scene):
    assert scene.render.engine == 'BLENDER_EEVEE', scene.render.engine
    scene.view_settings.view_transform = 'Standard'; scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0; scene.view_settings.gamma = 1
    scene.view_settings.use_curve_mapping = False
    scene.render.resolution_x, scene.render.resolution_y = 800, 900
    scene.render.resolution_percentage = 100
    enum(scene.render.image_settings, 'file_format', 'PNG')
    scene.render.fps = 30; scene.frame_start = 1; scene.frame_end = 60
    world = bpy.data.worlds.new('Weak_Neutral_Environment')
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (.18, .18, .18, 1); bg.inputs['Strength'].default_value = .25
    scene.world = world
    light_data = bpy.data.lights.new('Key', 'SUN'); light_data.energy = 2.2; light_data.angle = math.radians(1)
    light = bpy.data.objects.new('Key', light_data); scene.collection.objects.link(light)
    light.rotation_euler = Vector((-.6, -.9, 1.3)).to_track_quat('Z', 'Y').to_euler()
    camera_data = bpy.data.cameras.new('Preview_Camera'); enum(camera_data, 'type', 'ORTHO'); camera_data.ortho_scale = 1.23
    camera = bpy.data.objects.new('Preview_Camera', camera_data); scene.collection.objects.link(camera)
    camera.location = (1.1, -2.7, 1.35)
    camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    return light, camera


def validate(mesh, rig, before, source_hash, base_hash):
    assert fingerprint(mesh.data) == before, 'Source positions/topology/UV changed'
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
    sums = [sum(g.weight for g in v.groups) for v in mesh.data.vertices]
    assert max(abs(w - 1) for w in sums) < 1e-6
    assert max(len(v.groups) for v in mesh.data.vertices) <= 4
    head_group = mesh.vertex_groups['head'].index
    helmet = [v for v in mesh.data.vertices if v.co.z >= .595]
    assert all(len(v.groups) == 1 and v.groups[0].group == head_group and v.groups[0].weight == 1 for v in helmet)
    result = {'source_sha256': source_hash, 'base_color_sha256': base_hash, 'geometry_before': before,
              'geometry_after': fingerprint(mesh.data), 'bones': len(rig.data.bones), 'vertices': len(mesh.data.vertices),
              'unweighted_vertices': sum(not v.groups for v in mesh.data.vertices), 'max_influences': max(len(v.groups) for v in mesh.data.vertices),
              'rigid_helmet_vertices': len(helmet), 'normal_angle_degrees': 32, 'normal_map': False, 'subdivision': False,
              'bands': BANDS, 'outline_width': OUTLINE_WIDTH, 'clips': {}}
    for clip, period in PERIODS.items():
        rig.animation_data.action = bpy.data.actions[clip]
        ends, floors = [], []
        for frame in range(1, period + 2):
            bpy.context.scene.frame_set(frame)
            ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); data = ev.to_mesh()
            points = [v.co.copy() for v in data.vertices]
            assert all(math.isfinite(c) for v in points for c in v)
            floors.append(min(v.z for v in points))
            if frame in (1, period + 1): ends.append(points)
            ev.to_mesh_clear()
        seam = max((a - b).length for a, b in zip(*ends))
        assert seam < 1e-5, (clip, seam)
        assert min(floors) > -1e-5 and max(floors) < 1e-5, (clip, min(floors), max(floors))
        result['clips'][clip] = {'seconds': period / 30, 'loop_seam': seam, 'floor_range': [min(floors), max(floors)]}
    rig.animation_data.action = bpy.data.actions['idle']; bpy.context.scene.frame_set(1)
    (ART / 'validation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('VALIDATION', json.dumps(result), flush=True)


def export_game(mesh, rig, outline, matte, base_hash):
    import io_scene_gltf2
    assert 'GLB' in [e[0] for e in io_scene_gltf2.get_format_items(None, bpy.context)]
    assert 'ACTIONS' in [e.identifier for e in bpy.ops.export_scene.gltf.get_rna_type().properties['export_animation_mode'].enum_items]
    previous = mesh.data.materials[0]; mesh.data.materials[0] = matte
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [mesh, rig, outline]: obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    try:
        bpy.ops.export_scene.gltf(filepath=str(OUT / 'knight_toon.glb'), export_format='GLB', use_selection=True, use_active_scene=True,
            export_yup=True, export_animations=True, export_animation_mode='ACTIONS', export_frame_range=False,
            export_force_sampling=True, export_frame_step=1, export_anim_slide_to_zero=True, export_skins=True,
            export_all_influences=False, export_apply=False, export_morph=False, export_rest_position_armature=True,
            export_optimize_animation_size=False, export_cameras=False, export_lights=False, export_image_format='AUTO')
    finally: mesh.data.materials[0] = previous
    blob = (OUT / 'knight_toon.glb').read_bytes(); size = struct.unpack_from('<I', blob, 12)[0]
    doc = json.loads(blob[20:20 + size])
    assert len(doc['skins']) == 1 and len(doc['skins'][0]['joints']) == 26
    assert len(doc['animations']) == 3 and {a['name'] for a in doc['animations']} == set(PERIODS)
    assert not any(n.get('name') == 'Original_Rig' for n in doc['nodes'])
    assert len(doc['images']) == 1
    view = doc['bufferViews'][doc['images'][0]['bufferView']]; start = 28 + size + view.get('byteOffset', 0)
    assert hashlib.sha256(blob[start:start + view['byteLength']]).hexdigest() == base_hash, 'Export changed Base Color bytes'
    mat = next(m for m in doc['materials'] if m['name'] == 'Toon_Export_Matte')
    assert mat['pbrMetallicRoughness']['metallicFactor'] == 0 and 'normalTexture' not in mat
    print('EXPORT: exact original Base Color bytes, 26 bones, idle/walk/run, matte surface.', flush=True)


def render_previews():
    scene = bpy.data.scenes['Toon']; rig = bpy.data.objects['Knight_Rig']
    for name, view, clip, frame in [('Original', 'Standard', 'idle', 1), ('Toon', 'AgX', 'idle', 1),
                                   ('Toon', 'Standard', 'idle', 1), ('Toon', 'Standard', 'walk', 9),
                                   ('Toon', 'Standard', 'run', 6)]:
        target = bpy.data.scenes[name]; bpy.context.window.scene = target
        actor = bpy.data.objects['Original_Rig'] if name == 'Original' else rig
        actor.animation_data.action = bpy.data.actions[clip]
        target.view_settings.view_transform = view; target.view_settings.look = 'None'; target.frame_set(frame)
        target.render.filepath = str(ART / f'{name.lower()}_{view.lower()}_{clip}.png')
        bpy.ops.render.render(write_still=True, scene=target.name)
    bpy.context.window.scene = scene; scene.view_settings.view_transform = 'Standard'
    rig.animation_data.action = bpy.data.actions['idle']; scene.frame_set(1)


def main():
    sys.stdout.reconfigure(line_buffering=True)
    ART.mkdir(parents=True, exist_ok=True)
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    scene = bpy.context.scene; scene.name = 'Toon'
    mesh = next(o for o in scene.objects if o.type == 'MESH'); mesh.name = 'Knight_Body'
    original_data = mesh.data; original_data.name = 'Original_Mesh'; original_data.use_fake_user = True
    before = fingerprint(original_data)
    original_mat = original_data.materials[0]; original_mat.name = 'Original'; original_mat.use_fake_user = True
    principled = next(n for n in original_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    base = principled.inputs['Base Color'].links[0].from_node.image
    assert base.colorspace_settings.name == 'sRGB'
    base_hash = hashlib.sha256(base.packed_file.data).hexdigest()
    image_hashes = {i.name: hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.packed_file}
    toon, matte, ink = make_materials(base)
    mesh.data = original_data.copy(); mesh.data.name = 'Toon_Mesh'
    mesh.data.materials.clear(); mesh.data.materials.append(toon)
    extrusion_normals = angle_normals(mesh.data)
    rig = make_rig(mesh); animate(rig, mesh)
    outline = mesh.copy(); outline.data = mesh.data.copy(); outline.name = 'Toon_Outline'
    scene.collection.objects.link(outline)
    for v, normal in zip(outline.data.vertices, extrusion_normals): v.co += normal * OUTLINE_WIDTH
    outline.data.flip_normals(); outline.data.normals_split_custom_set([(0, 0, 0)] * len(outline.data.loops))
    outline.data.materials.clear(); outline.data.materials.append(ink)
    light, camera = preview_scene(scene)
    original = bpy.data.scenes.new('Original')
    original.render.engine = scene.render.engine
    original.world = scene.world; original.camera = camera
    original.collection.objects.link(camera); original.collection.objects.link(light)
    original.render.resolution_x = 800; original.render.resolution_y = 900; original.render.resolution_percentage = 100
    original.view_settings.view_transform = 'Standard'; original.view_settings.look = 'None'; original.render.fps = 30
    original.frame_start = 1; original.frame_end = 60
    original_rig = rig.copy(); original_rig.data = rig.data.copy(); original_rig.name = 'Original_Rig'
    original.collection.objects.link(original_rig)
    original_obj = mesh.copy(); original_obj.data = original_data; original_obj.name = 'Original_Body'
    original_obj.parent = original_rig
    next(m for m in original_obj.modifiers if m.type == 'ARMATURE').object = original_rig
    original.collection.objects.link(original_obj)
    for group in mesh.vertex_groups:
        original_obj.vertex_groups.new(name=group.name)
    for vertex in mesh.data.vertices:
        for group in vertex.groups:
            original_obj.vertex_groups[group.group].add([vertex.index], group.weight, 'REPLACE')
    scene['README'] = 'Toon: Eevee / Standard / 3 bands / one white Sun. Switch scene to Original for untouched materials and normals with the same animation.'
    scene['source'] = 'Tripo knight+3d+model.glb (the source was not made by Meshy). Original GLB is unchanged.'
    scene['normal_policy'] = '32 degree angle-limited normals; no normal/bump maps or subdivision. Rigid helmet weights.'
    validate(mesh, rig, before, source_hash, base_hash)
    assert image_hashes == {i.name: hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.packed_file}
    export_game(mesh, rig, outline, matte, base_hash)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active; enum(space.shading, 'type', 'RENDERED')
                space.shading.use_scene_world_render = True; space.shading.use_scene_lights_render = True
                enum(space.region_3d, 'view_perspective', 'CAMERA'); space.overlay.show_overlays = False
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'knight_toon.blend'))
    if '--render' in sys.argv: render_previews()
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
    print('DONE: source and all packed textures preserved; active saved scene is Toon / Standard.', flush=True)


if __name__ == '__main__': main()
