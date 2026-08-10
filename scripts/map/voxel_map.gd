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
const GRASS_TRANSITION_TEXTURE := preload("res://assets/terrain/textures/terrain_grass_top_01.png")
const GRASS_COVER_SOLID_COLOR := Color("#69a947")
const DARK_GRASS_COVER_SOLID_COLOR := Color("#507a38")
const STONE_FLOOR_SOLID_COLOR := Color("#d8d99a")
const STONE_FLOOR_LINE_COLOR := Color("#d99f86")
const SURFACE_COVER_OFFSET := 0.006
const LEAF_SHAPE_SIZE_MULTIPLIER := 2.2
const GRASS_TRANSITION_TARGET_TERRAINS := ["dirt", "forest"]
const LEAF_PATTERN_COLORS: Array[Color] = [
	Color("#c6d273"),
	Color("#b6c969"),
	Color("#9fbd5c"),
	Color("#aeca62"),
]
const DARK_LEAF_PATTERN_COLORS: Array[Color] = [
	Color("#3f6b2a"),
	Color("#365c24"),
	Color("#4a7a33"),
	Color("#2e551f"),
]
const STONE_EDGE_GRASS_COLORS: Array[Color] = [
	Color("#789d4c"),
	Color("#668d43"),
	Color("#527b39"),
	Color("#91ae58"),
]
const STONE_FRAGMENT_COLORS: Array[Color] = [
	Color("#d8d99a"),
	Color("#e1dfa4"),
	Color("#cbcf8e"),
]
const GRASS_STONE_CHIP_COLORS: Array[Color] = [
	Color("#69a947"),
	Color("#70ad4b"),
	Color("#639f42"),
]
const DARK_GRASS_STONE_CHIP_COLORS: Array[Color] = [
	Color("#507a38"),
	Color("#567f3c"),
	Color("#486f34"),
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
@export_group("Grass cover boundaries")
@export_range(0.08, 0.40, 0.01) var dark_grass_boundary_width := 0.24
@export_group("Grass cliff overhangs")
@export var grass_cliff_overhangs_enabled := true
@export_range(0.10, 0.60, 0.01) var grass_cliff_overhang_drop := 0.33
@export_group("Fluid surfaces")
# Optional visual fill inside a logically lowered water/lava cell. Production
# remains at 0; validation can remove a full cube while keeping its liquid
# surface visible just below the surrounding rim.
@export_range(0.0, 0.90, 0.01) var fluid_surface_fill_offset := 0.0
@export_group("Stone floor cover")
@export_range(0.0, 1.0, 0.025) var stone_floor_seam_grass_chance := 0.46
@export_range(0.0, 1.0, 0.025) var stone_floor_damage_chance := 0.28
@export_group("Painted grass top overlays")
@export var painted_grass_overlays_enabled := true
@export var painted_grass_overlay_seed := 8123
@export_range(0.0, 1.0, 0.025) var painted_grass_overlay_chance := 0.30
@export_range(0.0, 1.0, 0.025) var dark_leaf_overlay_chance := 0.26
@export_range(0.0, 1.0, 0.025) var dark_grass_pale_leaf_chance := 0.78
@export_range(0.0, 1.0, 0.025) var dark_grass_dark_leaf_chance := 0.82
@export_range(0.15, 0.70, 0.01) var painted_grass_overlay_min_size := 0.26
@export_range(0.15, 0.70, 0.01) var painted_grass_overlay_max_size := 0.46
# Kept for compatibility with existing preview scenes; sparse clusters no
# longer need edge-fringe trimming because they remain inside their cell.
@export_range(0.08, 0.40, 0.01) var painted_grass_edge_fringe_width := 0.18

var grid: GridSystem
var _solid_grass_cover_material: StandardMaterial3D
var _solid_dark_grass_cover_material: StandardMaterial3D
var _solid_stone_floor_material: StandardMaterial3D
var _stone_floor_line_material: StandardMaterial3D
var _leaf_pattern_material: StandardMaterial3D

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
	_create_stone_floor_boundaries()
	_create_grass_cover_boundaries()
	_create_grass_cliff_overhangs()
	_create_painted_grass_overlays()
	_create_dark_leaf_overlays()
	_create_terrain_transitions()
	_create_decorations()


func _base_terrain(cell: MapCellVisualData) -> String:
	return cell.resolved_base_terrain()


func _has_grass_cover(cell: MapCellVisualData) -> bool:
	return cell.resolved_surface_cover() in ["grass", "grass_dark"]


func _has_regular_grass_cover(cell: MapCellVisualData) -> bool:
	return cell.has_surface_cover("grass")


func _has_dark_grass_cover(cell: MapCellVisualData) -> bool:
	return cell.has_surface_cover("grass_dark")


func _has_stone_floor_cover(cell: MapCellVisualData) -> bool:
	return cell.resolved_surface_cover() in ["stone_floor", "stone_floor_worn"]


func _has_worn_stone_floor_cover(cell: MapCellVisualData) -> bool:
	return cell.has_surface_cover("stone_floor_worn")


func _create_grass_cover_boundaries() -> void:
	# Draw each light/dark seam once, from the dark cell into the regular grass
	# cell. Its irregular outer edge replaces the straight cover-plane join.
	for cell: MapCellVisualData in map_data.cells:
		if not _has_dark_grass_cover(cell) or _uses_micro_height_profile(cell):
			continue
		for edge_index in DIRECTIONS.size():
			var direction: Dictionary = DIRECTIONS[edge_index]
			var neighbor_position: Vector2i = cell.position + direction.offset
			if not map_data.is_in_bounds(neighbor_position):
				continue
			var neighbor := map_data.get_cell(neighbor_position)
			if (
				neighbor == null
				or neighbor.height != cell.height
				or not _has_regular_grass_cover(neighbor)
				or _uses_micro_height_profile(neighbor)
			):
				continue
			_create_dark_grass_boundary_fringe(
				cell, Vector2i(direction.offset), edge_index
			)


func _create_dark_grass_boundary_fringe(
	cell: MapCellVisualData,
	edge_offset: Vector2i,
	edge_index: int
) -> void:
	# Four broad sections produce large turf clumps along the seam instead of
	# a fine saw-tooth edge.
	const EDGE_SEGMENTS := 4
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var outward := Vector2(edge_offset)
	var tangent := Vector2(-outward.y, outward.x)
	var edge_center := (
		Vector2(cell.position) + Vector2(0.5, 0.5) + outward * 0.5
	)
	var edge_start := edge_center - tangent * 0.5
	for segment in EDGE_SEGMENTS:
		var t0 := float(segment) / float(EDGE_SEGMENTS)
		var t1 := float(segment + 1) / float(EDGE_SEGMENTS)
		var inner_0_2d := edge_start + tangent * t0
		var inner_1_2d := edge_start + tangent * t1
		var outer_0_2d := inner_0_2d + outward * _dark_grass_boundary_depth(
			cell.position, edge_index, segment, EDGE_SEGMENTS
		)
		var outer_1_2d := inner_1_2d + outward * _dark_grass_boundary_depth(
			cell.position, edge_index, segment + 1, EDGE_SEGMENTS
		)
		var inner_0 := Vector3(inner_0_2d.x, 0.0, inner_0_2d.y)
		var inner_1 := Vector3(inner_1_2d.x, 0.0, inner_1_2d.y)
		var outer_0 := Vector3(outer_0_2d.x, 0.0, outer_0_2d.y)
		var outer_1 := Vector3(outer_1_2d.x, 0.0, outer_1_2d.y)
		_append_grass_boundary_triangle(
			vertices, normals, uvs, inner_0, inner_1, outer_1
		)
		_append_grass_boundary_triangle(
			vertices, normals, uvs, inner_0, outer_1, outer_0
		)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var fringe := MeshInstance3D.new()
	fringe.name = "DarkGrassBoundary_%d_%d_%d" % [
		cell.position.x, cell.position.y, edge_index
	]
	fringe.mesh = mesh
	fringe.position.y = float(cell.height) + SURFACE_COVER_OFFSET + 0.003
	fringe.material_override = _solid_grass_cover_surface_material("grass_dark")
	fringe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fringe.set_meta("terrain_asset_name", "terrain_grass_dark_cover")
	fringe.set_meta("surface_cover", "grass_dark")
	fringe.set_meta("dark_grass_boundary", true)
	add_to_layer(fringe, TOP_LAYER)


func _dark_grass_boundary_depth(
	position: Vector2i,
	edge_index: int,
	sample_index: int,
	segments: int
) -> float:
	if sample_index == 0 or sample_index == segments:
		return dark_grass_boundary_width * 0.72
	var seed := float(
		position.x * 83492791
		+ position.y * 26544357
		+ edge_index * 73856093
		+ sample_index * 19349663
	)
	var variation := fposmod(sin(seed) * 43758.5453, 1.0)
	return dark_grass_boundary_width * lerpf(0.35, 1.45, variation)


func _append_grass_boundary_triangle(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	uvs: Array[Vector2],
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	# Godot's horizontal front faces use clockwise winding when viewed above.
	if (b - a).cross(c - a).y > 0.0:
		var swap := b
		b = c
		c = swap
	for point in [a, b, c]:
		vertices.append(point)
		normals.append(Vector3.UP)
		uvs.append(Vector2(point.x, point.z))


func _create_stone_floor_boundaries() -> void:
	for cell: MapCellVisualData in map_data.cells:
		if not _has_stone_floor_cover(cell) or _uses_micro_height_profile(cell):
			continue
		for edge_index in DIRECTIONS.size():
			var direction: Dictionary = DIRECTIONS[edge_index]
			var neighbor_position: Vector2i = cell.position + direction.offset
			if not map_data.is_in_bounds(neighbor_position):
				continue
			var neighbor := map_data.get_cell(neighbor_position)
			if (
				neighbor == null
				or neighbor.height != cell.height
				or not _has_grass_cover(neighbor)
				or _uses_micro_height_profile(neighbor)
			):
				continue
			_create_stone_floor_boundary(
				cell,
				direction.offset,
				edge_index,
				neighbor.resolved_surface_cover()
			)


func _create_stone_floor_boundary(
	cell: MapCellVisualData,
	edge_offset: Vector2i,
	edge_index: int,
	neighbor_cover_kind: String
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		painted_grass_overlay_seed
		+ cell.position.x * 92837111
		+ cell.position.y * 689287499
		+ edge_index * 283923481
	)
	var outward := Vector2(edge_offset)
	var tangent := Vector2(-outward.y, outward.x)
	_create_stone_edge_chips(
		cell, rng, outward, tangent, edge_index, neighbor_cover_kind
	)
	# Kept small and close to the seam: this remnant band represents a worn
	# tile edge, not a spray of rubble, so fragments stay near the boundary
	# line and grass clumps (below) carry most of the transition's visual
	# weight, matching the reference's soft grass-over-stone look.
	var fragment_count := rng.randi_range(1, 3)
	var large_fragment_index := rng.randi_range(0, fragment_count - 1)
	for segment in fragment_count:
		var edge_progress := (float(segment) + 0.5) / float(fragment_count) - 0.5
		var tangent_offset := edge_progress * 0.92
		tangent_offset += rng.randf_range(-0.06, 0.06)
		var fragment := MeshInstance3D.new()
		fragment.name = "StoneEdgeFragment_%d_%d_%d_%d" % [
			cell.position.x, cell.position.y, edge_index, segment
		]
		var fragment_size: float
		if segment == large_fragment_index:
			fragment_size = rng.randf_range(0.16, 0.26)
		elif rng.randf() < 0.28:
			fragment_size = rng.randf_range(0.10, 0.18)
		else:
			fragment_size = rng.randf_range(0.05, 0.11)
		fragment.mesh = _build_stone_fragment_mesh(
			rng, fragment_size, STONE_FRAGMENT_COLORS
		)
		# Stays on the stone side of the seam (outward < 0.5 is still inside
		# this cell) so it reads as a worn tile edge, not rubble scattered
		# across the grass.
		var fragment_center := (
			Vector2(cell.position)
			+ Vector2(0.5, 0.5)
			+ outward * rng.randf_range(0.30, 0.45)
			+ tangent * tangent_offset
		)
		fragment.position = Vector3(
			fragment_center.x,
			float(cell.height) + SURFACE_COVER_OFFSET + 0.006,
			fragment_center.y
		)
		fragment.material_override = _leaf_pattern_surface_material()
		fragment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fragment.set_meta("stone_floor_boundary", true)
		add_to_layer(fragment, TOP_LAYER)

		var grass_marks := MeshInstance3D.new()
		grass_marks.name = "StoneEdgeGrass_%d_%d_%d_%d" % [
			cell.position.x, cell.position.y, edge_index, segment
		]
		grass_marks.mesh = _build_leaf_pattern_mesh(
			rng,
			rng.randf_range(0.20, 0.32),
			STONE_EDGE_GRASS_COLORS
		)
		var grass_center := (
			Vector2(cell.position)
			+ Vector2(0.5, 0.5)
			+ outward * rng.randf_range(0.16, 0.42)
			+ tangent * tangent_offset
		)
		grass_marks.position = Vector3(
			grass_center.x,
			float(cell.height) + SURFACE_COVER_OFFSET + 0.009,
			grass_center.y
		)
		grass_marks.material_override = _leaf_pattern_surface_material()
		grass_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass_marks.set_meta("stone_floor_edge_grass", true)
		add_to_layer(grass_marks, TOP_LAYER)


func _create_stone_edge_chips(
	cell: MapCellVisualData,
	rng: RandomNumberGenerator,
	outward: Vector2,
	tangent: Vector2,
	edge_index: int,
	neighbor_cover_kind: String
) -> void:
	var chip_palette := (
		DARK_GRASS_STONE_CHIP_COLORS
		if neighbor_cover_kind == "grass_dark"
		else GRASS_STONE_CHIP_COLORS
	)
	var chip_count := rng.randi_range(2, 4)
	for chip_index in chip_count:
		var chip := MeshInstance3D.new()
		chip.name = "StoneEdgeChip_%d_%d_%d_%d" % [
			cell.position.x, cell.position.y, edge_index, chip_index
		]
		var chip_size := rng.randf_range(0.05, 0.16)
		chip.mesh = _build_stone_fragment_mesh(rng, chip_size, chip_palette)
		var edge_progress := (
			(float(chip_index) + rng.randf_range(0.25, 0.75))
			/ float(chip_count)
			- 0.5
		)
		var center := (
			Vector2(cell.position)
			+ Vector2(0.5, 0.5)
			+ outward * rng.randf_range(0.24, 0.42)
			+ tangent * (edge_progress * 0.92 + rng.randf_range(-0.10, 0.10))
		)
		chip.position = Vector3(
			center.x,
			float(cell.height) + SURFACE_COVER_OFFSET + 0.011,
			center.y
		)
		chip.material_override = _leaf_pattern_surface_material()
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.set_meta("stone_floor_chipped_edge", true)
		add_to_layer(chip, TOP_LAYER)


func _build_stone_fragment_mesh(
	rng: RandomNumberGenerator,
	size: float,
	palette: Array[Color]
) -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var colors: Array[Color] = []
	var indices: Array[int] = []
	var point_count := 3 if rng.randf() < 0.10 else 4
	var rotation: float
	if rng.randf() < 0.55:
		rotation = PI * 0.25 + float(rng.randi_range(0, 3)) * PI * 0.5
		rotation += rng.randf_range(-0.08, 0.08)
	else:
		rotation = float(rng.randi_range(0, 3)) * PI * 0.5
		rotation += rng.randf_range(-0.18, 0.18)
	var color := palette[
		rng.randi_range(0, palette.size() - 1)
	]
	var half_width := size * rng.randf_range(0.38, 0.58)
	var half_height := size * rng.randf_range(0.25, 0.48)
	var skew := size * rng.randf_range(-0.20, 0.20)
	var long_axis := Vector2(half_width, 0.0)
	var short_axis := Vector2(skew, half_height)
	var local_points := [
		-long_axis - short_axis,
		long_axis - short_axis,
		long_axis + short_axis,
		-long_axis + short_axis,
	]
	if point_count == 3:
		local_points.remove_at(rng.randi_range(0, local_points.size() - 1))
	for local_point: Vector2 in local_points:
		if point_count == 3:
			local_point.x *= rng.randf_range(0.88, 1.10)
			local_point.y *= rng.randf_range(0.88, 1.10)
		var point := local_point.rotated(rotation)
		vertices.append(Vector3(point.x, 0.0, point.y))
		colors.append(color)
	if point_count == 3:
		indices.append_array([0, 2, 1])
	else:
		indices.append_array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh




func _create_painted_grass_overlays() -> void:
	if not painted_grass_overlays_enabled:
		return
	for cell: MapCellVisualData in map_data.cells:
		if not _has_grass_cover(cell):
			continue
		var is_dark := _has_dark_grass_cover(cell)
		var palette := LEAF_PATTERN_COLORS
		var boundary_edges := _grass_boundary_leaf_edges(cell, is_dark)
		var is_required_boundary := not boundary_edges.is_empty()
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			painted_grass_overlay_seed
			+ cell.position.x * 73856093
			+ cell.position.y * 19349663
		)
		# Boundary cells always receive leaves. Dark grass carries a much denser
		# pale pattern than regular grass, matching its overgrown appearance.
		var scatter_chance := (
			dark_grass_pale_leaf_chance
			if is_dark
			else painted_grass_overlay_chance
		)
		if not is_required_boundary and rng.randf() >= scatter_chance:
			continue
		if _uses_micro_height_profile(cell):
			_create_micro_leaf_patterns(cell, rng, palette)
		else:
			var cluster_count := (
				rng.randi_range(2, 4)
				if is_dark
				else (2 if rng.randf() < 0.18 else 1)
			)
			for cluster_index in cluster_count:
				if is_required_boundary:
					var edge_offset: Vector2i = boundary_edges[
						rng.randi_range(0, boundary_edges.size() - 1)
					]
					_create_leaf_pattern(
						cell,
						rng,
						Vector2(cell.position)
							+ Vector2(0.5, 0.5)
							+ Vector2(edge_offset) * 0.31,
						0.42,
						float(cell.height),
						cluster_index,
						palette
					)
				else:
					_create_leaf_pattern(
						cell,
						rng,
						Vector2(cell.position) + Vector2(0.5, 0.5),
						0.90,
						float(cell.height),
						cluster_index,
						palette
					)


func _create_dark_leaf_overlays() -> void:
	if not painted_grass_overlays_enabled:
		return
	for cell: MapCellVisualData in map_data.cells:
		if not _has_grass_cover(cell):
			continue
		var is_dark_grass := _has_dark_grass_cover(cell)
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			painted_grass_overlay_seed
			+ cell.position.x * 83492791
			+ cell.position.y * 19349669
			+ 149417
		)
		var scatter_chance := (
			dark_grass_dark_leaf_chance
			if is_dark_grass
			else dark_leaf_overlay_chance
		)
		if rng.randf() >= scatter_chance:
			continue
		var cluster_count := (
			rng.randi_range(2, 4)
			if is_dark_grass
			else (2 if rng.randf() < 0.16 else 1)
		)
		for cluster_index in cluster_count:
			if _uses_micro_height_profile(cell):
				var sub_x := rng.randi_range(0, MICRO_GRID_SIZE - 1)
				var sub_z := rng.randi_range(0, MICRO_GRID_SIZE - 1)
				_create_leaf_pattern(
					cell,
					rng,
					Vector2(
						cell.position.x + (float(sub_x) + 0.5) * MICRO_CELL_SIZE,
						cell.position.y + (float(sub_z) + 0.5) * MICRO_CELL_SIZE
					),
					MICRO_CELL_SIZE,
					cell.micro_surface_height(sub_x, sub_z),
					cluster_index,
					DARK_LEAF_PATTERN_COLORS,
					"dark"
				)
			else:
				_create_leaf_pattern(
					cell,
					rng,
					Vector2(cell.position) + Vector2(0.5, 0.5),
					0.90,
					float(cell.height),
					cluster_index,
					DARK_LEAF_PATTERN_COLORS,
					"dark"
				)


