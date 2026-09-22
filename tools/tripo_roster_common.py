"""Shared non-destructive material and preview helpers for the Tripo roster.
Derived from the existing hero preparation pipeline; independent of its output paths.
"""
import hashlib
import json
import math
from collections import defaultdict
import bpy
from mathutils import Matrix, Vector
BANDS = (.68, .84, 1.0)
THRESHOLDS = (0, .28, .60)
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


def action_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags: yield from bag.fcurves


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
