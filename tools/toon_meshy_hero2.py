"""Non-destructive Eevee toon look for the existing Meshy Hero2 rig.

Execute setup(), render_preview(), validate(), export_game(), save() via Blender MCP.
Original geometry/materials live in the Original scene; Toon is the active scene.
The GLB uses a portable matte material. Godot's post-import shader supplies the
same three bands because Shader to RGB is an Eevee-only preview node.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/meshy_hero2'
ART = ROOT / 'artifacts/meshy_hero2/toon'
BANDS = (.68, .84, 1.0)
THRESHOLDS = (.0, .28, .60)
OUTLINE_WIDTH = .003


def enum(owner, prop, value):
    options = [e.identifier for e in owner.bl_rna.properties[prop].enum_items]
    assert value in options, (prop, value, options)
    setattr(owner, prop, value)


def digest(values):
    return hashlib.sha256(json.dumps(values, separators=(',', ':')).encode()).hexdigest()


def fingerprint(mesh):
    obj = bpy.data.objects['Mesh_0']
    return {
        'vertices': digest([list(v.co) for v in mesh.vertices]),
        'topology': digest([list(p.vertices) for p in mesh.polygons]),
        'uv': digest([[list(p.uv) for p in layer.data] for layer in mesh.uv_layers]),
        'weights': digest([[(g.group, g.weight) for g in v.groups] for v in mesh.vertices]),
        'groups': digest([g.name for g in obj.vertex_groups]),
        'images': {i.name: hashlib.sha256(i.packed_file.data).hexdigest()
                   for i in bpy.data.images if i.packed_file},
        'actions': {a.name: digest([(f.data_path, f.array_index,
                                    [list(k.co) for k in f.keyframe_points])
                                   for layer in a.layers for strip in layer.strips
                                   for bag in strip.channelbags for f in bag.fcurves])
                    for a in bpy.data.actions if a.name in ('idle', 'walk', 'run')},
    }


def material_nodes(name):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_fake_user = True
    material.node_tree.nodes.clear()
    return material, material.node_tree.nodes, material.node_tree.links


def setup():
    assert 'Toon' not in bpy.data.scenes, 'Toon setup already exists.'
    mesh = bpy.data.objects['Mesh_0']
    rig = bpy.data.objects['Hero2_Rig']
    scene = bpy.context.scene
    assert len(rig.data.bones) == 26 and mesh.modifiers[0].object == rig
    ART.mkdir(parents=True, exist_ok=True)
    baseline = fingerprint(mesh.data)
    (ART / 'preservation_before.json').write_text(json.dumps(baseline, indent=2))
    original_mesh = mesh.data
    original_mesh.name = 'Hero2_OriginalMesh'
    original_mesh.use_fake_user = True
    original_material = mesh.data.materials[0]
    original_material.name = 'Original'
    original_material.use_fake_user = True
    principled = next(n for n in original_material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    color_node = principled.inputs['Base Color'].links[0].from_node
    base_color = color_node.image
    assert base_color and base_color.colorspace_settings.name == 'sRGB'

    toon, nodes, links = material_nodes('Toon')
    image = nodes.new('ShaderNodeTexImage')
    image.image = base_color
    image.label = 'Original Meshy Base Color — unchanged'
    image.location = (-650, 200)
    diffuse = nodes.new('ShaderNodeBsdfDiffuse')
    diffuse.inputs['Color'].default_value = (1, 1, 1, 1)
    diffuse.inputs['Roughness'].default_value = 0
    diffuse.location = (-650, -80)
    rgb = nodes.new('ShaderNodeShaderToRGB')
    rgb.location = (-440, -80)
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.label = '3 neutral bands: 68% / 84% / 100%'
    ramp.location = (-230, -80)
    enum(ramp.color_ramp, 'interpolation', 'CONSTANT')
    ramp.color_ramp.elements.new(THRESHOLDS[1])
    for element, threshold, value in zip(ramp.color_ramp.elements, THRESHOLDS, BANDS):
        element.position = threshold
        element.color = (value, value, value, 1)
    multiply = nodes.new('ShaderNodeMixRGB')
    enum(multiply, 'blend_type', 'MULTIPLY')
    multiply.inputs[0].default_value = 1
    multiply.location = (70, 180)
    emission = nodes.new('ShaderNodeEmission')
    emission.inputs['Strength'].default_value = 1
    emission.location = (280, 180)
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (480, 180)
    links.new(diffuse.outputs['BSDF'], rgb.inputs['Shader'])
    links.new(rgb.outputs['Color'], ramp.inputs[0])
    links.new(image.outputs['Color'], multiply.inputs[1])
    links.new(ramp.outputs['Color'], multiply.inputs[2])
    links.new(multiply.outputs[0], emission.inputs['Color'])
    links.new(emission.outputs[0], output.inputs['Surface'])
    toon['bands'] = list(BANDS)
    toon['normal_map_enabled'] = False
    toon['base_color_sha256'] = baseline['images'][base_color.name]

    matte, nodes, links = material_nodes('Toon_Export_Matte')
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Metallic'].default_value = 0
    bsdf.inputs['Roughness'].default_value = 1
    bsdf.inputs['Specular IOR Level'].default_value = 0
    bsdf.inputs['Coat Weight'].default_value = 0
    bsdf.inputs['Sheen Weight'].default_value = 0
    image = nodes.new('ShaderNodeTexImage')
    image.image = base_color
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(image.outputs['Color'], bsdf.inputs['Base Color'])
    links.new(bsdf.outputs[0], output.inputs['Surface'])
    matte['note'] = 'Portable matte fallback; Godot post-import restores the stepped shader.'

    mesh.data = original_mesh.copy()
    mesh.data.name = 'Hero2_ToonMesh'
    mesh.data.materials.clear()
    mesh.data.materials.append(toon)
    for polygon in mesh.data.polygons:
        center = polygon.center
        # Face and ears only; hair, armor, clothing and cape keep planar facets.
        polygon.use_smooth = .07 < center.z < .40 and center.y < -.12 and abs(center.x) < .30
    mesh.data.normals_split_custom_set([(0, 0, 0)] * len(mesh.data.loops))
    mesh.data.update()

    # Separate skinned inverted hull: no changes to the original surface or UVs.
    outline = mesh.copy()
    outline.data = original_mesh.copy()
    outline.name = 'Toon_Outline'
    scene.collection.objects.link(outline)
    for v, source in zip(outline.data.vertices, original_mesh.vertices):
        v.co += source.normal * OUTLINE_WIDTH
    outline.data.flip_normals()
    outline.data.normals_split_custom_set([(0, 0, 0)] * len(outline.data.loops))
    ink, nodes, links = material_nodes('Toon_Outline_Ink')
    ink.use_backface_culling = True
    emission = nodes.new('ShaderNodeEmission')
    emission.inputs['Color'].default_value = (.008, .011, .018, 1)
    emission.inputs['Strength'].default_value = 1
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(emission.outputs[0], output.inputs['Surface'])
    outline.data.materials.clear()
    outline.data.materials.append(ink)
    outline.hide_select = True

    scene.name = 'Toon'
    scene['look_notes'] = 'Eevee / Standard / one white sun / weak neutral world / three CONSTANT bands. Compare scene Original.'
    scene['outline_width'] = OUTLINE_WIDTH
    # This connected Blender already reports BLENDER_EEVEE as its current engine.
    assert scene.render.engine == 'BLENDER_EEVEE'
    # Dynamic OCIO enums are confirmed in the installed config.ocio (RNA lists NONE).
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.view_settings.use_curve_mapping = False
    world = bpy.data.worlds.new('Toon_Weak_Neutral_Environment')
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    background.inputs['Color'].default_value = (.18, .18, .18, 1)
    background.inputs['Strength'].default_value = .25
    scene.world = world
    light_data = bpy.data.lights.new('Toon_Key', 'SUN')
    light_data.energy = 2.2
    light_data.angle = math.radians(1)
    light_data.color = (1, 1, 1)
    light = bpy.data.objects.new('Toon_Key', light_data)
    scene.collection.objects.link(light)
    light.rotation_euler = Vector((-.6, -.9, 1.3)).to_track_quat('Z', 'Y').to_euler()
    camera_data = bpy.data.cameras.new('Toon_Preview_Camera')
    enum(camera_data, 'type', 'ORTHO')
    camera_data.ortho_scale = 2.5
    camera = bpy.data.objects.new('Toon_Preview_Camera', camera_data)
    scene.collection.objects.link(camera)
    camera.location = (2.3, -5.5, 1.5)
    camera.rotation_euler = (Vector((0, 0, -.03)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    scene.render.resolution_x, scene.render.resolution_y = 800, 900
    scene.render.resolution_percentage = 100
    enum(scene.render.image_settings, 'file_format', 'PNG')
    scene.render.film_transparent = False

    original_scene = bpy.data.scenes.new('Original')
    original_scene.world = world
    original_scene.camera = camera
    original_scene.collection.objects.link(camera)
    original_scene.collection.objects.link(light)
    original_scene.render.engine = scene.render.engine
    original_scene.render.resolution_x, original_scene.render.resolution_y = 800, 900
    original_scene.render.resolution_percentage = 100
    original_scene.render.fps = 30
    original_scene.frame_start, original_scene.frame_end = 1, 30
    original_rig = rig.copy()
    original_rig.data = rig.data.copy()
    original_rig.name = 'Original_Rig'
    original_scene.collection.objects.link(original_rig)
    original_obj = mesh.copy()
    original_obj.data = original_mesh
    original_obj.name = 'Original_Mesh'
    original_obj.parent = original_rig
    for modifier in original_obj.modifiers:
        if modifier.type == 'ARMATURE':
            modifier.object = original_rig
    original_scene.collection.objects.link(original_obj)
    original_scene['look_notes'] = 'Unmodified source mesh, normals, material and packed textures; same rig and preview light as Toon.'
    original_scene.view_settings.view_transform = 'AgX'
    for s in (scene, original_scene):
        s.frame_set(1)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                enum(space.shading, 'type', 'RENDERED')
                space.shading.use_scene_world_render = True
                space.shading.use_scene_lights_render = True
                enum(space.region_3d, 'view_perspective', 'CAMERA')
                space.overlay.show_overlays = False
    print(json.dumps({'scene': scene.name, 'smooth_faces': sum(p.use_smooth for p in mesh.data.polygons),
                      'flat_faces': sum(not p.use_smooth for p in mesh.data.polygons), 'bands': BANDS,
                      'base_color_sha256': baseline['images'][base_color.name]}, indent=2))


def render_preview(look='Toon', transform='Standard', clip='idle', frame=1):
    scene = bpy.data.scenes[look]
    rig = bpy.data.objects['Hero2_Rig' if look == 'Toon' else 'Original_Rig']
    rig.animation_data.action = bpy.data.actions[clip]
    scene.view_settings.view_transform = transform
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.frame_set(frame)
    scene.render.filepath = str(ART / f'{look.lower()}_{transform.lower()}_{clip}.png')
    bpy.ops.render.render(write_still=True, scene=scene.name)
    print(scene.render.filepath)


def validate():
    mesh = bpy.data.objects['Mesh_0']
    before = json.loads((ART / 'preservation_before.json').read_text())
    after = fingerprint(mesh.data)
    assert before == after, [(k, before[k], after[k]) for k in before if before[k] != after[k]]
    assert len(bpy.data.objects['Hero2_Rig'].data.bones) == 26
    assert all(m.type != 'SUBSURF' for m in mesh.modifiers)
    toon = bpy.data.materials['Toon']
    ramp = next(n for n in toon.node_tree.nodes if n.type == 'VALTORGB')
    assert ramp.color_ramp.interpolation == 'CONSTANT' and len(ramp.color_ramp.elements) == 3
    assert not any(n.type in ('NORMAL_MAP', 'BUMP', 'BSDF_PRINCIPLED') for n in toon.node_tree.nodes)
    assert bpy.data.objects['Original_Mesh'].data == bpy.data.meshes['Hero2_OriginalMesh']
    result = {'preserved': after, 'bones': 26, 'subdivision': False, 'normal_map': False,
              'bands': BANDS, 'thresholds': THRESHOLDS, 'original_scene': 'Original', 'toon_scene': 'Toon',
              'smooth_faces': sum(p.use_smooth for p in mesh.data.polygons),
              'outline_width_source_units': OUTLINE_WIDTH}
    (ART / 'preservation_after.json').write_text(json.dumps(result, indent=2))
    print('PASS: Base Color bytes, all packed images, geometry, topology, UVs, weights and all action keys unchanged.')


def export_game():
    import io_scene_gltf2
    scene = bpy.data.scenes['Toon']
    bpy.context.window.scene = scene
    rig, mesh = bpy.data.objects['Hero2_Rig'], bpy.data.objects['Mesh_0']
    outline = bpy.data.objects['Toon_Outline']
    previous_hide_select = outline.hide_select
    outline.hide_select = False
    previous_action = rig.animation_data.action
    previous_material = mesh.data.materials[0]
    mesh.data.materials[0] = bpy.data.materials['Toon_Export_Matte']
    wrapper = bpy.data.objects.new('MeshyHero2', None)
    scene.collection.objects.link(wrapper)
    scale = 2.2 / (0.9458391070365906 + .950390100479126)
    wrapper.rotation_euler.z = math.pi / 2
    wrapper.scale = (scale,) * 3
    wrapper.location.z = .950390100479126 * scale
    rig.parent = wrapper
    rig.matrix_parent_inverse = Matrix.Identity(4)
    rig.animation_data.action = bpy.data.actions['idle']
    scene.frame_set(1)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in (rig, mesh, outline, wrapper):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    assert 'GLB' in [e[0] for e in io_scene_gltf2.get_format_items(None, bpy.context)]
    valid = [e.identifier for e in bpy.ops.export_scene.gltf.get_rna_type().properties['export_animation_mode'].enum_items]
    assert 'ACTIONS' in valid
    try:
        bpy.ops.export_scene.gltf(filepath=str(OUT / 'hero2.glb'), export_format='GLB', use_selection=True,
            export_yup=True, export_animations=True, export_animation_mode='ACTIONS',
            export_frame_range=False, export_force_sampling=True, export_frame_step=1,
            export_anim_slide_to_zero=True, export_skins=True, export_all_influences=False,
            export_apply=False, export_morph=False, export_rest_position_armature=True,
            export_optimize_animation_size=False, export_cameras=False, export_lights=False)
    finally:
        outline.hide_select = previous_hide_select
        mesh.data.materials[0] = previous_material
        rig.parent = None
        rig.matrix_parent_inverse = Matrix.Identity(4)
        rig.animation_data.action = previous_action
        bpy.data.objects.remove(wrapper, do_unlink=True)
        scene.frame_set(1)
    data = (OUT / 'hero2.glb').read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + size])
    assert len(doc['skins']) == 1 and len(doc['skins'][0]['joints']) == 26
    assert set(a['name'] for a in doc['animations']) == {'idle', 'walk', 'run'}
    assert len(doc['images']) == 1
    assert any(n.get('name') == 'Toon_Outline' and 'skin' in n for n in doc['nodes'])
    mat = next(m for m in doc['materials'] if m['name'] == 'Toon_Export_Matte')
    assert mat['pbrMetallicRoughness']['metallicFactor'] == 0 and 'normalTexture' not in mat
    view = doc['bufferViews'][doc['images'][0]['bufferView']]
    start = 20 + size + 8 + view.get('byteOffset', 0)
    image_hash = hashlib.sha256(data[start:start + view['byteLength']]).hexdigest()
    expected = json.loads((ART / 'preservation_before.json').read_text())['images']['Image_0']
    assert image_hash == expected, 'GLB changed Base Color bytes'
    print('PASS: exported GLB has exact original Base Color bytes, 26 bones, three clips, zero metallic and no normal map.')


def save():
    scene = bpy.data.scenes['Toon']
    bpy.context.window.scene = scene
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    bpy.data.scenes['Original'].view_settings.view_transform = 'AgX'
    bpy.data.objects['Hero2_Rig'].animation_data.action = bpy.data.actions['walk']
    bpy.data.objects['Original_Rig'].animation_data.action = bpy.data.actions['walk']
    scene.frame_start, scene.frame_end = 1, 30
    scene.frame_set(1)
    validate()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'hero2.blend'))


if __name__ == '__main__':
    bpy.ops.wm.open_mainfile(filepath=str(ART / 'hero2_live_before_toon.blend'))
    setup()
    validate()
    export_game()
    save()