func _grass_boundary_leaf_edges(
	cell: MapCellVisualData, is_dark: bool = false
) -> Array[Vector2i]:
	var boundary_edges: Array[Vector2i] = []
	if not _has_grass_cover(cell):
		return boundary_edges
	# Regular grass marks its boundary with dark grass or stone floor. Dark
	# grass only marks its boundary with regular grass - stone floor already
	# gets its own grass-spilling-from-the-seam treatment in
	# _create_stone_floor_seam_grass, so dark leaf marks would be redundant
	# (and wrong-colored) sitting on the stone side.
	var target_covers := (
		["grass"] if is_dark else ["stone_floor", "stone_floor_worn", "grass_dark"]
	)
	for direction: Dictionary in DIRECTIONS:
		var neighbor_position: Vector2i = cell.position + direction.offset
		if not map_data.is_in_bounds(neighbor_position):
			continue
		var neighbor := map_data.get_cell(neighbor_position)
		if (
			neighbor != null
			and neighbor.height == cell.height
			and neighbor.resolved_surface_cover() in target_covers
		):
			boundary_edges.append(direction.offset)
	return boundary_edges


func _create_micro_leaf_patterns(
	cell: MapCellVisualData,
	rng: RandomNumberGenerator,
	palette: Array[Color]
) -> void:
	var required_index := rng.randi_range(0, MICRO_GRID_SIZE * MICRO_GRID_SIZE - 1)
	for sub_z in MICRO_GRID_SIZE:
		for sub_x in MICRO_GRID_SIZE:
			var sub_index := sub_z * MICRO_GRID_SIZE + sub_x
			if (
				sub_index != required_index
				and rng.randf() >= painted_grass_overlay_chance * 0.42
			):
				continue
			_create_leaf_pattern(
				cell,
				rng,
				Vector2(
					cell.position.x + (float(sub_x) + 0.5) * MICRO_CELL_SIZE,
					cell.position.y + (float(sub_z) + 0.5) * MICRO_CELL_SIZE
				),
				MICRO_CELL_SIZE,
				cell.micro_surface_height(sub_x, sub_z),
				sub_index,
				palette
			)


