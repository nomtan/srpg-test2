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
# Capless cliff panels are 0.08 thick. Centering them at 0.46 places their
# outward face at exactly 0.50, flush with the full block side above.
const CLIFF_PANEL_CENTER_OFFSET := 0.46

const SELECTABLE_BLOCK_TERRAINS := [
	"stone_brick", "infested_cracked_stone_bricks", "chiseled_stone_brick",
	"stone_brick_stairs", "bricks", "brick_stairs", "cobblestone",
	"cobblestone_stairs",
]

const MICRO_HEIGHT_TERRAINS := [
	"grass", "dirt", "forest", "stone", "stone_road", "rock", "wall",
	"high_ground",
]
const MICRO_GRID_SIZE := MapCellVisualData.MICRO_GRID_SIZE
const MICRO_CELL_SIZE := 1.0 / float(MICRO_GRID_SIZE)

const GRASS_SHORT_VARIANTS: Array[PackedScene] = [
	preload("res://assets/props/grass/prop_grass_short_01.tscn"),
	preload("res://assets/props/grass/prop_grass_short_02.tscn"),
	preload("res://assets/props/grass/prop_grass_short_03.tscn"),
]
const GRASS_MID_VARIANTS: Array[PackedScene] = [
	preload("res://assets/props/grass/prop_grass_mid_01.tscn"),
	preload("res://assets/props/grass/prop_grass_mid_02.tscn"),
	preload("res://assets/props/grass/prop_grass_mid_03.tscn"),
]
const SHORT_GRASS_CLUSTER_PATTERNS := [
	[
		{"variant": 0, "offset": Vector2(-0.14, -0.08), "rotation": -18.0, "scale": 0.90},
		{"variant": 1, "offset": Vector2(0.13, -0.05), "rotation": 24.0, "scale": 1.00},
		{"variant": 2, "offset": Vector2(0.00, 0.15), "rotation": 68.0, "scale": 0.86},
	],
	[
		{"variant": 2, "offset": Vector2(-0.16, -0.11), "rotation": 8.0, "scale": 0.88},
		{"variant": 0, "offset": Vector2(0.12, -0.14), "rotation": 42.0, "scale": 0.96},
		{"variant": 1, "offset": Vector2(0.16, 0.11), "rotation": 86.0, "scale": 0.84},
		{"variant": 0, "offset": Vector2(-0.10, 0.15), "rotation": 126.0, "scale": 0.92},
	],
	[
		{"variant": 1, "offset": Vector2(-0.18, 0.02), "rotation": -36.0, "scale": 0.82},
		{"variant": 2, "offset": Vector2(0.00, -0.04), "rotation": 12.0, "scale": 1.00},
		{"variant": 0, "offset": Vector2(0.18, 0.05), "rotation": 52.0, "scale": 0.88},
	],
	[
		{"variant": 0, "offset": Vector2(-0.15, -0.15), "rotation": -12.0, "scale": 0.94},
		{"variant": 2, "offset": Vector2(0.06, -0.13), "rotation": 34.0, "scale": 0.82},
		{"variant": 1, "offset": Vector2(0.16, 0.08), "rotation": 74.0, "scale": 0.98},
		{"variant": 2, "offset": Vector2(-0.08, 0.16), "rotation": 118.0, "scale": 0.86},
	],
]
const SHORT_GRASS_LARGE_CLUSTER_COUNTS := [5, 6, 7, 8, 9, 10, 11, 12]
const SHORT_GRASS_GOLDEN_ANGLE := 2.399963229728653

const GRASS_TRANSITION_SHADER := preload("res://shaders/flat/flat_grass_transition.gdshader")
const PAINTED_GRASS_OVERLAY_SHADER := preload("res://shaders/flat/flat_painted_grass_overlay.gdshader")
const GRASS_TRANSITION_TEXTURE := preload("res://assets/terrain/textures/terrain_grass_top_01.png")
const GRASS_TRANSITION_SOURCE_TERRAINS := ["grass", "high_ground"]
const GRASS_TRANSITION_TARGET_TERRAINS := ["dirt", "forest"]
const PAINTED_GRASS_OVERLAY_VARIANTS: Array[Texture2D] = [
	preload("res://assets/terrain/reference/grass_overlay_01.png"),
	preload("res://assets/terrain/reference/grass_overlay_02.png"),
	preload("res://assets/terrain/reference/grass_overlay_03.png"),
	preload("res://assets/terrain/reference/grass_overlay_04.png"),
]

