class_name VoxelMap
extends MapRenderer

const DIRECTIONS := [
	{"offset": Vector2i(0, -1), "yaw": 0.0},
	{"offset": Vector2i(1, 0), "yaw": 90.0},
	{"offset": Vector2i(0, 1), "yaw": 180.0},
	{"offset": Vector2i(-1, 0), "yaw": 270.0},
]

# Water/lava tops sink this far below the cell's logical height (see
# water_plane.tscn / lava_plane.tscn's Mesh transform); the top-level side
# panel must sink by the same amount or it pokes above the surface.
const SURFACE_OFFSET := 0.08

@export var visual_theme: MapVisualTheme
@export var decorations: Array[MapDecorationData] = []

var grid: GridSystem

func build_from_grid(source_grid: GridSystem) -> void:
	grid = source_grid
	build_from_map_data(MapData.from_grid(source_grid, decorations))

func build_from_map_data(data: MapData) -> void:
	begin_render(data)
	_create_background_plane()
	for cell: MapCellVisualData in data.cells:
		_create_top(cell)
		_create_cliff_sides(cell)
	_create_decorations()

func _create_top(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var scene := visual_theme.top_scene_for(cell.terrain) if visual_theme else null
	var top := _instantiate(scene)
	if top:
		top.position = Vector3(grid_pos.x + 0.5, float(cell.height), grid_pos.y + 0.5)
		add_to_layer(top, WATER_LAYER if cell.terrain in ["water", "lava"] else TOP_LAYER)
	else:
		_create_fallback_top(grid_pos, cell)

func _create_cliff_sides(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var is_water := cell.terrain == "water"
	var is_lava := cell.terrain == "lava"
	var is_fluid := is_water or is_lava
	for direction: Dictionary in DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + direction.offset
		var neighbor := map_data.get_cell(neighbor_pos) if map_data.is_in_bounds(neighbor_pos) else null
		var neighbor_height: int = neighbor.height if neighbor else 0
		var levels_needed := cell.height - neighbor_height
		var is_stone := cell.terrain in ["stone", "stone_road", "rock", "wall"]
		for level in levels_needed:
			var is_top_level := level == levels_needed - 1
			var side_scene: PackedScene = null
			if visual_theme:
				if is_water:
					side_scene = visual_theme.water_side if visual_theme.water_side else visual_theme.cliff_side
				elif is_lava:
					side_scene = visual_theme.lava_side if visual_theme.lava_side else visual_theme.cliff_side
				else:
					side_scene = visual_theme.cliff_stone if is_stone else visual_theme.cliff_side
					if is_top_level and not is_stone and visual_theme.cliff_side_top:
						side_scene = visual_theme.cliff_side_top
			var side := _instantiate(side_scene)
			if not side: side = _make_fallback_cliff(cell.terrain)
			var normal := Vector3(direction.offset.x, 0.0, direction.offset.y)
			side.position = Vector3(grid_pos.x + 0.5, neighbor_height + level + 0.5, grid_pos.y + 0.5) + normal * 0.495
			if is_fluid and is_top_level:
				side.position.y -= SURFACE_OFFSET
			side.rotation_degrees.y = float(direction.yaw)
			add_to_layer(side, WATER_LAYER if is_fluid else CLIFF_LAYER)

func _create_decorations() -> void:
	for cell: MapCellVisualData in map_data.cells:
		for data: MapDecorationData in cell.props:
			_create_decoration(data, cell.height)

func _create_decoration(data: MapDecorationData, cell_height: int) -> void:
	var scene := visual_theme.decoration_scene_for(data.kind) if visual_theme else null
	var decoration := _instantiate(scene)
	if not decoration: decoration = _make_fallback_decoration(data.kind)
	decoration.position = Vector3(data.grid_position.x + 0.5, cell_height + data.height_offset, data.grid_position.y + 0.5)
	decoration.rotation_degrees.y = data.rotation_degrees
	decoration.scale = data.scale
	add_to_layer(decoration, PROP_LAYER)

func _instantiate(scene: PackedScene) -> Node3D:
	if not scene: return null
	var instance := scene.instantiate()
	if instance is Node3D:
		_apply_nearest_mipmap_filter(instance)
		return instance
	instance.free()
	push_warning("MapVisualTheme scenes must have a Node3D root")
	return null

func _apply_nearest_mipmap_filter(node: Node3D) -> void:
	# Production terrain textures are 32x32 Nearest-filtered pixel art. Without
	# mipmaps, minifying them at normal gameplay camera distance aliases into
	# moire/checkerboard noise; NEAREST_WITH_MIPMAPS keeps the crisp look up
	# close while smoothing correctly at a distance.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh:
			for surface in mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D:
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for child in node.get_children():
		if child is Node3D:
			_apply_nearest_mipmap_filter(child)

func _create_fallback_top(grid_pos: Vector2i, cell: MapCellVisualData) -> void:
	var part := MeshInstance3D.new()
	if cell.terrain == "water":
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.98, 0.98)
		part.mesh = plane
	elif cell.terrain == "stair":
		var stair_base := BoxMesh.new()
		stair_base.size = Vector3(0.96, 0.18, 0.96)
		part.mesh = stair_base
		# Grid height is the walkable surface, so geometry must extend downward.
		part.position.y = -stair_base.size.y * 0.5
	else:
		var tile := BoxMesh.new()
		tile.size = Vector3(0.96, 0.2 if cell.terrain == "bridge" else 0.12, 0.96)
		part.mesh = tile
		part.position.y = -tile.size.y * 0.5
	part.material_override = _material_for(cell.terrain)
	part.position += Vector3(grid_pos.x + 0.5, cell.height, grid_pos.y + 0.5)
	add_to_layer(part, WATER_LAYER if cell.terrain == "water" else TOP_LAYER)
	if cell.terrain == "stair": _add_stair_steps(grid_pos, cell.height)

func _add_stair_steps(grid_pos: Vector2i, height: int) -> void:
	# The logical cell surface stays at `height`; these steps only bridge the
	# visible one-level rise from the neighboring cell.
	for index in 5:
		var step := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.12, 0.19)
		step.mesh = box
		step.material_override = _material_for("stair")
		step.position = Vector3(grid_pos.x + 0.5, height - 0.9 + index * 0.2, grid_pos.y + 0.1 + index * 0.2)
		add_to_layer(step, TOP_LAYER)