func _create_leaf_pattern(
	cell: MapCellVisualData,
	rng: RandomNumberGenerator,
	area_center: Vector2,
	area_size: float,
	surface_height: float,
	cluster_index: int,
	palette: Array[Color],
	pattern_kind := "pale"
) -> void:
	var min_size := minf(
		painted_grass_overlay_min_size,
		painted_grass_overlay_max_size
	) * area_size
	var max_size := maxf(
		painted_grass_overlay_min_size,
		painted_grass_overlay_max_size
	) * area_size
	var pattern_size := rng.randf_range(min_size, max_size)
	var offset_limit := maxf(area_size * 0.5 - pattern_size * 0.5 - 0.02, 0.0)
	var overlay := MeshInstance3D.new()
	overlay.name = "Grass%sLeafPattern_%d_%d_%d" % [
		pattern_kind.capitalize(), cell.position.x, cell.position.y, cluster_index
	]
	overlay.mesh = _build_leaf_pattern_mesh(
		rng, pattern_size, palette
	)
	overlay.position = Vector3(
		area_center.x + rng.randf_range(-offset_limit, offset_limit),
		surface_height + SURFACE_COVER_OFFSET + 0.006
			+ cluster_index * 0.0002
			+ (0.0001 if pattern_kind == "dark" else 0.0),
		area_center.y + rng.randf_range(-offset_limit, offset_limit)
	)
	overlay.material_override = _leaf_pattern_surface_material()
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.set_meta("painted_grass_overlay", true)
	overlay.set_meta("dark_leaf_pattern", pattern_kind == "dark")
	add_to_layer(overlay, TOP_LAYER)


