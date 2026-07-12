"""Build a one-cell jungle-log block GLB with separate end and bark textures.

Run with Blender:
    blender --background --python tools/asset_gen/build_jungle_log_block.py -- \
        --tex assets/texture/jungle_log --out assets/props/log
"""

import argparse
import sys
from pathlib import Path

import bpy


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


def build_log(name: str, end_material, side_material) -> bpy.types.Object:
    # Blender Z-up. Base is Z=0 so the exported Godot prop stands on its origin.
    vertices = (
        (-0.5, -0.5, 0.0), (0.5, -0.5, 0.0),
        (0.5, 0.5, 0.0), (-0.5, 0.5, 0.0),
        (-0.5, -0.5, 1.0), (0.5, -0.5, 1.0),
        (0.5, 0.5, 1.0), (-0.5, 0.5, 1.0),
    )
    faces = (
        (0, 3, 2, 1), (4, 5, 6, 7),  # bottom, top (end grain)
        (0, 1, 5, 4), (1, 2, 6, 5),
        (2, 3, 7, 6), (3, 0, 4, 7),  # four bark sides
    )
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(end_material)
    mesh.materials.append(side_material)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    face_uvs = ((0, 0), (1, 0), (1, 1), (0, 1))
    for polygon in mesh.polygons:
        polygon.material_index = 0 if polygon.index < 2 else 1
        polygon.use_smooth = False
        for loop_index, uv in zip(polygon.loop_indices, face_uvs):
            uv_layer.data[loop_index].uv = uv
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def main() -> None:
    args = parse_args()
    tex_dir = args.tex.resolve()
    out_dir = args.out.resolve()
    end_path = tex_dir / "jungle_log_end_01.png"
    side_path = tex_dir / "jungle_log_side_01.png"
    missing = [path for path in (end_path, side_path) if not path.is_file()]
    if missing:
        raise SystemExit("missing input texture(s): " + ", ".join(map(str, missing)))

    out_dir.mkdir(parents=True, exist_ok=True)
    reset_scene()
    obj = build_log(
        "prop_jungle_log_block_01",
        make_material("MAT_jungle_log_end", end_path),
        make_material("MAT_jungle_log_side", side_path),
    )
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    output = out_dir / "prop_jungle_log_block_01.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", use_selection=True,
        export_animations=False, export_yup=True,
    )
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
