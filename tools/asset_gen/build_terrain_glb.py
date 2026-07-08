"""Build production terrain GLBs from the generated 32x32 textures.

Run headless via Blender:
    blender --background --python tools/asset_gen/build_terrain_glb.py -- \
        --tex assets/terrain/textures --out assets/terrain

Geometry conventions (must match scripts/map/voxel_map.gd / MapVisualTheme):
- CELL = 1.0 (GridSystem.CELL_SIZE)
- Top-face origin: the walkable surface sits at local Y=0 (Blender Z=0
  before the glTF Y-up conversion); solid geometry extends downward from
  there, never upward, since VoxelMap places tops at `Vector3(x+.5, cell.height, y+.5)`.
- TOP_THICKNESS = 0.2 for the grass/dirt/stone top slabs (thin plate, not a
  full cube - cliffs handle the vertical face separately).
- SURFACE_OFFSET = 0.08 for water/lava: the surface plane sits slightly
  below the top-face origin so it visibly sinks relative to solid ground.
"""

import argparse
import sys
from pathlib import Path

import bpy

CELL = 1.0
TOP_THICKNESS = 0.2
SURFACE_OFFSET = 0.08

# name -> (kind, output glb stem)
ASSETS = {
    "grass": ("box", "terrain_grass_top_01"),
    "dirt": ("box", "terrain_dirt_top_01"),
    "stone": ("box", "terrain_stone_top_01"),
    "water": ("plane", "terrain_water_plane_01"),
    "lava": ("plane", "terrain_lava_plane_01"),
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--tex", required=True)
    parser.add_argument("--out", required=True)
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
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.9
    image = bpy.data.images.load(str(texture_path))
    tex_node = nodes.new("ShaderNodeTexImage")
    tex_node.image = image
    tex_node.interpolation = "Closest"
    links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    return material


def remap_side_uvs(mesh: bpy.types.Mesh) -> None:
    """Side faces reuse the texture's top 0.2 V-band instead of the full image."""
    uv_layer = mesh.uv_layers.active.data
    for polygon in mesh.polygons:
        if abs(polygon.normal.z) > 0.5:
            continue  # top/bottom face, keep full 0..1 UV
        for loop_index in polygon.loop_indices:
            uv = uv_layer[loop_index].uv
            uv.y = 0.8 + uv.y * 0.2


def build_box(name: str, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.scale.z = TOP_THICKNESS
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.location.z = -TOP_THICKNESS / 2.0
    obj.scale.x = CELL
    obj.scale.y = CELL
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh = obj.data
    mesh.materials.append(material)
    remap_side_uvs(mesh)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return obj


def build_plane(name: str, material: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_plane_add(size=CELL, location=(0.0, 0.0, -SURFACE_OFFSET))
    obj = bpy.context.object
    obj.name = name
    mesh = obj.data
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return obj


def main() -> None:
    args = parse_args()
    tex_dir = Path(args.tex).resolve()
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    for name, (kind, stem) in ASSETS.items():
        reset_scene()
        texture_path = tex_dir / f"terrain_{name}_top_01.png"
        material = make_material(f"MAT_{name}", texture_path)
        if kind == "box":
            build_box(name, material)
        else:
            build_plane(name, material)

        glb_path = out_dir / f"{stem}.glb"
        bpy.ops.object.select_all(action="SELECT")
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