@export var visual_theme: MapVisualTheme
@export var decorations: Array[MapDecorationData] = []
@export_group("Automatic grass props")
@export_range(0.0, 0.90, 0.025) var grass_prop_chance := 0.275
@export var grass_prop_seed := 1601
@export_range(0.0, 1.0, 0.01) var grass_short_weight := 0.65
@export_range(0.0, 1.0, 0.01) var grass_mid_weight := 0.25
@export_range(0.0, 1.0, 0.01) var grass_tall_weight := 0.10
@export_range(0.0, 1.0, 0.01) var grass_short_cluster_chance := 0.0
@export_range(0.0, 1.0, 0.01) var grass_short_large_cluster_chance := 0.0
@export_group("Terrain transitions")
@export var grass_transitions_enabled := false
@export_range(0.08, 0.40, 0.01) var grass_transition_fringe_width := 0.20
@export_group("Grass cliff overhangs")
@export var grass_cliff_overhangs_enabled := true
@export_range(0.04, 0.24, 0.01) var grass_cliff_overhang_width := 0.12
@export_group("Fluid surfaces")
# Optional visual fill inside a logically lowered water/lava cell. Production
# remains at 0; validation can remove a full cube while keeping its liquid
# surface visible just below the surrounding rim.
@export_range(0.0, 0.90, 0.01) var fluid_surface_fill_offset := 0.0
@export_group("Painted grass top overlays")
@export var painted_grass_overlays_enabled := false
@export var painted_grass_overlay_seed := 8123
@export_range(0.08, 0.40, 0.01) var painted_grass_edge_fringe_width := 0.18

var grid: GridSystem
var _grass_overhang_source_material: StandardMaterial3D

func build_from_grid(source_grid: GridSystem) -> void:
	grid = source_grid
	build_from_map_data(MapData.from_grid(source_grid, decorations))

func build_from_map_data(data: MapData) -> void:
	begin_render(data)
	_create_background_plane()
	for cell: MapCellVisualData in data.cells:
		if _uses_micro_height_profile(cell):
			_create_micro_height_top(cell)
		else:
			_create_top(cell)
		_create_cliff_sides(cell)
	_create_grass_cliff_overhangs()
	_create_painted_grass_overlays()
	_create_terrain_transitions()
	_create_decorations()


func _create_painted_grass_overlays() -> void:
	if not painted_grass_overlays_enabled:
		return
	const OVERLAY_SCALE := 1.48
	for cell: MapCellVisualData in map_data.cells:
		if not cell.terrain in GRASS_TRANSITION_SOURCE_TERRAINS:
			continue
		if _uses_micro_height_profile(cell):
			continue
		var rng := RandomNumberGenerator.new()
		# Coordinate mixing makes variant selection stable across rebuilds and
		# independent of MapData iteration order.
		rng.seed = (
			painted_grass_overlay_seed
			+ cell.position.x * 73856093
			+ cell.position.y * 19349663
		)
		var variant := PAINTED_GRASS_OVERLAY_VARIANTS[
			rng.randi_range(0, PAINTED_GRASS_OVERLAY_VARIANTS.size() - 1)
		]
		var position := cell.position
		var trim_n := _should_trim_painted_grass(position + Vector2i(0, -1), cell.height)
		var trim_e := _should_trim_painted_grass(position + Vector2i(1, 0), cell.height)
		var trim_s := _should_trim_painted_grass(position + Vector2i(0, 1), cell.height)
		var trim_w := _should_trim_painted_grass(position + Vector2i(-1, 0), cell.height)
		var trim_ne := not trim_n and not trim_e and _should_trim_painted_grass(position + Vector2i(1, -1), cell.height)
		var trim_se := not trim_s and not trim_e and _should_trim_painted_grass(position + Vector2i(1, 1), cell.height)
		var trim_sw := not trim_s and not trim_w and _should_trim_painted_grass(position + Vector2i(-1, 1), cell.height)
		var trim_nw := not trim_n and not trim_w and _should_trim_painted_grass(position + Vector2i(-1, -1), cell.height)
		var overlay := MeshInstance3D.new()
		overlay.name = "PaintedGrassTop_%d_%d" % [cell.position.x, cell.position.y]
		var plane := PlaneMesh.new()
		# Neighboring grass decals overlap into one carpet. The shader clips the
		# enlarged plane back at dirt, cliffs, and the outside of the map.
		plane.size = Vector2(OVERLAY_SCALE, OVERLAY_SCALE)
		overlay.mesh = plane
		overlay.position = Vector3(
			cell.position.x + 0.5,
			# A tiny deterministic height order prevents coplanar overlap seams
			# without lifting the carpet visibly above the soil.
			float(cell.height) + 0.021 + rng.randi_range(0, 15) * 0.00025,
			cell.position.y + 0.5
		)
		var material := ShaderMaterial.new()
		material.shader = PAINTED_GRASS_OVERLAY_SHADER
		material.set_shader_parameter("grass_tex", variant)
		material.set_shader_parameter("fringe_width", painted_grass_edge_fringe_width)
		material.set_shader_parameter("overlay_scale", OVERLAY_SCALE)
		material.set_shader_parameter("texture_turn", rng.randi_range(0, 3))
		material.set_shader_parameter("pattern_seed", float(rng.randi()))
		material.set_shader_parameter("trim_n", trim_n)
		material.set_shader_parameter("trim_e", trim_e)
		material.set_shader_parameter("trim_s", trim_s)
		material.set_shader_parameter("trim_w", trim_w)
		material.set_shader_parameter("trim_ne", trim_ne)
		material.set_shader_parameter("trim_se", trim_se)
		material.set_shader_parameter("trim_sw", trim_sw)
		material.set_shader_parameter("trim_nw", trim_nw)
		overlay.material_override = material
		overlay.set_meta("painted_grass_overlay", true)
		add_to_layer(overlay, TOP_LAYER)


