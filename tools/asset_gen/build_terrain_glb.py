"""Build production terrain GLBs from the generated 32x32 textures.

Run headless via Blender:
    blender --background --python tools/asset_gen/build_terrain_glb.py -- \
        --tex assets/terrain/textures --out assets/terrain

Geometry conventions (must match scripts/map/voxel_map.gd / MapVisualTheme):
- CELL = 1.0 (GridSystem.CELL_SIZE)
- Top-face origin: the walkable surface sits at local Y=0 (Blender Z=0
  before the glTF Y-up conversion); solid geometry extends downward from
  there, never upward, since VoxelMap places tops at `Vector3(x+.5, cell.height, y+.5)`.
- Grass/dirt/stone assets are full blocks. Their top and side faces use
  separate textures: grass has a grassy top and grass-over-dirt sides,
  while a dirt block has no grass. Lower exposed height levels are still
  filled by cliff panels in VoxelMap.
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

ROOT = Path(__file__).resolve().parent.parent.parent
GRASS_SIDE_TEXTURE = ROOT / "assets" / "texture" / "grass" / "grass_side_01.png"

CELL = 1.0
PANEL_THICKNESS = 0.08

ASSETS = [
    # stem, kind, top/main texture, side texture for full blocks
    ("terrain_grass_top_01", "box", "terrain_grass_top_01.png", GRASS_SIDE_TEXTURE),
    ("terrain_dirt_top_01", "box", "terrain_dirt_top_01.png", "terrain_cliff_side_01.png"),
    ("terrain_stone_top_01", "box", "terrain_stone_top_01.png", "terrain_cliff_stone_01.png"),
    ("terrain_cliff_side_01", "panel", "terrain_cliff_side_01.png", None),
    ("terrain_cliff_side_top_01", "panel", "terrain_cliff_side_top_01.png", None),
    ("terrain_cliff_stone_01", "panel", "terrain_cliff_stone_01.png", None),
    ("terrain_stair_01", "stair", "terrain_stone_top_01.png", None),
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


def make_material(
    name: str,
    texture_path: Path,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
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
    if emission_strength > 0.0:
        emission = bsdf.inputs.get("Emission Color")
        if emission is None:
            emission = bsdf.inputs.get("Emission")
        if emission is not None:
            links.new(tex_node.outputs["Color"], emission)
        strength = bsdf.inputs.get("Emission Strength")
        if strength is not None:
            strength.default_value = emission_strength
    return material


def resolve_texture(tex_dir: Path, texture_ref) -> Path:
    texture_path = Path(texture_ref)
    return texture_path if texture_path.is_absolute() else tex_dir / texture_path


def map_box_side_uvs(mesh: bpy.types.Mesh) -> None:
    """Map the complete 0..1 texture rectangle onto each vertical face.

    Blender's primitive cube uses a six-face atlas layout by default. That
    makes each side sample only a small section when given a standalone tile.
    The horizontal faces intentionally retain their original UVs so the top
    surface keeps the established appearance.
    """
    uv_layer = mesh.uv_layers.active.data
    for polygon in mesh.polygons:
        normal = polygon.normal
        if abs(normal.z) > 0.5:
            continue
        for loop_index in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if abs(normal.x) > 0.5:
                uv = (vertex.y + 0.5, vertex.z + 0.5)
            else:
                uv = (vertex.x + 0.5, vertex.z + 0.5)
            uv_layer[loop_index].uv = uv


def build_box(
    name: str,
    top_material: bpy.types.Material,
    side_material: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    # Local Z=0 is the walkable surface; the block extends one cell downward.
    obj.location.z = -0.5
    obj.scale.x = CELL
    obj.scale.y = CELL
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh = obj.data
    mesh.materials.append(top_material)
    mesh.materials.append(side_material)
    map_box_side_uvs(mesh)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
        # Only the upward face is grass/topsoil; sides and hidden bottom use
        # the block's side material.
        polygon.material_index = 0 if polygon.normal.z > 0.5 else 1
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

    for stem, kind, texture_name, side_texture_name in ASSETS:
        reset_scene()
        material = make_material(
            f"MAT_{stem}", resolve_texture(tex_dir, texture_name)
        )
        if kind == "box":
            side_material = make_material(
                f"MAT_{stem}_side",
                resolve_texture(tex_dir, side_texture_name),
                0.16 if stem == "terrain_grass_top_01" else 0.0,
            )
            build_box(stem, material, side_material)
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
