"""Convert the project's mesh-based Blockbench model to a Godot-ready GLB.

Run inside Blender. The source and output paths can be overridden by setting
BBMODEL_SOURCE and BBMODEL_OUTPUT in the environment.
"""

import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(os.environ.get("SRPG_PROJECT_ROOT", r"C:\Users\nomur\Desktop\git\srpg-test2"))
SOURCE = Path(os.environ.get("BBMODEL_SOURCE", ROOT / "assets/characters/base/base.bbmodel"))
OUTPUT = Path(os.environ.get("BBMODEL_OUTPUT", ROOT / "assets/characters/base/base.glb"))
COLLECTION_NAME = "BB_Base_Export"
BLOCKBENCH_UNIT_METERS = 1.0 / 16.0

# Blockbench's editor colour indices. These are intentionally neutral so the
# base remains useful as an untextured modelling/rigging reference.
PALETTE = (
    (0.48, 0.52, 0.58, 1.0),
    (0.70, 0.72, 0.76, 1.0),
    (0.84, 0.66, 0.51, 1.0),
    (0.38, 0.45, 0.55, 1.0),
    (0.55, 0.37, 0.28, 1.0),
    (0.30, 0.42, 0.62, 1.0),
    (0.50, 0.56, 0.64, 1.0),
    (0.32, 0.50, 0.42, 1.0),
    (0.62, 0.48, 0.34, 1.0),
    (0.40, 0.44, 0.50, 1.0),
)


def bb_to_blender(value):
    """This model uses BB X/front, Y/up, Z/left -> Blender X/right, Y/back, Z/up.

    Blender's glTF exporter maps Blender -Y to glTF/Godot +Z, which is the
    model's neutral SOUTH-facing direction expected by BattleUnit.
    """
    return (
        value[2] * BLOCKBENCH_UNIT_METERS,
        -value[0] * BLOCKBENCH_UNIT_METERS,
        value[1] * BLOCKBENCH_UNIT_METERS,
    )


def get_material(index):
    name = f"BB_Base_Color_{index:02d}"
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    color = PALETTE[index % len(PALETTE)]
    material.diffuse_color = color
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 0.82
    return material


def clear_export_collection():
    old = bpy.data.collections.get(COLLECTION_NAME)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    collection = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)
    return collection


def create_armature(collection):
    armature_data = bpy.data.armatures.new("BB_Base_Skeleton")
    armature = bpy.data.objects.new("BB_Base_Skeleton", armature_data)
    collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    # Coordinates are in Blender space. The skeleton is deliberately simple:
    # one rigidly weighted bone per movable Blockbench body section.
    definitions = {
        "root": ((0, 0, 0), (0, 0, 0.18), None),
        "pelvis": ((0, 0, 0.18), (0, 0, 0.40), "root"),
        "spine": ((0, 0, 0.40), (0, 0, 0.82), "pelvis"),
        "chest": ((0, 0, 0.82), (0, 0, 1.08), "spine"),
        "neck": ((0, 0, 1.08), (0, 0, 1.20), "chest"),
        "head": ((0, 0, 1.20), (0, 0, 1.70), "neck"),
        # Vertical arm bones make local-X rotation a forward/backward swing.
        # The former diagonal shoulder bones caused the walk cycle to swing
        # the arms sideways instead.
        "upper_arm_R": ((-0.44, 0, 1.00), (-0.44, 0, 0.68), "chest"),
        "forearm_R": ((-0.44, 0, 0.68), (-0.44, 0, 0.43), "upper_arm_R"),
        "hand_R": ((-0.44, 0, 0.43), (-0.44, 0, 0.22), "forearm_R"),
        "upper_arm_L": ((0.44, 0, 1.00), (0.44, 0, 0.68), "chest"),
        "forearm_L": ((0.44, 0, 0.68), (0.44, 0, 0.43), "upper_arm_L"),
        "hand_L": ((0.44, 0, 0.43), (0.44, 0, 0.22), "forearm_L"),
        "thigh_R": ((-0.19, 0, 0.34), (-0.19, 0, 0.18), "pelvis"),
        "shin_R": ((-0.19, 0, 0.18), (-0.19, 0, 0.06), "thigh_R"),
        "foot_R": ((-0.19, 0, 0.06), (-0.19, -0.18, 0.04), "shin_R"),
        "thigh_L": ((0.19, 0, 0.34), (0.19, 0, 0.18), "pelvis"),
        "shin_L": ((0.19, 0, 0.18), (0.19, 0, 0.06), "thigh_L"),
        "foot_L": ((0.19, 0, 0.06), (0.19, -0.18, 0.04), "shin_L"),
    }
    bones = {}
    for name, (head, tail, _) in definitions.items():
        bone = armature_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bones[name] = bone
    for name, (_, _, parent_name) in definitions.items():
        if parent_name:
            bones[name].parent = bones[parent_name]

    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def rigid_bind(obj, armature, bone_name):
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature


