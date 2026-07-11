"""Build crossed-quad grass prop GLBs with Blender."""

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy

PROPS = (
    ("prop_grass_short_01", "prop_grass_short_01.png", 0.9, 0.45),
    ("prop_grass_tall_01", "prop_grass_tall_01.png", 0.9, 0.85),
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tex", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args(argv)


def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for block in list(blocks):
            blocks.remove(block)


def make_material(name: str, texture_path: Path) -> bpy.types.Material:
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    if hasattr(material, "blend_method"):
        material.blend_method = "CLIP"
    if hasattr(material, "alpha_threshold"):
        material.alpha_threshold = 0.5
    material.use_backface_culling = False

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    specular = bsdf.inputs.get("Specular IOR Level")
    if specular:
        specular.default_value = 0.0
    image = bpy.data.images.load(str(texture_path))
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    alpha_clip = nodes.new("ShaderNodeMath")
    alpha_clip.operation = "GREATER_THAN"
    alpha_clip.inputs[1].default_value = 0.5
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(texture.outputs["Alpha"], alpha_clip.inputs[0])
    links.new(alpha_clip.outputs[0], bsdf.inputs["Alpha"])
    return material


def build_cross(name: str, material: bpy.types.Material, width: float, height: float) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    half_width = width / 2.0
    for angle in (math.radians(45), math.radians(135)):
        dx = math.cos(angle) * half_width
        dy = math.sin(angle) * half_width
        vertices = [bm.verts.new(point) for point in (
            (-dx, -dy, 0.0), (dx, dy, 0.0),
            (dx, dy, height), (-dx, -dy, height),
        )]
        face = bm.faces.new(vertices)
        for loop, uv in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv_layer].uv = uv
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    mesh.materials.append(material)
    bpy.context.collection.objects.link(obj)
    return obj


def main() -> None:
    args = parse_args()
    tex_dir = args.tex.resolve()
    out_dir = args.out.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    missing = [tex_dir / filename for _, filename, _, _ in PROPS if not (tex_dir / filename).is_file()]
    if missing:
        raise SystemExit("missing input texture(s): " + ", ".join(str(path) for path in missing))

    for name, texture_name, width, height in PROPS:
        reset_scene()
        material = make_material(f"MAT_{name}", tex_dir / texture_name)
        obj = build_cross(name, material, width, height)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        glb_path = out_dir / f"{name}.glb"
        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            use_selection=True,
            export_animations=False,
            export_yup=True,
        )
        print(f"wrote {glb_path}")


if __name__ == "__main__":
    main()