func _build_leaf_pattern_mesh(
	rng: RandomNumberGenerator,
	pattern_size: float,
	palette: Array[Color]
) -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var colors: Array[Color] = []
	var indices: Array[int] = []
	var leaf_count := rng.randi_range(5, 11)
	for leaf_index in leaf_count:
		var angle := rng.randf_range(0.0, TAU)
		var distance := sqrt(rng.randf()) * pattern_size * 0.40
		var center := Vector2(cos(angle), sin(angle)) * distance
		center += Vector2(
			rng.randf_range(-0.018, 0.018),
			rng.randf_range(-0.018, 0.018)
		) * pattern_size
		var leaf_angle: float
		var angle_style := rng.randf()
		if angle_style < 0.58:
			leaf_angle = float(rng.randi_range(0, 3) * 2 + 1) * PI * 0.25
			leaf_angle += rng.randf_range(-0.07, 0.07)
		elif angle_style < 0.82:
			leaf_angle = float(rng.randi_range(0, 3)) * PI * 0.5
			leaf_angle += rng.randf_range(-0.07, 0.07)
		else:
			leaf_angle = rng.randf_range(0.0, TAU)
		var direction := Vector2(cos(leaf_angle), sin(leaf_angle))
		var side := Vector2(-direction.y, direction.x)
		var length := (
			pattern_size
			* rng.randf_range(0.055, 0.145)
			* LEAF_SHAPE_SIZE_MULTIPLIER
		)
		var width := length * rng.randf_range(0.42, 0.92)
		var color := palette[
			rng.randi_range(0, palette.size() - 1)
		]
		if rng.randf() < 0.10:
			_append_triangle_leaf(
				vertices, colors, indices, center,
				direction, side, length, width, color, rng
			)
		else:
			_append_quad_leaf(
				vertices, colors, indices, center,
				direction, side, length, width, color, rng
			)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_triangle_leaf(
	vertices: Array[Vector3],
	colors: Array[Color],
	indices: Array[int],
	center: Vector2,
	direction: Vector2,
	side: Vector2,
	length: float,
	width: float,
	color: Color,
	rng: RandomNumberGenerator
) -> void:
	var base_index := vertices.size()
	var points := [
		center + direction * length * rng.randf_range(0.45, 0.68),
		center - direction * length * rng.randf_range(0.25, 0.52)
			+ side * width * rng.randf_range(0.35, 0.62),
		center - direction * length * rng.randf_range(0.25, 0.52)
			- side * width * rng.randf_range(0.35, 0.62),
	]
	for point: Vector2 in points:
		vertices.append(Vector3(point.x, 0.0, point.y))
		colors.append(color)
	indices.append_array([
		base_index, base_index + 2, base_index + 1
	])


func _append_quad_leaf(
	vertices: Array[Vector3],
	colors: Array[Color],
	indices: Array[int],
	center: Vector2,
	direction: Vector2,
	side: Vector2,
	length: float,
	width: float,
	color: Color,
	rng: RandomNumberGenerator
) -> void:
	var base_index := vertices.size()
	var half_length := length * rng.randf_range(0.38, 0.62)
	var half_width := width * rng.randf_range(0.30, 0.56)
	var skew := length * rng.randf_range(-0.28, 0.28)
	var long_axis := direction * half_length
	var short_axis := side * half_width + direction * skew
	var points := [
		center - long_axis - short_axis,
		center + long_axis - short_axis,
		center + long_axis + short_axis,
		center - long_axis + short_axis,
	]
	for point: Vector2 in points:
		vertices.append(Vector3(point.x, 0.0, point.y))
		colors.append(color)
	indices.append_array([
		base_index, base_index + 2, base_index + 1,
		base_index, base_index + 3, base_index + 2,
	])


