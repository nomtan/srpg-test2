"""Build the voxel hero sword and export it as a Godot-ready GLB.

Run inside Blender. The grip centre is the asset origin, so Godot can attach
SwordRoot directly to the character's hand_R BoneAttachment3D.
"""

import os
from pathlib import Path

import bpy


ROOT = Path(os.environ.get("SRPG_PROJECT_ROOT", r"C:\Users\nomur\Desktop\git\srpg-test2"))
OUTPUT = Path(os.environ.get(
    "VOXEL_SWORD_OUTPUT",
    ROOT / "assets/weapons/sword/hero_voxel_sword.glb",
))
COLLECTION_NAME = "Hero_Voxel_Sword_Export"


def material(name, color, metallic=0.0, roughness=0.72):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return mat


def clear_collection():
    old = bpy.data.collections.get(COLLECTION_NAME)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    collection = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)
    return collection


def add_cube(collection, parent, name, location, dimensions, mat, bevel=0.004):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new("VoxelEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    obj.parent = parent
    return obj


def build():
    collection = clear_collection()
    root = bpy.data.objects.new("SwordRoot", None)
    collection.objects.link(root)

    silver = material("Sword_Silver", (0.76, 0.79, 0.82), metallic=0.72, roughness=0.28)
    highlight = material("Sword_Edge_Highlight", (0.94, 0.96, 0.98), metallic=0.58, roughness=0.22)
    shadow = material("Sword_Blade_Shadow", (0.48, 0.52, 0.57), metallic=0.70, roughness=0.32)
    gold = material("Sword_Gold", (0.92, 0.60, 0.015), metallic=0.62, roughness=0.30)
    gold_light = material("Sword_Gold_Highlight", (1.0, 0.77, 0.04), metallic=0.48, roughness=0.28)
    leather = material("Sword_Leather", (0.30, 0.105, 0.035), roughness=0.88)
    leather_light = material("Sword_Leather_Light", (0.48, 0.19, 0.065), roughness=0.82)
    gem = material("Sword_Blue_Gem", (0.01, 0.30, 0.95), metallic=0.18, roughness=0.18)

    parts = []
    add = lambda name, loc, size, mat, bevel=0.004: parts.append(
        add_cube(collection, root, name, loc, size, mat, bevel)
    )

    # Grip centre is Z=0. The blade points along +Z and is thin on Y.
    add("Grip_Core", (0, 0, 0), (0.115, 0.105, 0.34), leather, 0.006)
    add("Grip_Wrap_Upper", (0, -0.057, 0.08), (0.125, 0.018, 0.08), leather_light, 0.002)
    add("Grip_Wrap_Lower", (0, -0.057, -0.08), (0.125, 0.018, 0.08), leather_light, 0.002)

    # Pommel, slightly blocky and stepped like the reference.
    add("Pommel_Collar", (0, 0, -0.205), (0.25, 0.14, 0.075), gold, 0.004)
    add("Pommel_Block", (0, 0, -0.275), (0.15, 0.15, 0.105), gold_light, 0.004)
    add("Pommel_End", (0, 0, -0.345), (0.105, 0.13, 0.055), gold, 0.003)

    # Ornate crossguard with stepped, upward-curving tips.
    add("Guard_Centre", (0, 0, 0.235), (0.30, 0.18, 0.18), gold, 0.005)
    add("Guard_Gem_Front", (0, -0.101, 0.245), (0.14, 0.026, 0.14), gem, 0.002)
    add("Guard_Left_Inner", (-0.23, 0, 0.235), (0.20, 0.14, 0.105), gold_light, 0.004)
    add("Guard_Right_Inner", (0.23, 0, 0.235), (0.20, 0.14, 0.105), gold_light, 0.004)
    add("Guard_Left_Step", (-0.37, 0, 0.285), (0.105, 0.14, 0.18), gold, 0.004)
    add("Guard_Right_Step", (0.37, 0, 0.285), (0.105, 0.14, 0.18), gold, 0.004)
    add("Guard_Left_Tip", (-0.45, 0, 0.37), (0.10, 0.15, 0.18), gold_light, 0.004)
    add("Guard_Right_Tip", (0.45, 0, 0.37), (0.10, 0.15, 0.18), gold_light, 0.004)

    # Broad three-tone blade and stepped point.
    add("Blade_Base", (0, 0, 0.43), (0.31, 0.105, 0.22), silver, 0.003)
    add("Blade_Centre", (0, 0, 0.78), (0.34, 0.09, 0.70), silver, 0.003)
    add("Blade_Left_Edge", (-0.145, -0.006, 0.78), (0.075, 0.105, 0.70), highlight, 0.002)
    add("Blade_Right_Edge", (0.145, 0.006, 0.78), (0.075, 0.105, 0.70), shadow, 0.002)
    add("Blade_Tip_Wide", (0, 0, 1.165), (0.25, 0.09, 0.12), silver, 0.002)
    add("Blade_Tip_Mid", (0, 0, 1.255), (0.17, 0.085, 0.10), highlight, 0.002)
    add("Blade_Tip_End", (0, 0, 1.325), (0.09, 0.08, 0.07), silver, 0.002)

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=False,
        collection=COLLECTION_NAME,
        export_animations=False,
        export_yup=True,
    )
    print({"output": str(OUTPUT), "parts": len(parts), "origin": "grip_center"})


build()