func _should_trim_painted_grass(position: Vector2i, height: int) -> bool:
	if not map_data.is_in_bounds(position):
		return true
	var neighbor := map_data.get_cell(position)
	return not (
		neighbor != null
		and neighbor.height == height
		and neighbor.terrain in GRASS_TRANSITION_SOURCE_TERRAINS
		and not _uses_micro_height_profile(neighbor)
	)


func _create_terrain_transitions() -> void:
	if not grass_transitions_enabled:
		return
	for cell: MapCellVisualData in map_data.cells:
		if not cell.terrain in GRASS_TRANSITION_TARGET_TERRAINS:
			continue
		if _uses_micro_height_profile(cell):
			continue
		var position := cell.position
		var edge_n := _is_same_height_grass(position + Vector2i(0, -1), cell.height)
		var edge_e := _is_same_height_grass(position + Vector2i(1, 0), cell.height)
		var edge_s := _is_same_height_grass(position + Vector2i(0, 1), cell.height)
		var edge_w := _is_same_height_grass(position + Vector2i(-1, 0), cell.height)

		# A diagonal-only grass neighbor gets a small corner bite. If either
		# adjacent cardinal edge is grass, the edge strip already fills it.
		var corner_ne := not edge_n and not edge_e and _is_same_height_grass(position + Vector2i(1, -1), cell.height)
		var corner_se := not edge_s and not edge_e and _is_same_height_grass(position + Vector2i(1, 1), cell.height)
		var corner_sw := not edge_s and not edge_w and _is_same_height_grass(position + Vector2i(-1, 1), cell.height)
		var corner_nw := not edge_n and not edge_w and _is_same_height_grass(position + Vector2i(-1, -1), cell.height)

		if not (edge_n or edge_e or edge_s or edge_w or corner_ne or corner_se or corner_sw or corner_nw):
			continue
		_create_grass_transition_overlay(
			cell, edge_n, edge_e, edge_s, edge_w,
			corner_ne, corner_se, corner_sw, corner_nw
		)


func _is_same_height_grass(position: Vector2i, height: int) -> bool:
	if not map_data.is_in_bounds(position):
		return false
	var neighbor := map_data.get_cell(position)
	return (
		neighbor != null
		and neighbor.height == height
		and neighbor.terrain in GRASS_TRANSITION_SOURCE_TERRAINS
		and not _uses_micro_height_profile(neighbor)
	)


func _create_grass_transition_overlay(
	cell: MapCellVisualData,
	edge_n: bool,
	edge_e: bool,
	edge_s: bool,
	edge_w: bool,
	corner_ne: bool,
	corner_se: bool,
	corner_sw: bool,
	corner_nw: bool
) -> void:
	var overlay := MeshInstance3D.new()
	overlay.name = "GrassTransition_%d_%d" % [cell.position.x, cell.position.y]
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.998, 0.998)
	overlay.mesh = plane
	overlay.position = Vector3(cell.position.x + 0.5, float(cell.height) + 0.018, cell.position.y + 0.5)

	var material := ShaderMaterial.new()
	material.shader = GRASS_TRANSITION_SHADER
	material.set_shader_parameter("grass_tex", GRASS_TRANSITION_TEXTURE)
	material.set_shader_parameter("fringe_width", grass_transition_fringe_width)
	material.set_shader_parameter("edge_n", edge_n)
	material.set_shader_parameter("edge_e", edge_e)
	material.set_shader_parameter("edge_s", edge_s)
	material.set_shader_parameter("edge_w", edge_w)
	material.set_shader_parameter("corner_ne", corner_ne)
	material.set_shader_parameter("corner_se", corner_se)
	material.set_shader_parameter("corner_sw", corner_sw)
	material.set_shader_parameter("corner_nw", corner_nw)
	overlay.material_override = material
	overlay.set_meta("terrain_transition", "grass_to_dirt")
	add_to_layer(overlay, TOP_LAYER)