func _make_fallback_cliff(terrain: String) -> Node3D:
	var side := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.96, 0.08)
	side.mesh = box
	side.material_override = _material_for("stone" if terrain in ["stone", "stone_road", "rock", "wall"] else "dirt")
	return side

func _make_fallback_decoration(kind: String) -> Node3D:
	var part := MeshInstance3D.new()
	if kind == "flag_placeholder":
		var pole := BoxMesh.new()
		pole.size = Vector3(0.08, 1.2, 0.08)
		part.mesh = pole
		part.position.y = 0.6
		part.material_override = _colored_material(Color("#76503a"))
	elif kind == "broken_stone":
		var rock := SphereMesh.new()
		rock.radius = 0.22
		rock.height = 0.3
		part.mesh = rock
		part.position.y = 0.12
		part.material_override = _colored_material(Color("#77736d"))
	else:
		var grass := CylinderMesh.new()
		grass.top_radius = 0.05
		grass.bottom_radius = 0.22
		grass.height = 0.35
		part.mesh = grass
		part.position.y = 0.17
		part.material_override = _colored_material(Color("#3f7d32"))
	return part

func _material_for(terrain: String) -> StandardMaterial3D:
	var colors := {"grass": Color("#69a947"), "dirt": Color("#8c6748"), "forest": Color("#477b38"), "stone": Color("#817f78"), "stone_road": Color("#99958b"), "rock": Color("#55545a"), "wall": Color("#686872"), "high_ground": Color("#79a85e"), "water": Color("#3a83ce"), "lava": Color("#e64d18"), "bridge": Color("#9b6b3f"), "stair": Color("#aaa49a")}
	var material := _colored_material(colors.get(terrain, Color.GRAY))
	if terrain == "water":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.78
		material.roughness = 0.08
	return material

func _colored_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _create_background_plane() -> void:
	var background := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var margin := 60.0
	plane.size = Vector2(map_data.width + margin * 2.0, map_data.depth + margin * 2.0)
	background.mesh = plane
	background.position = Vector3(map_data.width * 0.5, -0.02, map_data.depth * 0.5)
	background.material_override = _colored_material(Color("#527c3f"))
	add_to_layer(background, DEBUG_LAYER)
