"""Convert the Blockbench bow and staff sources into Godot-ready GLBs.

Run inside Blender.  Each exported model is centred on its grip so it can be
parented directly to the character's right-hand BoneAttachment3D.
"""

import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(os.environ.get("SRPG_PROJECT_ROOT", r"C:\Users\nomur\Desktop\git\srpg-test2"))
PIXEL_SCALE = 0.04
WEAPONS = {
    "bow": {
        "source": ROOT / "assets/weapons/bow/bow.bbmodel",
        "output": ROOT / "assets/weapons/bow/bow.glb",
        "grip": Vector((5.0, 8.0, 6.0)),
        "colors": {
            1: (0.78, 0.82, 0.76, 1.0),
            2: (0.34, 0.12, 0.035, 1.0),
            4: (0.12, 0.045, 0.018, 1.0),
            7: (0.82, 0.48, 0.055, 1.0),
        },
    },
    "staff": {
        "source": ROOT / "assets/weapons/staff/staff.bbmodel",
        "output": ROOT / "assets/weapons/staff/staff.glb",
        "grip": Vector((1.5, -8.0, 6.0)),
        "colors": {
            2: (0.30, 0.10, 0.025, 1.0),
            3: (0.08, 0.66, 0.94, 1.0),
            4: (0.13, 0.045, 0.015, 1.0),
            7: (0.86, 0.53, 0.075, 1.0),
        },
    },
}


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 0.62
    shader.inputs["Metallic"].default_value = 0.35 if "7" in name else 0.05
    return mat


def to_blender(point, grip):
    relative = Vector(point) - grip
    return Vector((relative.x, -relative.z, relative.y)) * PIXEL_SCALE


def rotate_about_origin(point, origin, degrees):
    rotation = Matrix.Rotation(math.radians(float(degrees)), 4, "Z")
    return Vector(origin) + rotation @ (Vector(point) - Vector(origin))


def add_cube(collection, element, grip, mat):
    start = Vector(element["from"])
    end = Vector(element["to"])
    centre = (start + end) * 0.5
    origin = Vector(element.get("origin", centre))
    rotation = element.get("rotation", [0.0, 0.0, 0.0])
    z_rotation = float(rotation[2])
    centre = rotate_about_origin(centre, origin, z_rotation)

    bpy.ops.mesh.primitive_cube_add(location=to_blender(centre, grip))
    obj = bpy.context.object
    obj.name = element.get("name", "Cube")
    size = end - start
    obj.dimensions = Vector((size.x, size.z, size.y)) * PIXEL_SCALE
    obj.rotation_euler.y = -math.radians(z_rotation)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def add_mesh(collection, element, grip, mat):
    vertex_keys = list(element["vertices"].keys())
    vertices = [to_blender(element["vertices"][key], grip) for key in vertex_keys]
    key_to_index = {key: index for index, key in enumerate(vertex_keys)}
    faces = []
    for face in element.get("faces", {}).values():
        indices = [key_to_index[key] for key in face.get("vertices", [])]
        if len(indices) >= 3:
            faces.append(indices)
    mesh = bpy.data.meshes.new(element.get("name", "Mesh"))
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(element.get("name", "Mesh"), mesh)
    collection.objects.link(obj)
    return obj


def build_weapon(name, config):
    with config["source"].open("r", encoding="utf-8-sig") as source_file:
        data = json.load(source_file)

    collection = bpy.data.collections.new("%s_Export" % name.title())
    bpy.context.scene.collection.children.link(collection)
    root = bpy.data.objects.new("%sRoot" % name.title(), None)
    collection.objects.link(root)
    materials = {
        index: material("%s_Palette_%d" % (name.title(), index), color)
        for index, color in config["colors"].items()
    }

    parts = []
    for element in data.get("elements", []):
        color_index = int(element.get("color", 2))
        mat = materials.get(color_index, next(iter(materials.values())))
        if element.get("type") == "cube":
            part = add_cube(collection, element, config["grip"], mat)
        elif element.get("type") == "mesh":
            part = add_mesh(collection, element, config["grip"], mat)
        else:
            continue
        part.parent = root
        parts.append(part)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = root
    config["output"].parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(config["output"]),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_yup=True,
    )
    print({"weapon": name, "output": str(config["output"]), "parts": len(parts)})


for weapon_name, weapon_config in WEAPONS.items():
    build_weapon(weapon_name, weapon_config)
