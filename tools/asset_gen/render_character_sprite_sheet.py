"""Render an animated GLB as anime-style 8-direction pixel sprite sheets.

Run with Blender:
    blender --background --python tools/asset_gen/render_character_sprite_sheet.py

The defaults render the current base character's one-handed-sword idle and run
animations. Output PNGs and metadata are written under assets/characters/sprites.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = ROOT / "assets/characters/py/base_body.glb"
DEFAULT_FACE = ROOT / "assets/characters/textures/anime_face_vain.png"
DEFAULT_OUTPUT = ROOT / "assets/characters/sprites"

DIRECTIONS = (
    "front",
    "front_right",
    "right",
    "back_right",
    "back",
    "back_left",
    "left",
    "front_left",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--face", type=Path, default=DEFAULT_FACE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--size", type=int, default=64)
    parser.add_argument("--samples", type=int, default=16)
    parser.add_argument(
        "--actions",
        nargs="+",
        default=("onehand_sword_idle:4", "onehand_sword_run:8"),
        help="Animation and frame count pairs, for example idle:4 run:8",
    )
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def clear_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            datablocks.remove(block)


def material_base_color(material: bpy.types.Material) -> tuple[float, float, float, float]:
    if material.use_nodes:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                return tuple(node.inputs["Base Color"].default_value)
    return tuple(material.diffuse_color)


def make_toon_material(material: bpy.types.Material) -> None:
    base = material_base_color(material)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (600, 0)
    emission = nodes.new("ShaderNodeEmission")
    emission.location = (400, 0)
    multiply = nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1.0
    multiply.inputs["Color2"].default_value = base
    multiply.location = (180, 0)
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (-40, 20)
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.38, 0.38, 0.42, 1.0)
    ramp.color_ramp.elements[1].position = 0.52
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    shader_to_rgb = nodes.new("ShaderNodeShaderToRGB")
    shader_to_rgb.location = (-260, 20)
    diffuse = nodes.new("ShaderNodeBsdfDiffuse")
    diffuse.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    diffuse.inputs["Roughness"].default_value = 1.0
    diffuse.location = (-480, 20)

    links.new(diffuse.outputs[0], shader_to_rgb.inputs[0])
    links.new(shader_to_rgb.outputs[0], ramp.inputs[0])
    links.new(ramp.outputs[0], multiply.inputs["Color1"])
    links.new(multiply.outputs[0], emission.inputs["Color"])
    links.new(emission.outputs[0], output.inputs["Surface"])


def add_face(armature: bpy.types.Object, face_path: Path) -> bpy.types.Object:
    # The imported character faces +X. These rest-pose coordinates match the
    # ganmen attachment used by BattleUnit in Godot.
    x = 0.266
    half_width = 0.219
    z_bottom = 1.19
    z_top = 1.565
    vertices = (
        (x, -half_width, z_bottom),
        (x, half_width, z_bottom),
        (x, half_width, z_top),
        (x, -half_width, z_top),
    )
    mesh = bpy.data.meshes.new("AnimeFaceMesh")
    mesh.from_pydata(vertices, [], ((0, 1, 2, 3),))
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop, uv in zip(mesh.polygons[0].loop_indices, ((0, 0), (1, 0), (1, 1), (0, 1))):
        uv_layer.data[loop].uv = uv

    material = bpy.data.materials.new("AnimeFace")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    mix = nodes.new("ShaderNodeMixShader")
    transparent = nodes.new("ShaderNodeBsdfTransparent")
    emission = nodes.new("ShaderNodeEmission")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(face_path))
    texture.interpolation = "Closest"
    links.new(texture.outputs["Color"], emission.inputs["Color"])
    links.new(texture.outputs["Alpha"], mix.inputs[0])
    links.new(transparent.outputs[0], mix.inputs[1])
    links.new(emission.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])
    try:
        material.surface_render_method = "DITHERED"
    except Exception:
        pass
    material.use_backface_culling = True
    mesh.materials.append(material)

    face = bpy.data.objects.new("AnimeFace", mesh)
    bpy.context.scene.collection.objects.link(face)
    group = face.vertex_groups.new(name="ganmen")
    group.add(range(4), 1.0, "REPLACE")
    modifier = face.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    face.parent = armature
    return face


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_render(size: int, samples: int) -> bpy.types.Object:
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.use_file_extension = True
    scene.render.fps = 24
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.render.use_freestyle = True
    scene.render.line_thickness = 0.72
    scene.world.color = (0.0, 0.0, 0.0)
    try:
        scene.eevee.taa_render_samples = samples
    except Exception:
        pass

    camera_data = bpy.data.cameras.new("SpriteCamera")
    camera = bpy.data.objects.new("SpriteCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (4.5, 0.0, 3.15)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.85
    camera_data.lens = 70
    point_at(camera, Vector((0.0, 0.0, 0.86)))
    scene.camera = camera

    sun_data = bpy.data.lights.new("SpriteKey", "SUN")
    sun_data.energy = 3.0
    sun_data.angle = math.radians(4.0)
    sun = bpy.data.objects.new("SpriteKey", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(35), 0.0, math.radians(55))

    fill_data = bpy.data.lights.new("SpriteFill", "SUN")
    fill_data.energy = 0.7
    fill = bpy.data.objects.new("SpriteFill", fill_data)
    scene.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(55), 0.0, math.radians(-120))
    return camera


def make_rotation_root(objects: list[bpy.types.Object]) -> bpy.types.Object:
    root = bpy.data.objects.new("SpriteRotationRoot", None)
    bpy.context.scene.collection.objects.link(root)
    object_set = set(objects)
    for obj in objects:
        if obj.parent not in object_set:
            matrix = obj.matrix_world.copy()
            obj.parent = root
            obj.matrix_world = matrix
    return root


def render_frame(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def render_action(
    armature: bpy.types.Object,
    root: bpy.types.Object,
    action_name: str,
    frame_count: int,
    size: int,
    output_dir: Path,
    frame_root: Path,
) -> dict:
    action = bpy.data.actions.get(action_name)
    if action is None:
        raise RuntimeError(f"Animation not found: {action_name}")
    if armature.animation_data is None:
        armature.animation_data_create()
    armature.animation_data.action = action
    for track in armature.animation_data.nla_tracks:
        track.mute = True

    start, end = action.frame_range
    sampled_frames = [start + (end - start) * index / frame_count for index in range(frame_count)]
    action_frame_dir = frame_root / action_name
    for direction_index, direction_name in enumerate(DIRECTIONS):
        root.rotation_euler.z = math.radians(-45.0 * direction_index)
        for frame_index, timeline_frame in enumerate(sampled_frames):
            bpy.context.scene.frame_set(int(timeline_frame), subframe=timeline_frame % 1.0)
            frame_path = action_frame_dir / f"{direction_index:02d}_{direction_name}_{frame_index:02d}.png"
            render_frame(frame_path)
            print(f"[sprite] {action_name}: {direction_name} {frame_index + 1}/{frame_count}")

    output = output_dir / f"vain_{action_name}_8dir.png"
    return {
        "action": action_name,
        "path": output.name,
        "cell_size": [size, size],
        "columns": frame_count,
        "rows": len(DIRECTIONS),
        "directions": list(DIRECTIONS),
        "frame_count": frame_count,
        "fps": 8 if "run" in action_name else 4,
        "frame_dir": str(action_frame_dir),
    }


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    frame_root = ROOT / ".godot" / "character_sprite_frames"
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(args.model))
    imported = list(bpy.context.scene.objects)
    armature = next(obj for obj in imported if obj.type == "ARMATURE")
    for material in list(bpy.data.materials):
        make_toon_material(material)
    face = add_face(armature, args.face)
    imported.append(face)
    configure_render(args.size, args.samples)
    root = make_rotation_root(imported)

    metadata = {"format": "8-direction anime pixel sprite sheet", "sheets": []}
    for item in args.actions:
        name, count = item.rsplit(":", 1)
        metadata["sheets"].append(
            render_action(armature, root, name, int(count), args.size, args.output, frame_root)
        )
    metadata_path = args.output / "vain_sprite_sheets.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[sprite] wrote {metadata_path}")


if __name__ == "__main__":
    main()
