"""Blender-only deterministic channel/occlusion fixture, NOT a Tripo Face007.

Run with Blender --background --factory-startup --python this_file.py.
The intentionally simple geometry makes front mask and hair coverage testable.
"""
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_modular_parts import export, prepare_static, validate_expression_authoring
from character_asset_metrics import accessor_values, read_glb

ROOT = Path(__file__).resolve().parents[3]


def material(name, color):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    image = bpy.data.images.new(name + "FixtureTexture", width=4, height=4)
    image.generated_color = color
    image.pack()
    texture = result.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    result.node_tree.links.new(texture.outputs["Color"], result.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
    return result


def cube(name, center, dimensions, mat, head=False):
    # Coordinates below are authored in Godot Y-up; Blender uses Z-up.
    x, y, z = center
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -z, y))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (dimensions[0], dimensions[2], dimensions[1])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    if head:
        uv = obj.data.uv_layers.new(name="ExpressionUV")
        mask = obj.data.color_attributes.new(name="ExpressionMask", type="FLOAT_COLOR", domain="CORNER")
        obj.data.color_attributes.active_color = mask
        for polygon in obj.data.polygons:
            front = polygon.normal.y < -0.9
            for loop_index in polygon.loop_indices:
                co = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
                uv.data[loop_index].uv = tuple(max(0, min(1, v)) for v in ((co.x + 0.26) / 0.52, (co.z - 0.9) / 0.5))
                mask.data[loop_index].color = (1 if front else 0, 0, 0, 1)
        validate_expression_authoring(obj)
    return obj


head = cube("HeadMesh", (0, 1.15, 0.06), (0.52, 0.5, 0.52), material("Head", (0.8, 0.6, 0.4, 1)), True)
hair = cube("HairMesh", (-0.13, 1.29, 0.34), (0.26, 0.22, 0.04), material("Hair", (0.08, 0.04, 0.02, 1)))
export(ROOT / "artifacts/expression_v2_fixture/model.glb", [head, hair], False)
original_path = ROOT / "artifacts/expression_v2_fixture/model.glb"
# Exercise the same working-GLB path as production, including separate meshes.
objects = prepare_static("face", "007", {"scale": 1.0, "position": [0, 0, 0], "expression_rendering": "uv_v2"}, original_path)
normalized_path = ROOT / "artifacts/expression_v2_fixture/normalized.glb"
export(normalized_path, objects, False)
original, original_binary = read_glb(original_path)
normalized, normalized_binary = read_glb(normalized_path)


def channel_values(document, binary):
    result = {}
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            name = document["materials"][primitive["material"]]["name"]
            name = name.split(".")[0]
            # Compare sorted channel tuples: exporter may reorder vertices.
            channels = [accessor_values(document, binary, primitive["attributes"][key])
                        for key in sorted(primitive["attributes"])]
            result[name] = sorted(
                tuple(tuple(round(float(v), 5) for v in value) for value in values)
                for values in zip(*channels)
            )
    return result


assert channel_values(original, original_binary) == channel_values(normalized, normalized_binary), "Normalizer changed authored geometry, UV0, ExpressionUV or mask"
print("PASS: Normalizer working-GLB round trip preserves both meshes and authored channels")
print("EXPRESSION_V2_FIXTURE_EXPORTED")
