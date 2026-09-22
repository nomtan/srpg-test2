"""Run with Blender MCP after opening Adventure.blend (or its live backup).

Preserves the source in a separate scene; exports shared job body, face morphs,
and independently swappable hair. All parts share a feet-origin, 2.2 m contract.
"""
import hashlib
import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/meshy_adventure'
ART = ROOT / 'artifacts/meshy_adventure'
HEIGHT = 2.2
SOLE = -0.9497570991516113
SCALE = HEIGHT / (0.9494621157646179 - SOLE)


def enum(owner, prop, value):
    valid = [e.identifier for e in owner.bl_rna.properties[prop].enum_items]
    if value not in valid:
        # OCIO's dynamic enum is not exposed by RNA in Blender 5.1.
        try:
            setattr(owner, prop, '__QUERY_VALID_VALUES__')
        except TypeError as error:
            assert repr(value) in str(error), str(error)
    setattr(owner, prop, value)


def source_color():
    mat = bpy.data.objects['Mesh_0'].data.materials[0]
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    return bsdf.inputs['Base Color'].links[0].from_node.image


def classify(mesh):
    """Keep every source polygon exactly once. Use painted skin/scarf boundaries.

    Eyes are included geometrically so their dark paint is never mistaken for hair.
    The original welded Meshy mesh has no separate topology islands.
    """
    img = source_color()
    pixels = np.empty(len(img.pixels), dtype=np.float32)
    img.pixels.foreach_get(pixels)
    pixels = pixels.reshape((img.size[1], img.size[0], 4))
    uv = mesh.uv_layers.active.data
    parts = {'AdventurerBody': [], 'Face': [], 'Hair_Tousled': []}
    for p in mesh.polygons:
        x, y, z = p.center
        tex = sum((uv[i].uv for i in p.loop_indices), Vector((0, 0))) / len(p.loop_indices)
        r, g, b = pixels[round(tex.y * (img.size[1] - 1)), round(tex.x * (img.size[0] - 1)), :3]
        skin = r > .64 and g > .43 and b > .36 and g / max(r, .001) > .56
        scarf = r > g * 1.6 and b > g * 1.02 and z < .30
        eyes = abs(x) < .195 and y < -.17 and .235 < z < .395
        head_region = not (abs(x) > .30 and z < .20)
        if z > .10 and head_region and not scarf and (skin or eyes):
            part = 'Face'
        elif z > .20 and not scarf:
            part = 'Hair_Tousled'
        else:
            part = 'AdventurerBody'
        parts[part].append(p.index)
    return parts


def transform(co):
    return Vector((co.x * SCALE, co.y * SCALE, (co.z - SOLE) * SCALE))


def subset(source, indices, name, collection, material):
    mesh = source.data
    used = sorted({v for i in indices for v in mesh.polygons[i].vertices})
    remap = {v: i for i, v in enumerate(used)}
    data = bpy.data.meshes.new(name)
    data.from_pydata([transform(mesh.vertices[i].co) for i in used], [],
                     [[remap[v] for v in mesh.polygons[i].vertices] for i in indices])
    data.update()
    for layer in mesh.uv_layers:
        dst = data.uv_layers.new(name=layer.name)
        for p, original in zip(data.polygons, indices):
            for new_loop, old_loop in zip(p.loop_indices, mesh.polygons[original].loop_indices):
                dst.data[new_loop].uv = layer.data[old_loop].uv
    for p, original in zip(data.polygons, indices):
        p.use_smooth = mesh.polygons[original].use_smooth
    # Preserve normals across separated face/hair/scarf seams.
    data.normals_split_custom_set([mesh.corner_normals[j].vector
                                  for i in indices for j in mesh.polygons[i].loop_indices])
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    data.materials.append(material)
    obj['part_contract'] = 'adventurer_v1_feet_origin_y_up_2.2m_gltf'
    obj['source_polygon_count'] = len(indices)
    return obj, used