def create_walk_animation(armature):
    scene = bpy.context.scene
    scene.render.fps = 24
    armature.animation_data_create()
    action = bpy.data.actions.get("walk") or bpy.data.actions.new("walk")
    armature.animation_data.action = action

    animated_bones = (
        "upper_arm_R", "forearm_R", "upper_arm_L", "forearm_L",
        "thigh_R", "shin_R", "foot_R", "thigh_L", "shin_L", "foot_L",
    )
    for bone_name in animated_bones:
        armature.pose.bones[bone_name].rotation_mode = "XYZ"

    # Contact, passing, opposite contact, passing, and loop-closing contact.
    poses = {
        1: {
            "upper_arm_R": 20, "forearm_R": -8,
            "upper_arm_L": -20, "forearm_L": -18,
            "thigh_R": -24, "shin_R": 8, "foot_R": 8,
            "thigh_L": 24, "shin_L": 3, "foot_L": -8,
        },
        7: {
            "upper_arm_R": 0, "forearm_R": -12,
            "upper_arm_L": 0, "forearm_L": -12,
            "thigh_R": 0, "shin_R": 28, "foot_R": -4,
            "thigh_L": 0, "shin_L": 5, "foot_L": 4,
        },
        13: {
            "upper_arm_R": -20, "forearm_R": -18,
            "upper_arm_L": 20, "forearm_L": -8,
            "thigh_R": 24, "shin_R": 3, "foot_R": -8,
            "thigh_L": -24, "shin_L": 8, "foot_L": 8,
        },
        19: {
            "upper_arm_R": 0, "forearm_R": -12,
            "upper_arm_L": 0, "forearm_L": -12,
            "thigh_R": 0, "shin_R": 5, "foot_R": 4,
            "thigh_L": 0, "shin_L": 28, "foot_L": -4,
        },
        25: {
            "upper_arm_R": 20, "forearm_R": -8,
            "upper_arm_L": -20, "forearm_L": -18,
            "thigh_R": -24, "shin_R": 8, "foot_R": 8,
            "thigh_L": 24, "shin_L": 3, "foot_L": -8,
        },
    }
    for frame, rotations in poses.items():
        for bone_name, angle in rotations.items():
            bone = armature.pose.bones[bone_name]
            bone.rotation_euler.x = math.radians(angle)
            bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone_name)

    action.frame_start = 1
    action.frame_end = 25
    scene.frame_start = 1
    scene.frame_end = 25
    scene.frame_set(1)
    return action


# Element order is stable in the bbmodel and distinguishes duplicate Japanese
# part names such as the two feet and ankles.
ELEMENT_BONES = {
    0: "neck",
    1: "upper_arm_R",
    2: "upper_arm_L",
    3: "thigh_L",
    4: "thigh_R",
    5: "head",
    6: "foot_R",
    7: "shin_R",
    8: "foot_L",
    9: "shin_L",
    10: "forearm_R",
    11: "forearm_L",
    12: "hand_R",
    13: "hand_L",
    14: "chest",
    15: "upper_arm_R",
    16: "upper_arm_L",
    17: "head",
    18: "head",
    19: "pelvis",
}


def convert():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    collection = clear_export_collection()
    armature = create_armature(collection)
    created = []

    for element_index, element in enumerate(data.get("elements", [])):
        if not element.get("export", True) or element.get("type") != "mesh":
            continue

        vertex_items = list(element.get("vertices", {}).items())
        vertex_lookup = {key: index for index, (key, _) in enumerate(vertex_items)}
        origin = element.get("origin", (0, 0, 0))
        vertices = [
            bb_to_blender([value[i] + origin[i] for i in range(3)])
            for _, value in vertex_items
        ]
        faces = []
        for face in element.get("faces", {}).values():
            indices = [vertex_lookup[key] for key in face.get("vertices", []) if key in vertex_lookup]
            if len(indices) >= 3:
                faces.append(indices)

        mesh = bpy.data.meshes.new(f"{element['name']}_Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(f"{element_index:02d}_{element['name']}", mesh)
        collection.objects.link(obj)
        mesh.materials.append(get_material(int(element.get("color", 0))))
        for polygon in mesh.polygons:
            polygon.use_smooth = False
        rigid_bind(obj, armature, ELEMENT_BONES.get(element_index, "root"))
        created.append(obj)

    create_walk_animation(armature)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in created:
        obj.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=False,
        collection=COLLECTION_NAME,
        export_animations=True,
        export_yup=True,
    )
    print({
        "source": str(SOURCE),
        "output": str(OUTPUT),
        "objects": len(created),
        "bones": len(armature.data.bones),
    })


convert()