func _leaf_pattern_surface_material() -> StandardMaterial3D:
	if _leaf_pattern_material:
		return _leaf_pattern_material
	_leaf_pattern_material = StandardMaterial3D.new()
	_leaf_pattern_material.vertex_color_use_as_albedo = true
	_leaf_pattern_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leaf_pattern_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_pattern_material.roughness = 1.0
	return _leaf_pattern_material


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
		and _has_grass_cover(neighbor)
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
		if not _has_grass_cover(cell):
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
	# Fewer, wider segments make the lower turf edge read as torn clumps
	# instead of a finely tessellated wave.
	const EDGE_SEGMENTS := 6
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
	overhang.material_override = _grass_cliff_overhang_material(
		cell.resolved_surface_cover()
	)
	var layer_order := (cell.position.x * 3 + cell.position.y * 5) % 11
	overhang.position = Vector3(
		cell.position.x,
		float(cell.height) + SURFACE_COVER_OFFSET + 0.002
			+ float(layer_order) * 0.00015,
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
	# Lay the fringe directly over the physical block side. A tiny outward
	# offset prevents z-fighting with the dirt face without making the grass
	# look like a separate floating shell.
	const SIDE_SURFACE_OFFSET := 0.003
	for segment in segments:
		var t0 := float(segment) / float(segments)
		var t1 := float(segment + 1) / float(segments)
		var upper_0 := start + tangent * t0 + outward * SIDE_SURFACE_OFFSET
		var upper_1 := start + tangent * t1 + outward * SIDE_SURFACE_OFFSET
		var lower_0 := upper_0 - Vector3.UP * _grass_overhang_drop(
			cell.position, edge_index, segment, segments
		)
		var lower_1 := upper_1 - Vector3.UP * _grass_overhang_drop(
			cell.position, edge_index, segment + 1, segments
		)
		_append_grass_overhang_side_triangle(
			vertices, normals, uvs, upper_0, lower_1, upper_1, outward
		)
		_append_grass_overhang_side_triangle(
			vertices, normals, uvs, upper_0, lower_0, lower_1, outward
		)


func _grass_overhang_drop(
	position: Vector2i,
	edge_index: int,
	sample_index: int,
	segments: int
) -> float:
	# Keep edge endpoints level so adjacent corner skirts meet without cracks,
	# while the samples between them form a subtly uneven turf fringe.
	if sample_index == 0 or sample_index == segments:
		return grass_cliff_overhang_drop
	var seed := float(
		position.x * 19349663
		+ position.y * 83492791
		+ edge_index * 26544357
		+ sample_index * 73856093
	)
	var variation := fposmod(sin(seed) * 43758.5453, 1.0)
	return grass_cliff_overhang_drop * lerpf(0.65, 1.30, variation)


func _append_grass_overhang_side_triangle(
	vertices: Array[Vector3],
	normals: Array[Vector3],
	uvs: Array[Vector2],
	a: Vector3,
	b: Vector3,
	c: Vector3,
	outward: Vector3
) -> void:
	# Godot treats clockwise triangles as front-facing. A cross product pointing
	# inward therefore exposes this face to a camera looking at the cliff.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for point in [a, b, c]:
		vertices.append(point)
		normals.append(outward)
		# The solid grass material ignores UVs, but retaining stable coordinates
		# keeps this mesh ready for a textured turf-side material later.
		uvs.append(Vector2(point.x + point.z, -point.y))


func _grass_cliff_overhang_material(cover_kind: String) -> StandardMaterial3D:
	return _solid_grass_cover_surface_material(cover_kind)


func _create_top(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var base_terrain := _base_terrain(cell)
	var scene := visual_theme.top_scene_for(base_terrain) if visual_theme else null
	var top := _instantiate(scene)
	if top:
		var surface_y := float(cell.height)
		if base_terrain in ["water", "lava"]:
			surface_y += fluid_surface_fill_offset
		top.position = Vector3(grid_pos.x + 0.5, surface_y, grid_pos.y + 0.5)
		add_to_layer(top, WATER_LAYER if base_terrain in ["water", "lava"] else TOP_LAYER)
	else:
		_create_fallback_top(grid_pos, cell, base_terrain)
	if _has_grass_cover(cell):
		_create_grass_surface_cover(cell)
	elif _has_stone_floor_cover(cell):
		_create_stone_floor_cover(cell)


func _create_grass_surface_cover(cell: MapCellVisualData) -> void:
	var cover := MeshInstance3D.new()
	var cover_kind := cell.resolved_surface_cover()
	cover.name = "%sCover_%d_%d" % [
		"DarkGrass" if cover_kind == "grass_dark" else "Grass",
		cell.position.x,
		cell.position.y,
	]
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.material = _solid_grass_cover_surface_material(cover_kind)
	cover.mesh = plane
	cover.position = Vector3(
		cell.position.x + 0.5,
		float(cell.height) + SURFACE_COVER_OFFSET,
		cell.position.y + 0.5
	)
	cover.set_meta(
		"terrain_asset_name",
		"terrain_grass_dark_cover" if cover_kind == "grass_dark" else "terrain_grass_top_01.glb"
	)
	cover.set_meta("surface_cover", cover_kind)
	cover.set_meta("grass_dirt_boundary_flags", _grass_dirt_boundary_flags(cell))
	add_to_layer(cover, TOP_LAYER)


func _solid_grass_cover_surface_material(
	cover_kind := "grass"
) -> StandardMaterial3D:
	if cover_kind == "grass_dark":
		if _solid_dark_grass_cover_material:
			return _solid_dark_grass_cover_material
		_solid_dark_grass_cover_material = StandardMaterial3D.new()
		_solid_dark_grass_cover_material.albedo_color = DARK_GRASS_COVER_SOLID_COLOR
		_solid_dark_grass_cover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_solid_dark_grass_cover_material.roughness = 0.92
		return _solid_dark_grass_cover_material
	if _solid_grass_cover_material:
		return _solid_grass_cover_material
	_solid_grass_cover_material = StandardMaterial3D.new()
	_solid_grass_cover_material.albedo_color = GRASS_COVER_SOLID_COLOR
	_solid_grass_cover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_solid_grass_cover_material.roughness = 0.92
	return _solid_grass_cover_material


func _create_stone_floor_cover(cell: MapCellVisualData) -> void:
	var cover_kind := cell.resolved_surface_cover()
	# A backing plane sits beneath four separate slabs. At a grass boundary it
	# uses the neighboring grass color, so missing stones never expose pink grout.
	var grout := MeshInstance3D.new()
	grout.name = "StoneFloorGrout_%d_%d" % [cell.position.x, cell.position.y]
	var grout_plane := PlaneMesh.new()
	grout_plane.size = Vector2.ONE
	var boundary_grass_kind := _stone_floor_boundary_grass_kind(cell)
	if boundary_grass_kind.is_empty():
		grout_plane.material = _stone_floor_line_surface_material()
	else:
		grout_plane.material = _solid_grass_cover_surface_material(
			boundary_grass_kind
		)
	grout.mesh = grout_plane
	grout.position = Vector3(
		cell.position.x + 0.5,
		float(cell.height) + SURFACE_COVER_OFFSET,
		cell.position.y + 0.5
	)
	grout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_to_layer(grout, TOP_LAYER)

	var slabs := MeshInstance3D.new()
	slabs.name = "StoneFloorSlabs_%d_%d" % [cell.position.x, cell.position.y]
	slabs.mesh = _build_four_stone_slab_mesh(cell)
	slabs.material_override = _leaf_pattern_surface_material()
	slabs.position = grout.position + Vector3(0.0, 0.002, 0.0)
	slabs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slabs.set_meta(
		"terrain_asset_name",
		"terrain_stone_floor_worn_cover"
		if cover_kind == "stone_floor_worn"
		else "terrain_stone_floor_cover"
	)
	slabs.set_meta("surface_cover", cover_kind)
	add_to_layer(slabs, TOP_LAYER)
	if _has_worn_stone_floor_cover(cell):
		_create_stone_floor_seam_grass(cell)
		_create_stone_floor_damage(cell)


func _build_four_stone_slab_mesh(cell: MapCellVisualData) -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var colors: Array[Color] = []
	var indices: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.position.x * 73856093 + cell.position.y * 19349663 + 97003
	var boundary_flags := _stone_floor_grass_boundary_flags(cell)
	const OUTER_EDGE := 0.49
	const HALF_GAP := 0.018
	var rectangles := [
		Rect2(Vector2(-OUTER_EDGE, -OUTER_EDGE), Vector2(OUTER_EDGE - HALF_GAP, OUTER_EDGE - HALF_GAP)),
		Rect2(Vector2(HALF_GAP, -OUTER_EDGE), Vector2(OUTER_EDGE - HALF_GAP, OUTER_EDGE - HALF_GAP)),
		Rect2(Vector2(-OUTER_EDGE, HALF_GAP), Vector2(OUTER_EDGE - HALF_GAP, OUTER_EDGE - HALF_GAP)),
		Rect2(Vector2(HALF_GAP, HALF_GAP), Vector2(OUTER_EDGE - HALF_GAP, OUTER_EDGE - HALF_GAP)),
	]
	var emitted_slab_count := 0
	for slab_index in rectangles.size():
		var rectangle: Rect2 = rectangles[slab_index]
		var min_point := rectangle.position
		var max_point := rectangle.position + rectangle.size
		var touches_boundary := (
			(bool(boundary_flags.n) and slab_index in [0, 1])
			or (bool(boundary_flags.s) and slab_index in [2, 3])
			or (bool(boundary_flags.w) and slab_index in [0, 2])
			or (bool(boundary_flags.e) and slab_index in [1, 3])
		)
		# A small, occasional edge slab loss keeps the paving from reading as
		# perfectly machine-cut, but stays rare - the reference keeps its
		# tile grid intact right up to the grass, with the transition
		# carried by grass clumps overlaid on top rather than missing tiles.
		var dropout_chance := rng.randf_range(0.03, 0.12)
		if (
			touches_boundary
			and rng.randf() < dropout_chance
			and not (slab_index == rectangles.size() - 1 and emitted_slab_count == 0)
		):
			continue
		# Boundary slabs recede by a small amount, enough to read as worn
		# corners without breaking up the regular grid.
		if bool(boundary_flags.n) and slab_index in [0, 1]:
			min_point.y += rng.randf_range(0.02, 0.08)
		if bool(boundary_flags.s) and slab_index in [2, 3]:
			max_point.y -= rng.randf_range(0.02, 0.08)
		if bool(boundary_flags.w) and slab_index in [0, 2]:
			min_point.x += rng.randf_range(0.02, 0.08)
		if bool(boundary_flags.e) and slab_index in [1, 3]:
			max_point.x -= rng.randf_range(0.02, 0.08)
		if (
			touches_boundary
			and rng.randf() < 0.35
		):
			min_point += Vector2(
				rng.randf_range(0.0, 0.04),
				rng.randf_range(0.0, 0.04)
			)
			max_point -= Vector2(
				rng.randf_range(0.0, 0.04),
				rng.randf_range(0.0, 0.04)
			)
		# Give each surviving boundary stone its own width and depth. The center
		# also drifts slightly so large and tiny remnants do not form a regular row.
		if touches_boundary:
			var slab_center := (min_point + max_point) * 0.5
			var slab_half_size := (max_point - min_point) * 0.5
			slab_half_size *= Vector2(
				rng.randf_range(0.78, 1.0),
				rng.randf_range(0.72, 1.0)
			)
			slab_center += Vector2(
				rng.randf_range(-0.02, 0.02),
				rng.randf_range(-0.02, 0.02)
			)
			min_point = slab_center - slab_half_size
			max_point = slab_center + slab_half_size
		var slab_points := [
			min_point,
			Vector2(max_point.x, min_point.y),
			max_point,
			Vector2(min_point.x, max_point.y),
		]
		var corner_jitter_x := minf(0.19, (max_point.x - min_point.x) * 0.46)
		var corner_jitter_y := minf(0.19, (max_point.y - min_point.y) * 0.46)
		# Move the two corners on a grass-facing side independently. This keeps
		# the four-slab layout but avoids repeating straight, equally deep cuts.
		if bool(boundary_flags.n) and slab_index in [0, 1]:
			slab_points[0].y += rng.randf_range(0.0, corner_jitter_y)
			slab_points[1].y += rng.randf_range(0.0, corner_jitter_y)
		if bool(boundary_flags.s) and slab_index in [2, 3]:
			slab_points[2].y -= rng.randf_range(0.0, corner_jitter_y)
			slab_points[3].y -= rng.randf_range(0.0, corner_jitter_y)
		if bool(boundary_flags.w) and slab_index in [0, 2]:
			slab_points[0].x += rng.randf_range(0.0, corner_jitter_x)
			slab_points[3].x += rng.randf_range(0.0, corner_jitter_x)
		if bool(boundary_flags.e) and slab_index in [1, 3]:
			slab_points[1].x -= rng.randf_range(0.0, corner_jitter_x)
			slab_points[2].x -= rng.randf_range(0.0, corner_jitter_x)
		var base_index := vertices.size()
		var color := STONE_FRAGMENT_COLORS[
			rng.randi_range(0, STONE_FRAGMENT_COLORS.size() - 1)
		]
		for point: Vector2 in slab_points:
			vertices.append(Vector3(point.x, 0.0, point.y))
			colors.append(color)
		indices.append_array([
			base_index, base_index + 2, base_index + 1,
			base_index, base_index + 3, base_index + 2,
		])
		emitted_slab_count += 1
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _stone_floor_grass_boundary_flags(cell: MapCellVisualData) -> Dictionary:
	var result := {"n": false, "e": false, "s": false, "w": false}
	for edge_index in DIRECTIONS.size():
		var direction: Dictionary = DIRECTIONS[edge_index]
		var neighbor_position: Vector2i = cell.position + direction.offset
		if not map_data.is_in_bounds(neighbor_position):
			continue
		var neighbor := map_data.get_cell(neighbor_position)
		if (
			neighbor != null
			and neighbor.height == cell.height
			and _has_grass_cover(neighbor)
		):
			result[["n", "e", "s", "w"][edge_index]] = true
	return result


func _stone_floor_boundary_grass_kind(cell: MapCellVisualData) -> String:
	var found_regular_grass := false
	for direction: Dictionary in DIRECTIONS:
		var neighbor_position: Vector2i = cell.position + direction.offset
		if not map_data.is_in_bounds(neighbor_position):
			continue
		var neighbor := map_data.get_cell(neighbor_position)
		if neighbor == null or neighbor.height != cell.height:
			continue
		var cover_kind := neighbor.resolved_surface_cover()
		if cover_kind == "grass_dark":
			return "grass_dark"
		if cover_kind == "grass":
			found_regular_grass = true
	return "grass" if found_regular_grass else ""


func _create_stone_floor_seam_grass(cell: MapCellVisualData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.position.x * 92837111 + cell.position.y * 689287499 + 54163
	if rng.randf() >= stone_floor_seam_grass_chance:
		return
	var cluster_count := rng.randi_range(1, 3)
	for cluster_index in cluster_count:
		var grass_marks := MeshInstance3D.new()
		grass_marks.name = "StoneSeamGrass_%d_%d_%d" % [
			cell.position.x, cell.position.y, cluster_index
		]
		grass_marks.mesh = _build_leaf_pattern_mesh(
			rng,
			rng.randf_range(0.08, 0.14),
			STONE_EDGE_GRASS_COLORS
		)
		var use_vertical_seam := rng.randf() < 0.5
		var local_position := Vector2.ZERO
		if use_vertical_seam:
			local_position.y = rng.randf_range(-0.36, 0.36)
		else:
			local_position.x = rng.randf_range(-0.36, 0.36)
		grass_marks.position = Vector3(
			cell.position.x + 0.5 + local_position.x,
			float(cell.height) + SURFACE_COVER_OFFSET + 0.006,
			cell.position.y + 0.5 + local_position.y
		)
		grass_marks.material_override = _leaf_pattern_surface_material()
		grass_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass_marks.set_meta("stone_floor_seam_grass", true)
		add_to_layer(grass_marks, TOP_LAYER)


func _create_stone_floor_damage(cell: MapCellVisualData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.position.x * 19349663 + cell.position.y * 83492791 + 73129
	if rng.randf() >= stone_floor_damage_chance:
		return
	var boundary_grass_kind := _stone_floor_boundary_grass_kind(cell)
	var damage_palette: Array[Color] = (
		DARK_GRASS_STONE_CHIP_COLORS
		if boundary_grass_kind == "grass_dark"
		else GRASS_STONE_CHIP_COLORS
	)
	var damage_count := 2 if rng.randf() < 0.24 else 1
	for damage_index in damage_count:
		var local_position := Vector2(
			rng.randf_range(-0.38, 0.38),
			rng.randf_range(-0.38, 0.38)
		)
		# Most missing pieces touch a grout seam, making the green area look as
		# though grass has pushed up between paving stones.
		if rng.randf() < 0.72:
			if rng.randf() < 0.5:
				local_position.x = rng.randf_range(-0.035, 0.035)
			else:
				local_position.y = rng.randf_range(-0.035, 0.035)
		var damage_size := (
			rng.randf_range(0.28, 0.42)
			if rng.randf() < 0.20
			else rng.randf_range(0.11, 0.28)
		)
		var damage := MeshInstance3D.new()
		damage.name = "StoneFloorDamage_%d_%d_%d" % [
			cell.position.x, cell.position.y, damage_index
		]
		damage.mesh = _build_stone_fragment_mesh(rng, damage_size, damage_palette)
		damage.position = Vector3(
			cell.position.x + 0.5 + local_position.x,
			float(cell.height) + SURFACE_COVER_OFFSET + 0.011,
			cell.position.y + 0.5 + local_position.y
		)
		damage.material_override = _leaf_pattern_surface_material()
		damage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		damage.set_meta("stone_floor_missing_piece", true)
		add_to_layer(damage, TOP_LAYER)

		if rng.randf() < 0.68:
			var grass_marks := MeshInstance3D.new()
			grass_marks.name = "StoneDamageGrass_%d_%d_%d" % [
				cell.position.x, cell.position.y, damage_index
			]
			grass_marks.mesh = _build_leaf_pattern_mesh(
				rng,
				rng.randf_range(0.07, 0.13),
				STONE_EDGE_GRASS_COLORS
			)
			grass_marks.position = damage.position + Vector3(
				rng.randf_range(-0.06, 0.06),
				0.002,
				rng.randf_range(-0.06, 0.06)
			)
			grass_marks.material_override = _leaf_pattern_surface_material()
			grass_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			grass_marks.set_meta("stone_floor_damage_grass", true)
			add_to_layer(grass_marks, TOP_LAYER)


func _create_stone_floor_lines(
	cell: MapCellVisualData,
	cover_size: Vector2,
	surface_height: float
) -> void:
	var vertices: Array[Vector3] = []
	var indices: Array[int] = []
	var half_size := cover_size * 0.5
	var line_width := minf(cover_size.x, cover_size.y) * 0.018
	_append_floor_line(
		vertices, indices,
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		line_width
	)
	_append_floor_line(
		vertices, indices,
		Vector2(-half_size.x, -half_size.y),
		Vector2(-half_size.x, half_size.y),
		line_width
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.position.x * 73856093 + cell.position.y * 19349663 + 46021
	if rng.randf() < 0.42:
		var crack_start := Vector2(
			rng.randf_range(-half_size.x * 0.32, half_size.x * 0.32),
			rng.randf_range(-half_size.y * 0.32, half_size.y * 0.32)
		)
		var crack_angle := rng.randf_range(0.0, TAU)
		var crack_length := minf(cover_size.x, cover_size.y) * rng.randf_range(0.12, 0.26)
		_append_floor_line(
			vertices, indices,
			crack_start,
			crack_start + Vector2(cos(crack_angle), sin(crack_angle)) * crack_length,
			line_width * 0.72
		)
	if vertices.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var lines := MeshInstance3D.new()
	lines.name = "StoneFloorLines_%d_%d" % [cell.position.x, cell.position.y]
	lines.mesh = mesh
	lines.material_override = _stone_floor_line_surface_material()
	lines.position = Vector3(
		cell.position.x + 0.5,
		surface_height + SURFACE_COVER_OFFSET + 0.003,
		cell.position.y + 0.5
	)
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_to_layer(lines, TOP_LAYER)


func _append_floor_line(
	vertices: Array[Vector3],
	indices: Array[int],
	start: Vector2,
	end: Vector2,
	width: float
) -> void:
	var delta := end - start
	if delta.length_squared() <= 0.000001:
		return
	var side := Vector2(-delta.y, delta.x).normalized() * width * 0.5
	var base_index := vertices.size()
	for point: Vector2 in [start + side, end + side, end - side, start - side]:
		vertices.append(Vector3(point.x, 0.0, point.y))
	indices.append_array([
		base_index, base_index + 2, base_index + 1,
		base_index, base_index + 3, base_index + 2,
	])


func _solid_stone_floor_surface_material() -> StandardMaterial3D:
	if _solid_stone_floor_material:
		return _solid_stone_floor_material
	_solid_stone_floor_material = StandardMaterial3D.new()
	_solid_stone_floor_material.albedo_color = STONE_FLOOR_SOLID_COLOR
	_solid_stone_floor_material.roughness = 0.94
	return _solid_stone_floor_material


func _stone_floor_line_surface_material() -> StandardMaterial3D:
	if _stone_floor_line_material:
		return _stone_floor_line_material
	_stone_floor_line_material = StandardMaterial3D.new()
	_stone_floor_line_material.albedo_color = STONE_FLOOR_LINE_COLOR
	_stone_floor_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stone_floor_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stone_floor_line_material.roughness = 1.0
	return _stone_floor_line_material


func _uses_micro_height_profile(cell: MapCellVisualData) -> bool:
	return (
		cell.has_micro_height_profile()
		and (
			_base_terrain(cell) in MICRO_HEIGHT_TERRAINS
			or _base_terrain(cell) in SELECTABLE_BLOCK_TERRAINS
		)
	)


func _create_micro_height_top(cell: MapCellVisualData) -> void:
	var base_height := float(cell.height - 1)
	var material_terrain := _base_terrain(cell)
	var asset_name := _micro_terrain_asset_name(material_terrain)
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
			if _has_grass_cover(cell):
				_create_micro_grass_surface_cover(cell, sub_x, sub_z, surface_height)
			elif _has_stone_floor_cover(cell):
				_create_micro_stone_floor_cover(cell, sub_x, sub_z, surface_height)


func _create_micro_grass_surface_cover(
	cell: MapCellVisualData,
	sub_x: int,
	sub_z: int,
	surface_height: float
) -> void:
	var cover := MeshInstance3D.new()
	var cover_kind := cell.resolved_surface_cover()
	cover.name = "Micro%sCover_%d_%d_%d_%d" % [
		"DarkGrass" if cover_kind == "grass_dark" else "Grass",
		cell.position.x, cell.position.y, sub_x, sub_z
	]
	var plane := PlaneMesh.new()
	plane.size = Vector2(MICRO_CELL_SIZE, MICRO_CELL_SIZE)
	plane.material = _solid_grass_cover_surface_material(cover_kind)
	cover.mesh = plane
	cover.position = Vector3(
		cell.position.x + (float(sub_x) + 0.5) * MICRO_CELL_SIZE,
		surface_height + SURFACE_COVER_OFFSET,
		cell.position.y + (float(sub_z) + 0.5) * MICRO_CELL_SIZE
	)
	cover.set_meta(
		"terrain_asset_name",
		"terrain_grass_dark_cover" if cover_kind == "grass_dark" else "terrain_grass_top_01.glb"
	)
	cover.set_meta("surface_cover", cover_kind)
	cover.set_meta("micro_height_stage", cell.micro_height_at(sub_x, sub_z))
	add_to_layer(cover, TOP_LAYER)


func _create_micro_stone_floor_cover(
	cell: MapCellVisualData,
	sub_x: int,
	sub_z: int,
	surface_height: float
) -> void:
	var cover_kind := cell.resolved_surface_cover()
	var cover := MeshInstance3D.new()
	cover.name = "Micro%sStoneFloorCover_%d_%d_%d_%d" % [
		"Worn" if cover_kind == "stone_floor_worn" else "",
		cell.position.x, cell.position.y, sub_x, sub_z
	]
	var plane := PlaneMesh.new()
	plane.size = Vector2(MICRO_CELL_SIZE, MICRO_CELL_SIZE)
	plane.material = _solid_stone_floor_surface_material()
	cover.mesh = plane
	cover.position = Vector3(
		cell.position.x + (float(sub_x) + 0.5) * MICRO_CELL_SIZE,
		surface_height + SURFACE_COVER_OFFSET,
		cell.position.y + (float(sub_z) + 0.5) * MICRO_CELL_SIZE
	)
	cover.set_meta(
		"terrain_asset_name",
		"terrain_stone_floor_worn_cover"
		if cover_kind == "stone_floor_worn"
		else "terrain_stone_floor_cover"
	)
	cover.set_meta("surface_cover", cover_kind)
	cover.set_meta("micro_height_stage", cell.micro_height_at(sub_x, sub_z))
	add_to_layer(cover, TOP_LAYER)


func _micro_terrain_asset_name(terrain: String) -> String:
	if terrain in ["stone", "stone_road", "rock", "wall"]:
		return "terrain_stone_top_01.glb"
	if terrain in SELECTABLE_BLOCK_TERRAINS:
		return "stone_brick.glb"
	return "terrain_dirt_top_01.glb"

func _create_cliff_sides(cell: MapCellVisualData) -> void:
	var grid_pos := cell.position
	var base_terrain := _base_terrain(cell)
	var is_water := base_terrain == "water"
	var is_lava := base_terrain == "lava"
	var is_fluid := is_water or is_lava
	if is_fluid and fluid_surface_fill_offset > SURFACE_OFFSET:
		_create_fluid_fill_sides(cell)
	var full_block_terrain := base_terrain in [
		"dirt", "forest", "stone", "stone_road", "rock", "wall"
	] or base_terrain in SELECTABLE_BLOCK_TERRAINS
	var has_full_top_block := (
		full_block_terrain
		and visual_theme != null
		and visual_theme.top_scene_for(base_terrain) != null
	)
	for direction: Dictionary in DIRECTIONS:
		var neighbor_pos: Vector2i = grid_pos + direction.offset
		var neighbor := map_data.get_cell(neighbor_pos) if map_data.is_in_bounds(neighbor_pos) else null
		var neighbor_height: int = neighbor.height if neighbor else 0
		var levels_needed := cell.height - neighbor_height
		var is_stone := (
			base_terrain in ["stone", "stone_road", "rock", "wall"]
			or base_terrain in SELECTABLE_BLOCK_TERRAINS
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
			if not side: side = _make_fallback_cliff(base_terrain)
			if not is_fluid:
				# Preserve the physical block family across separately instanced
				# lower side panels. Surface covers never change cliff material.
				var side_block_key := "dirt"
				if (
					base_terrain in ["stone", "stone_road", "rock", "wall"]
					or base_terrain in SELECTABLE_BLOCK_TERRAINS
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

func _create_decoration(data: MapDecorationData, cell_height: int) -> void:
	var scene := visual_theme.decoration_scene_for(data.kind) if visual_theme else null
	var decoration := _instantiate(scene, not data.kind in ["grass_short", "grass_tall"])
	if not decoration: decoration = _make_fallback_decoration(data.kind)
	decoration.position = Vector3(data.grid_position.x + 0.5, cell_height + data.height_offset, data.grid_position.y + 0.5)
	decoration.rotation_degrees.y = data.rotation_degrees
	decoration.scale = data.scale
	add_to_layer(decoration, PROP_LAYER)

func _create_random_grass(cell: MapCellVisualData) -> void:
	if not _has_grass_cover(cell) or not cell.props.is_empty():
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

func _create_fallback_top(
	grid_pos: Vector2i,
	cell: MapCellVisualData,
	base_terrain: String
) -> void:
	var part := MeshInstance3D.new()
	if base_terrain == "water":
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.98, 0.98)
		part.mesh = plane
	elif base_terrain == "stair":
		var stair_base := BoxMesh.new()
		stair_base.size = Vector3(0.96, 0.18, 0.96)
		part.mesh = stair_base
		# Grid height is the walkable surface, so geometry must extend downward.
		part.position.y = -stair_base.size.y * 0.5
	else:
		var tile := BoxMesh.new()
		tile.size = Vector3(0.96, 0.2 if base_terrain == "bridge" else 0.12, 0.96)
		part.mesh = tile
		part.position.y = -tile.size.y * 0.5
	part.material_override = _material_for(base_terrain)
	part.position += Vector3(grid_pos.x + 0.5, cell.height, grid_pos.y + 0.5)
	add_to_layer(part, WATER_LAYER if base_terrain == "water" else TOP_LAYER)
	if base_terrain == "stair": _add_stair_steps(grid_pos, cell.height)

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
