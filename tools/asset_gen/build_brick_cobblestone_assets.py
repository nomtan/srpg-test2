"""Build brick and cobblestone cube/stair GLB assets.

Run with Blender:
    blender --background --python tools/asset_gen/build_brick_cobblestone_assets.py -- \
        --tex assets/texture/masonry --out assets/props/masonry
"""

import argparse
import sys
from pathlib import Path

import bpy

ASSETS = (
    ("bricks", "cube", "bricks.png"),
    ("brick_stairs", "stairs", "bricks.png"),
    ("cobblestone", "cube", "cobblestone.png"),
    ("cobblestone_stairs", "stairs", "cobblestone.png"),
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tex", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for block in list(blocks):
            blocks.remove(block)


def make_material(name: str, texture_path: Path) -> bpy.types.Material:
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.0
    image = bpy.data.images.load(str(texture_path))
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def map_cube_uvs(mesh: bpy.types.Mesh) -> None:
    uv_layer = mesh.uv_layers.active.data
    face_uvs = ((0, 0), (1, 0), (1, 1), (0, 1))
    for polygon in mesh.polygons:
        for loop_index, uv in zip(polygon.loop_indices, face_uvs):
            uv_layer[loop_index].uv = uv
        polygon.use_smooth = False


def add_box(name: str, size: tuple, location: tuple, material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    map_cube_uvs(obj.data)
    return obj


def build_cube(name: str, material) -> bpy.types.Object:
    # Local Z=0 is the walkable surface; terrain geometry extends downward.
    return add_box(name, (1.0, 1.0, 1.0), (0.0, 0.0, -0.5), material)


def build_stairs(name: str, material) -> bpy.types.Object:
    lower = add_box(f"{name}_lower", (1.0, 1.0, 0.5), (0.0, 0.0, -0.75), material)
    upper = add_box(f"{name}_upper", (1.0, 0.5, 0.5), (0.0, 0.25, -0.25), material)
    bpy.ops.object.select_all(action="DESELECT")
    lower.select_set(True)
    upper.select_set(True)
    bpy.context.view_layer.objects.active = lower
    bpy.ops.object.join()
    lower.name = name
    return lower


def main() -> None:
    args = parse_args()
    tex_dir = args.tex.resolve()
    out_dir = args.out.resolve()
    missing = [tex_dir / texture for _, _, texture in ASSETS if not (tex_dir / texture).is_file()]
    if missing:
        raise SystemExit("missing input texture(s): " + ", ".join(map(str, missing)))
    out_dir.mkdir(parents=True, exist_ok=True)

    for name, kind, texture_name in ASSETS:
        reset_scene()
        material = make_material(f"MAT_{name}", tex_dir / texture_name)
        obj = build_stairs(name, material) if kind == "stairs" else build_cube(name, material)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        output = out_dir / f"{name}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(output), export_format="GLB", use_selection=True,
            export_animations=False, export_yup=True,
        )
        print(f"wrote {output}")


if __name__ == "__main__":
    main()