func _grass_dirt_boundary_flags(cell: MapCellVisualData) -> Dictionary:
	var position := cell.position
	var edge_n := _is_same_height_dirt(position + Vector2i(0, -1), cell.height)
	var edge_e := _is_same_height_dirt(position + Vector2i(1, 0), cell.height)
	var edge_s := _is_same_height_dirt(position + Vector2i(0, 1), cell.height)
	var edge_w := _is_same_height_dirt(position + Vector2i(-1, 0), cell.height)
	return {
		"edge_n": edge_n,
		"edge_e": edge_e,
		"edge_s": edge_s,
		"edge_w": edge_w,
		"corner_ne": (
			not edge_n
			and not edge_e
			and _is_same_height_dirt(position + Vector2i(1, -1), cell.height)
		),
		"corner_se": (
			not edge_s
			and not edge_e
			and _is_same_height_dirt(position + Vector2i(1, 1), cell.height)
		),
		"corner_sw": (
			not edge_s
			and not edge_w
			and _is_same_height_dirt(position + Vector2i(-1, 1), cell.height)
		),
		"corner_nw": (
			not edge_n
			and not edge_w
			and _is_same_height_dirt(position + Vector2i(-1, -1), cell.height)
		),
	}


func _is_same_height_dirt(position: Vector2i, height: int) -> bool:
	if not map_data.is_in_bounds(position):
		return false
	var neighbor := map_data.get_cell(position)
	return (
		neighbor != null
		and neighbor.height == height
		and neighbor.terrain in GRASS_TRANSITION_TARGET_TERRAINS
		and not _uses_micro_height_profile(neighbor)
	)


func _create_grass_cliff_overhangs() -> void:
	if not grass_cliff_overhangs_enabled:
		return
	for cell: MapCellVisualData in map_data.cells:
		if not cell.terrain in GRASS_TRANSITION_SOURCE_TERRAINS:
			continue
		if _uses_micro_height_profile(cell):
			continue
		var flags := _grass_cliff_edge_flags(cell)
		if not (flags.n or flags.e or flags.s or flags.w):
			continue
		_create_grass_cliff_overhang(cell, flags)


func _grass_cliff_edge_flags(cell: MapCellVisualData) -> Dictionary:
	var position := cell.position
	return {
		"n": _is_lower_grass_neighbor(position + Vector2i(0, -1), cell.height),
		"e": _is_lower_grass_neighbor(position + Vector2i(1, 0), cell.height),
		"s": _is_lower_grass_neighbor(position + Vector2i(0, 1), cell.height),
		"w": _is_lower_grass_neighbor(position + Vector2i(-1, 0), cell.height),
	}


func _is_lower_grass_neighbor(position: Vector2i, height: int) -> bool:
	if not map_data.is_in_bounds(position):
		return true
	var neighbor := map_data.get_cell(position)
	if neighbor == null:
		return true
	if neighbor.height < height:
		return true
	return neighbor.height == height and neighbor.terrain in ["water", "lava"]