def make_material():
    # Neutral unlit material retains Meshy's painted cel shading in Blender/glTF.
    # Godot adds only restrained discrete neutral light bands, without PBR gloss.
    mat = bpy.data.materials.new('Adventure_Painted_Cel')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    image = nodes.new('ShaderNodeTexImage')
    image.image = source_color()
    emission = nodes.new('ShaderNodeEmission')
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(image.outputs['Color'], emission.inputs['Color'])
    links.new(emission.outputs[0], output.inputs['Surface'])
    return mat


def setup():
    assert 'Adventure_Modular' not in bpy.data.scenes, 'Already prepared.'
    original = bpy.context.scene
    original.name = 'Adventure_Original'
    original.use_fake_user = True
    source = bpy.data.objects['Mesh_0']
    parts = classify(source.data)
    scene = bpy.data.scenes.new('Adventure_Modular')
    bpy.context.window.scene = scene
    enum(scene.view_settings, 'view_transform', 'Standard')
    enum(scene.view_settings, 'look', 'None')
    material = make_material()
    objects = {}
    for name, ids in parts.items():
        obj, used = subset(source, ids, name, scene.collection, material)
        objects[name] = obj
        if name == 'AdventurerBody':
            obj['job_id'] = 'adventurer'
            obj['shared_across_characters'] = True
            angles = {}
            for v, old in zip(obj.data.vertices, used):
                co = source.data.vertices[old].co.copy()
                # Smooth shoulder transition into a relaxed standing pose.
                if abs(co.x) > .31 and -.18 < co.z < .16:
                    w = min(1, max(0, (abs(co.x) - .31) / .12))
                    w = w * w * (3 - 2 * w)
                    angle = -math.radians(57) * w
                    angles[old] = (angle, math.copysign(1, co.x))
                    dx, dz = abs(co.x) - .335, co.z - .015
                    co.x = math.copysign(.335 + dx * math.cos(angle) - dz * math.sin(angle), co.x)
                    co.z = .015 + dx * math.sin(angle) + dz * math.cos(angle)
                    v.co = transform(co)
            normals = []
            for i in ids:
                for loop in source.data.polygons[i].loop_indices:
                    normal = source.data.corner_normals[loop].vector.copy()
                    vertex = source.data.loops[loop].vertex_index
                    if vertex in angles:
                        angle, sign = angles[vertex]
                        nx, nz = normal.x * sign, normal.z
                        normal.x = sign * (nx * math.cos(angle) - nz * math.sin(angle))
                        normal.z = nx * math.sin(angle) + nz * math.cos(angle)
                    normals.append(normal)
            obj.data.normals_split_custom_set(normals)
        elif name == 'Face':
            obj.shape_key_add(name='Basis')
            keys = {k: obj.shape_key_add(name=k) for k in ['Smile', 'Blink', 'Angry']}
            # Fixed boundary vertices keep the jaw/hairline/socket sealed.
            edges = {}
            for p in obj.data.polygons:
                for edge in p.edge_keys:
                    edges[edge] = edges.get(edge, 0) + 1
            boundary = {v for e, n in edges.items() if n == 1 for v in e}
            for v, old in zip(obj.data.vertices, used):
                if v.index in boundary:
                    continue
                x, y, z = source.data.vertices[old].co
                front = max(0, min(1, (-y - .13) / .09))
                mouth = math.exp(-((x / .085) ** 4 + ((z - .172) / .043) ** 4)) * front
                keys['Smile'].data[v.index].co.z += SCALE * .027 * mouth * (abs(x) / .065 - .23)
                eye = math.exp(-(((abs(x) - .13) / .058) ** 4 + ((z - .312) / .068) ** 8)) * front
                keys['Blink'].data[v.index].co.z -= SCALE * (z - .332) * .93 * eye
                brow = math.exp(-(((abs(x) - .12) / .065) ** 4 + ((z - .37) / .032) ** 4)) * front
                keys['Angry'].data[v.index].co.z += SCALE * .035 * brow * ((abs(x) - .12) / .065)
    hair = objects['Hair_Tousled']
    swept = hair.copy()
    swept.data = hair.data.copy()
    swept.name = 'Hair_Swept'
    scene.collection.objects.link(swept)
    for v in swept.data.vertices:
        z = v.co.z / SCALE + SOLE
        w = max(0, min(1, (z - .48) / .47))
        v.co.x += .16 * SCALE * w * w
        v.co.z -= .09 * SCALE * w
    swept.hide_render = True
    swept.hide_set(True)
    for a in bpy.context.screen.areas:
        if a.type == 'VIEW_3D':
            a.spaces.active.shading.type = 'MATERIAL'
            a.spaces.active.region_3d.view_location = (0, 0, 1.1)
            a.spaces.active.region_3d.view_rotation = (math.sqrt(.5), math.sqrt(.5), 0, 0)
            a.spaces.active.region_3d.view_distance = 3.7
    report = {
        'source_vertices': len(source.data.vertices),
        'source_polygons': len(source.data.polygons),
        'parts': {k: len(v) for k, v in parts.items()},
        'base_color_sha256': hashlib.sha256(source_color().packed_file.data).hexdigest(),
        'height': HEIGHT,
        'contract': 'Blender +Z up/-Y front; glTF +Y up/+Z front, sole at origin',
        'source_preserved': 'Adventure_Original scene and artifacts/meshy_adventure backups',
    }
    assert sum(report['parts'].values()) == report['source_polygons']
    (ART / 'preparation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))


def export():
    # A rigged file must use the skin/animation-aware exporter.
    if 'Adventurer_Rig' in bpy.data.objects:
        rig_script = ROOT / 'tools/rig_meshy_adventure.py'
        namespace = {'__file__': str(rig_script), '__name__': 'adventure_rig'}
        exec(compile(rig_script.read_text(encoding='utf-8'), str(rig_script), 'exec'), namespace)
        return namespace['export']()
    import io_scene_gltf2
    assert 'GLB' in [e[0] for e in io_scene_gltf2.get_format_items(None, bpy.context)]
    scene = bpy.data.scenes['Adventure_Modular']
    bpy.context.window.scene = scene
    portable = bpy.data.objects['Mesh_0'].data.materials[0].copy()
    portable.name = 'Adventure_Export_Matte'
    bsdf = next(n for n in portable.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    for socket in ['Metallic', 'Roughness', 'Normal', 'Specular IOR Level']:
        for link in list(bsdf.inputs[socket].links):
            portable.node_tree.links.remove(link)
    bsdf.inputs['Metallic'].default_value = 0
    bsdf.inputs['Roughness'].default_value = 1
    bsdf.inputs['Specular IOR Level'].default_value = 0
    for name, filename in {'AdventurerBody': 'adventurer_body.glb', 'Face': 'face_default.glb',
                           'Hair_Tousled': 'hair_tousled.glb', 'Hair_Swept': 'hair_swept.glb'}.items():
        for o in bpy.context.selected_objects:
            o.select_set(False)
        obj = bpy.data.objects[name]
        hidden = obj.hide_get()
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        previous = obj.data.materials[0]
        obj.data.materials[0] = portable
        try:
            bpy.ops.export_scene.gltf(filepath=str(OUT / filename), export_format='GLB',
                                      use_selection=True, use_active_scene=True, export_yup=True, export_extras=True,
                                      export_animations=False, export_morph=True,
                                      export_cameras=False, export_lights=False)
        finally:
            obj.data.materials[0] = previous
            obj.select_set(False)
            obj.hide_set(hidden)
    bpy.data.materials.remove(portable)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'Adventure_modular.blend'))
    print('Exported all four modular assets and saved editable blend.')
