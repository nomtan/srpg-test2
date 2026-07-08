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
- Cliff panels are centered at the panel's own origin (VoxelMap already
  positions them at `neighbor_height + level + 0.5`, offset by
  `normal * 0.495`), thickness PANEL_THICKNESS, matching the size of the
  fallback cliff box in `_make_fallback_cliff`.
- The stair asset bakes the same relative geometry as the fallback
  (`_create_fallback_top`'s stair branch + `_add_stair_steps`) into one
  mesh: a 0.96x0.18x0.96 base slab plus 5 receding/rising 0.9x0.12x0.19
  steps, so swapping in the real asset doesn't shift anything visually.
- Water/lava are NOT built here anymore (see assets/terrain/materials/) -
  they moved to hand-authored ShaderMaterial .tscn scenes since they're
  flat animated planes that don't need Blender.

Axis note: Blender is Z-up; export_yup=True converts (x, y, z) -> (x, z, -y).
So a Godot-space size/center (x, y=height, z=depth) becomes a Blender-space
size/location of (x, z, -y) before export.
"""

import argparse
import sys
from pathlib import Path

import bpy

CELL = 1.0
TOP_THICKNESS = 0.2
PANEL_THICKNESS = 0.08

ASSETS = [
    ("terrain_grass_top_01", "box", "terrain_grass_top_01.png"),
    ("terrain_dirt_top_01", "box", "terrain_dirt_top_01.png"),
    ("terrain_stone_top_01", "box", "terrain_stone_top_01.png"),
    ("terrain_cliff_side_01", "panel", "terrain_cliff_side_01.png"),
    ("terrain_cliff_side_top_01", "panel", "terrain_cliff_side_top_01.png"),
    ("terrain_cliff_stone_01", "panel", "terrain_cliff_stone_01.png"),
    ("terrain_stair_01", "stair", "terrain_stone_top_01.png"),
]


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


def build_panel(name: str, material: bpy.types.Material) -> bpy.types.Object:
    """A thin vertical 1x1 cliff panel, centered at its own origin (no offset -
    VoxelMap positions the instance directly at the panel's world center)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.scale.y = PANEL_THICKNESS  # Blender Y (thin) -> Godot Z (depth) after yup export
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh = obj.data
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    return obj


def _add_stair_part(name: str, godot_size: tuple, godot_center: tuple, material: bpy.types.Material) -> bpy.types.Object:
    blender_size = (godot_size[0], godot_size[2], godot_size[1])
    blender_loc = (godot_center[0], -godot_center[2], godot_center[1])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=blender_loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = blender_size
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def build_stair(name: str, material: bpy.types.Material) -> bpy.types.Object:
    """Bakes the fallback stair's base slab + 5 steps (voxel_map.gd
    _create_fallback_top / _add_stair_steps) into a single mesh."""
    parts = [_add_stair_part(f"{name}_base", (0.96, 0.18, 0.96), (0.0, -0.09, 0.0), material)]
    for index in range(5):
        y_center = -0.9 + index * 0.2
        z_center = -0.4 + index * 0.2
        parts.append(_add_stair_part(f"{name}_step{index}", (0.9, 0.12, 0.19), (0.0, y_center, z_center), material))

    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    parts[0].name = name
    return parts[0]


def main() -> None:
    args = parse_args()
    tex_dir = Path(args.tex).resolve()
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    for stem, kind, texture_name in ASSETS:
        reset_scene()
        material = make_material(f"MAT_{stem}", tex_dir / texture_name)
        if kind == "box":
            build_box(stem, material)
        elif kind == "panel":
            build_panel(stem, material)
        else:
            build_stair(stem, material)

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