func _create_grass_cliff_overhang(cell: MapCellVisualData, flags: Dictionary) -> void:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	const EDGE_SEGMENTS := 8
	if flags.n:
		_append_grass_overhang_strip(
			vertices, normals, uvs, cell, 0,
			Vector3(0.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 0.0, -1.0),
			EDGE_SEGMENTS
		)
	if flags.e:
		_append_grass_overhang_strip(
			vertices, normals, uvs, cell, 1,
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 1.0),
			Vector3(1.0, 0.0, 0.0),
			EDGE_SEGMENTS
		)
	if flags.s:
		_append_grass_overhang_strip(
			vertices, normals, uvs, cell, 2,
			Vector3(0.0, 0.0, 1.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 1.0),
			EDGE_SEGMENTS
		)
	if flags.w:
		_append_grass_overhang_strip(
			vertices, normals, uvs, cell, 3,
			Vector3(0.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 1.0),
			Vector3(-1.0, 0.0, 0.0),
			EDGE_SEGMENTS
		)

	# Adjacent exposed edges form a convex outer corner. Fill their gap with a
	# small rounded fan; concave inner corners are formed by the overlap of the
	# two neighboring cells' straight lips.
	if flags.n and flags.e:
		_append_grass_overhang_corner(vertices, normals, uvs, Vector2(1.0, 0.0), -90.0)
	if flags.e and flags.s:
		_append_grass_overhang_corner(vertices, normals, uvs, Vector2(1.0, 1.0), 0.0)
	if flags.s and flags.w:
		_append_grass_overhang_corner(vertices, normals, uvs, Vector2(0.0, 1.0), 90.0)
	if flags.w and flags.n:
		_append_grass_overhang_corner(vertices, normals, uvs, Vector2(0.0, 0.0), 180.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var overhang := MeshInstance3D.new()
	overhang.name = "GrassCliffOverhang_%d_%d" % [cell.position.x, cell.position.y]
	overhang.mesh = mesh
	overhang.material_override = _grass_cliff_overhang_material()
	var layer_order := (cell.position.x * 3 + cell.position.y * 5) % 11
	overhang.position = Vector3(
		cell.position.x,
		float(cell.height) + 0.024 + float(layer_order) * 0.00015,
		cell.position.y
	)
	# flat_validation routes this procedural surface through the same grass
	# material pipeline as the imported production grass top.
	overhang.set_meta("terrain_asset_name", "terrain_grass_top_01.glb")
	overhang.set_meta("grass_cliff_overhang", true)
	add_to_layer(overhang, TOP_LAYER)


func _append_grass_overhang_strip(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	uvs: Array[Vector2],
	cell: MapCellVisualData,
	edge_index: int,
	start: Vector3,
	tangent: Vector3,
	outward: Vector3,
	segments: int
) -> void:
	for segment in segments:
		var t0 := float(segment) / float(segments)
		var t1 := float(segment + 1) / float(segments)
		var inner_0 := start + tangent * t0
		var inner_1 := start + tangent * t1
		var outer_0 := inner_0 + outward * _grass_overhang_depth(
			cell.position, edge_index, segment, segments
		)
		var outer_1 := inner_1 + outward * _grass_overhang_depth(
			cell.position, edge_index, segment + 1, segments
		)
		_append_grass_overhang_triangle(vertices, normals, uvs, inner_0, inner_1, outer_1)
		_append_grass_overhang_triangle(vertices, normals, uvs, inner_0, outer_1, outer_0)


func _grass_overhang_depth(
	position: Vector2i,
	edge_index: int,
	sample_index: int,
	segments: int
) -> float:
	if sample_index == 0 or sample_index == segments:
		return grass_cliff_overhang_width
	var seed := float(
		position.x * 73856093
		+ position.y * 19349663
		+ edge_index * 83492791
		+ sample_index * 26544357
	)
	var variation := fposmod(sin(seed) * 43758.5453, 1.0)
	return grass_cliff_overhang_width * lerpf(0.82, 1.12, variation)


func _append_grass_overhang_corner(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	uvs: Array[Vector2],
	corner: Vector2,
	start_angle_degrees: float
) -> void:
	const CORNER_SEGMENTS := 4
	var center := Vector3(corner.x, 0.0, corner.y)
	for segment in CORNER_SEGMENTS:
		var angle_0 := deg_to_rad(
			start_angle_degrees + 90.0 * float(segment) / float(CORNER_SEGMENTS)
		)
		var angle_1 := deg_to_rad(
			start_angle_degrees + 90.0 * float(segment + 1) / float(CORNER_SEGMENTS)
		)
		var point_0 := center + Vector3(cos(angle_0), 0.0, sin(angle_0)) * grass_cliff_overhang_width
		var point_1 := center + Vector3(cos(angle_1), 0.0, sin(angle_1)) * grass_cliff_overhang_width
		_append_grass_overhang_triangle(vertices, normals, uvs, center, point_0, point_1)


func _append_grass_overhang_triangle(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	uvs: Array[Vector2],
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	# Keep every triangle front-facing from above regardless of edge direction.
	if (b - a).cross(c - a).y < 0.0:
		var swap := b
		b = c
		c = swap
	for point in [a, b, c]:
		vertices.append(point)
		normals.append(Vector3.UP)
		uvs.append(Vector2(point.x, point.z))


func _grass_cliff_overhang_material() -> StandardMaterial3D:
	if _grass_overhang_source_material:
		return _grass_overhang_source_material
	_grass_overhang_source_material = StandardMaterial3D.new()
	_grass_overhang_source_material.albedo_texture = GRASS_TRANSITION_TEXTURE
	_grass_overhang_source_material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	)
	_grass_overhang_source_material.roughness = 0.92
	return _grass_overhang_source_material


func _create_top(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var scene := visual_theme.top_scene_for(cell.terrain) if visual_theme else null
	var top := _instantiate(scene)
	if top:
		if cell.terrain in GRASS_TRANSITION_SOURCE_TERRAINS:
			top.set_meta(
				"grass_dirt_boundary_flags",
				_grass_dirt_boundary_flags(cell)
			)
		var surface_y := float(cell.height)
		if cell.terrain in ["water", "lava"]:
			surface_y += fluid_surface_fill_offset
		top.position = Vector3(grid_pos.x + 0.5, surface_y, grid_pos.y + 0.5)
		add_to_layer(top, WATER_LAYER if cell.terrain in ["water", "lava"] else TOP_LAYER)
	else:
		_create_fallback_top(grid_pos, cell)


func _uses_micro_height_profile(cell: MapCellVisualData) -> bool:
	return (
		cell.has_micro_height_profile()
		and (cell.terrain in MICRO_HEIGHT_TERRAINS or cell.terrain in SELECTABLE_BLOCK_TERRAINS)
	)


func _create_micro_height_top(cell: MapCellVisualData) -> void:
	var base_height := float(cell.height - 1)
	var material_terrain := "dirt" if cell.terrain == "grass" else cell.terrain
	var asset_name := _micro_terrain_asset_name(cell.terrain)
	for sub_z in MICRO_GRID_SIZE:
		for sub_x in MICRO_GRID_SIZE:
			var surface_height := cell.micro_surface_height(sub_x, sub_z)
			var column_height := surface_height - base_height
			var column := MeshInstance3D.new()
			column.name = "MicroTop_%d_%d_%d_%d" % [
				cell.position.x, cell.position.y, sub_x, sub_z
			]
			var box := BoxMesh.new()
			box.size = Vector3(MICRO_CELL_SIZE, column_height, MICRO_CELL_SIZE)
			# Put the source material on the mesh surface itself. Validation's A/B
			# material collector reads active surface materials; a node-level
			# material_override is not reported there for procedural PrimitiveMesh.
			box.material = _material_for(material_terrain)
			column.mesh = box
			column.position = Vector3(
				cell.position.x + (float(sub_x) + 0.5) * MICRO_CELL_SIZE,
				base_height + column_height * 0.5,
				cell.position.y + (float(sub_z) + 0.5) * MICRO_CELL_SIZE
			)
			# Validation can route procedural columns through the same A/B terrain
			# materials as imported GLB tops by using this explicit identity.
			column.set_meta("terrain_asset_name", asset_name)
			column.set_meta("micro_height_stage", cell.micro_height_at(sub_x, sub_z))
			add_to_layer(column, TOP_LAYER)


func _micro_terrain_asset_name(terrain: String) -> String:
	if terrain == "grass" or terrain == "high_ground" or terrain == "forest":
		return "terrain_grass_top_01.glb"
	if terrain in ["stone", "stone_road", "rock", "wall"]:
		return "terrain_stone_top_01.glb"
	if terrain in SELECTABLE_BLOCK_TERRAINS:
		return "stone_brick.glb"
	return "terrain_dirt_top_01.glb"

func _create_cliff_sides(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var is_water := cell.terrain == "water"
	var is_lava := cell.terrain == "lava"
	var is_fluid := is_water or is_lava
	if is_fluid and fluid_surface_fill_offset > SURFACE_OFFSET:
		_create_fluid_fill_sides(cell)
	var full_block_terrain := cell.terrain in [
		"grass", "dirt", "forest", "stone", "stone_road", "rock", "wall", "high_ground"
	] or cell.terrain in SELECTABLE_BLOCK_TERRAINS
	var has_full_top_block := (
		full_block_terrain
		and visual_theme != null
		and visual_theme.top_scene_for(cell.terrain) != null
	)
	for direction: Dictionary in DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + direction.offset
		var neighbor := map_data.get_cell(neighbor_pos) if map_data.is_in_bounds(neighbor_pos) else null
		var neighbor_height: int = neighbor.height if neighbor else 0
		var levels_needed := cell.height - neighbor_height
		var is_stone := (
			cell.terrain in ["stone", "stone_road", "rock", "wall"]
			or cell.terrain in SELECTABLE_BLOCK_TERRAINS
		)
		for level in levels_needed:
			var is_top_level := level == levels_needed - 1
			# The terrain asset itself now supplies all four sides of its top block.
			if is_top_level and has_full_top_block:
				continue
			var side_scene: PackedScene = null
			if visual_theme:
				if is_water:
					side_scene = visual_theme.water_side if visual_theme.water_side else visual_theme.cliff_side
				elif is_lava:
					side_scene = visual_theme.lava_side if visual_theme.lava_side else visual_theme.cliff_side
				else:
					side_scene = visual_theme.cliff_stone if is_stone else visual_theme.cliff_side
			var side := _instantiate(side_scene)
			if not side: side = _make_fallback_cliff(cell.terrain)
			if not is_fluid:
				# Preserve the owning block family across separately instanced
				# lower side panels. Validation uses this to keep grass-column
				# and dirt-column side parameters continuous at level seams.
				var side_block_key := "dirt"
				if cell.terrain in ["grass", "forest", "high_ground"]:
					side_block_key = "grass"
				elif (
					cell.terrain in ["stone", "stone_road", "rock", "wall"]
					or cell.terrain in SELECTABLE_BLOCK_TERRAINS
				):
					side_block_key = "stone"
				side.set_meta("terrain_side_block_key", side_block_key)
			var normal := Vector3(direction.offset.x, 0.0, direction.offset.y)
			var panel_offset := 0.495 if is_fluid else CLIFF_PANEL_CENTER_OFFSET
			side.position = Vector3(grid_pos.x + 0.5, neighbor_height + level + 0.5, grid_pos.y + 0.5) + normal * panel_offset
			if is_fluid and is_top_level:
				side.position.y -= SURFACE_OFFSET
			side.rotation_degrees.y = float(direction.yaw)
			add_to_layer(side, WATER_LAYER if is_fluid else CLIFF_LAYER)


func _create_fluid_fill_sides(cell: MapCellVisualData) -> void:
	# Validation can lift a logically lowered fluid surface toward the rim.
	# Fill that lifted interval with animated vertical quads so map edges and
	# gaps no longer reveal an infinitely thin water/lava plane.
	var side_height := fluid_surface_fill_offset - SURFACE_OFFSET
	var side_scene: PackedScene = null
	if visual_theme:
		side_scene = (
			visual_theme.water_side
			if cell.terrain == "water"
			else visual_theme.lava_side
		)
	for direction: Dictionary in DIRECTIONS:
		var neighbor_pos: Vector2i = cell.position + direction.offset
		var neighbor := (
			map_data.get_cell(neighbor_pos)
			if map_data.is_in_bounds(neighbor_pos)
			else null
		)
		# Adjacent cells of the same fluid form one continuous volume and do
		# not need an internal side face.
		if (
			neighbor
			and neighbor.terrain == cell.terrain
			and neighbor.height == cell.height
		):
			continue
		var side := _instantiate(side_scene)
		if not side:
			side = _make_fallback_cliff(cell.terrain)
		var normal := Vector3(direction.offset.x, 0.0, direction.offset.y)
		side.position = (
			Vector3(
				cell.position.x + 0.5,
				float(cell.height) + side_height * 0.5,
				cell.position.y + 0.5
			)
			+ normal * 0.495
		)
		side.rotation_degrees.y = float(direction.yaw)
		side.scale.y = side_height
		add_to_layer(side, WATER_LAYER)

func _create_decorations() -> void:
	for cell: MapCellVisualData in map_data.cells:
		for data: MapDecorationData in cell.props:
			_create_decoration(data, cell.height)
		_create_random_grass(cell)

func _create_decoration(data: MapDecorationData, cell_height: int) -> void:
	var scene := visual_theme.decoration_scene_for(data.kind) if visual_theme else null
	var decoration := _instantiate(scene, not data.kind in ["grass_short", "grass_tall"])
	if not decoration: decoration = _make_fallback_decoration(data.kind)
	decoration.position = Vector3(data.grid_position.x + 0.5, cell_height + data.height_offset, data.grid_position.y + 0.5)
	decoration.rotation_degrees.y = data.rotation_degrees
	decoration.scale = data.scale
	add_to_layer(decoration, PROP_LAYER)

func _create_random_grass(cell: MapCellVisualData) -> void:
	if cell.terrain != "grass" or not cell.props.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	# Coordinate mixing keeps the result stable regardless of cell iteration order.
	rng.seed = grass_prop_seed + cell.position.x * 73856093 + cell.position.y * 19349663
	if rng.randf() >= grass_prop_chance:
		return
	var total_weight := grass_short_weight + grass_mid_weight + grass_tall_weight
	var type_roll := rng.randf() * maxf(total_weight, 0.001)
	var kind := "grass_short"
	var scene: PackedScene
	if type_roll < grass_short_weight:
		var cluster_roll := rng.randf()
		if cluster_roll < grass_short_large_cluster_chance:
			_create_large_short_grass_cluster(cell, rng)
			return
		if (
			cluster_roll
			< grass_short_large_cluster_chance + grass_short_cluster_chance
		):
			_create_short_grass_cluster(cell, rng)
			return
		scene = GRASS_SHORT_VARIANTS[rng.randi_range(0, GRASS_SHORT_VARIANTS.size() - 1)]
	elif type_roll < grass_short_weight + grass_mid_weight:
		# Evenly choose one of the dedicated medium variants.
		scene = GRASS_MID_VARIANTS[rng.randi_range(0, GRASS_MID_VARIANTS.size() - 1)]
	else:
		kind = "grass_tall"
		scene = visual_theme.decoration_scene_for(kind) if visual_theme else null
	var grass := _instantiate(scene, false)
	if not grass:
		grass = _make_fallback_decoration(kind)
	grass.position = Vector3(
		cell.position.x + rng.randf_range(0.28, 0.72),
		float(cell.height),
		cell.position.y + rng.randf_range(0.28, 0.72)
	)
	grass.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	add_to_layer(grass, PROP_LAYER)


func _create_short_grass_cluster(
	cell: MapCellVisualData,
	rng: RandomNumberGenerator
) -> void:
	var pattern: Array = SHORT_GRASS_CLUSTER_PATTERNS[
		rng.randi_range(0, SHORT_GRASS_CLUSTER_PATTERNS.size() - 1)
	]
	var center := Vector2(
		rng.randf_range(0.42, 0.58),
		rng.randf_range(0.42, 0.58)
	)
	var cluster_rotation := rng.randf_range(0.0, TAU)
	for member: Dictionary in pattern:
		var variant_index: int = member.variant
		var grass := _instantiate(GRASS_SHORT_VARIANTS[variant_index], false)
		if not grass:
			grass = _make_fallback_decoration("grass_short")
		var offset: Vector2 = (member.offset as Vector2).rotated(cluster_rotation)
		grass.position = Vector3(
			cell.position.x + center.x + offset.x,
			float(cell.height),
			cell.position.y + center.y + offset.y
		)
		grass.rotation_degrees.y = (
			float(member.rotation)
			+ rad_to_deg(cluster_rotation)
			+ rng.randf_range(-8.0, 8.0)
		)
		var scale_value := float(member.scale) * rng.randf_range(0.92, 1.08)
		grass.scale *= scale_value
		add_to_layer(grass, PROP_LAYER)


func _create_large_short_grass_cluster(
	cell: MapCellVisualData,
	rng: RandomNumberGenerator
) -> void:
	var pattern_index := rng.randi_range(
		0,
		SHORT_GRASS_LARGE_CLUSTER_COUNTS.size() - 1
	)
	var grass_count: int = SHORT_GRASS_LARGE_CLUSTER_COUNTS[pattern_index]
	var center := Vector2(
		rng.randf_range(0.46, 0.54),
		rng.randf_range(0.46, 0.54)
	)
	var cluster_rotation := rng.randf_range(0.0, TAU)
	var variant_offset := rng.randi_range(0, GRASS_SHORT_VARIANTS.size() - 1)
	# Keep the total at 5-12 blades while replacing one short blade in the
	# smaller patterns, or two in the larger patterns, with tall grass.
	var tall_count := 1 if grass_count <= 8 else 2
	var first_tall_index := (pattern_index * 3 + variant_offset) % grass_count
	var second_tall_index := (
		(first_tall_index + grass_count / 2) % grass_count
		if tall_count == 2
		else -1
	)
	for index in grass_count:
		var normalized_index := (
			float(index) / float(maxi(grass_count - 1, 1))
		)
		var radius := 0.035 + sqrt(normalized_index) * 0.225
		var angle := (
			float(index) * SHORT_GRASS_GOLDEN_ANGLE
			+ cluster_rotation
			+ float(pattern_index) * 0.17
		)
		var offset := Vector2(cos(angle), sin(angle)) * radius
		offset += Vector2(
			rng.randf_range(-0.018, 0.018),
			rng.randf_range(-0.018, 0.018)
		)
		var variant_index := (
			index + variant_offset + pattern_index
		) % GRASS_SHORT_VARIANTS.size()
		var is_tall := (
			index == first_tall_index
			or index == second_tall_index
		)
		var scene: PackedScene = (
			visual_theme.decoration_scene_for("grass_tall")
			if is_tall and visual_theme
			else GRASS_SHORT_VARIANTS[variant_index]
		)
		var grass := _instantiate(scene, false)
		if not grass:
			grass = _make_fallback_decoration(
				"grass_tall" if is_tall else "grass_short"
			)
		grass.position = Vector3(
			cell.position.x + center.x + offset.x,
			float(cell.height),
			cell.position.y + center.y + offset.y
		)
		grass.rotation_degrees.y = (
			rad_to_deg(angle)
			+ float((index * 37 + pattern_index * 19) % 120)
			+ rng.randf_range(-7.0, 7.0)
		)
		var scale_value := (
			rng.randf_range(0.68, 0.82)
			if is_tall
			else rng.randf_range(0.72, 0.94)
		)
		grass.scale *= scale_value
		add_to_layer(grass, PROP_LAYER)


func _instantiate(scene: PackedScene, use_mipmaps := true) -> Node3D:
	if not scene: return null
	var instance := scene.instantiate()
	if instance is Node3D:
		_apply_nearest_filter(instance, use_mipmaps)
		return instance
	instance.free()
	push_warning("MapVisualTheme scenes must have a Node3D root")
	return null

func _apply_nearest_filter(node: Node3D, use_mipmaps := true) -> void:
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
					material.texture_filter = (
						BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
						if use_mipmaps else BaseMaterial3D.TEXTURE_FILTER_NEAREST
					)
	for child in node.get_children():
		if child is Node3D:
			_apply_nearest_filter(child, use_mipmaps)

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
	# Water/lava tops sink SURFACE_OFFSET below their cell height, so a
	# height-0 water/lava cell surfaces at y=-0.08. Keep this well below that
	# or the opaque background plane occludes the water surface from above.
	background.position = Vector3(map_data.width * 0.5, -0.5, map_data.depth * 0.5)
	background.material_override = _colored_material(Color("#313134"))
	add_to_layer(background, DEBUG_LAYER)
