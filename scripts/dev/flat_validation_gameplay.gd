extends "res://scripts/dev/flat_validation.gd"

## Gameplay-oriented variant of the flat validation scene.
## Keeps the original material tuning UI and A/B controls, but replaces the
## technical tile gallery with a readable grassy battlefield composition.

const ROAD_X_BY_Z := [8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12]


func _build_environment_and_camera() -> void:
	super()

	# Match the bright, warm outdoor presentation of the target screenshot.
	params.background_color = Color("#8ebd58")
	params.fog_color = Color("#9fbd79")
	params.fog_density = 0.0008
	environment_resource.background_color = params.background_color
	environment_resource.fog_light_color = params.fog_color
	environment_resource.fog_density = params.fog_density
	environment_resource.adjustment_brightness = 1.08
	environment_resource.adjustment_contrast = 1.02
	environment_resource.adjustment_saturation = 1.05

	# A broader orthographic frame gives the map the same "battlefield first"
	# composition as the reference while keeping units readable.
	camera_controller.focus_offset = Vector3(27.0, 24.0, -34.0)
	camera_controller.focus_target = Vector3(8.5, 1.0, 7.0)
	var camera := camera_controller.get_viewport().get_camera_3d()
	if camera:
		camera.position = camera_controller.focus_target + camera_controller.focus_offset
		camera.size = 16.5
		camera.look_at_from_position(camera.position, camera_controller.focus_target, Vector3.UP)


func _build_terrain() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = VISUAL_THEME

	# Break up repeated square tops with stable vegetation, painted grass and
	# organic grass/road boundaries. Tactical logic remains one cell per tile.
	renderer.grass_prop_chance = 0.325
	renderer.grass_prop_seed = 4171
	renderer.grass_transitions_enabled = true
	renderer.grass_transition_fringe_width = 0.24
	renderer.fluid_surface_fill_offset = 0.88
	renderer.painted_grass_overlays_enabled = true
	renderer.painted_grass_overlay_seed = 8123
	renderer.painted_grass_edge_fringe_width = 0.22
	add_child(renderer)

	validation_map = _create_validation_map()
	renderer.build_from_map_data(validation_map)
	_collect_terrain_materials(renderer)


func _create_validation_map() -> MapData:
	var data := MapData.new()
	data.width = MAP_WIDTH
	data.depth = MAP_DEPTH

	# Mostly flat grass keeps the scene readable like a production SRPG map.
	# Raised corners create a subtle diorama silhouette without turning every
	# cell into a visible stack of cubes.
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"
			if (x <= 2 and z >= 10) or (x >= 15 and z <= 2):
				cell.height = 2
			data.cells.append(cell)
	data.rebuild_lookup()

	# Irregular pale stone route crossing the center. Varying widths and small
	# missing corners prevent the road from reading as a rigid grid stripe.
	for z in MAP_DEPTH:
		var center_x: int = ROAD_X_BY_Z[z]
		var half_width := 2 if z in [4, 5, 6, 7, 8, 9] else 1
		for x in range(center_x - half_width, center_x + half_width + 1):
			if data.is_in_bounds(Vector2i(x, z)):
				data.get_cell(Vector2i(x, z)).terrain = "stone"

	for cutout in [
		Vector2i(7, 1), Vector2i(10, 4), Vector2i(7, 6),
		Vector2i(13, 9), Vector2i(10, 11), Vector2i(14, 12),
	]:
		if data.is_in_bounds(cutout):
			data.get_cell(cutout).terrain = "grass"

	# Earth patches near the road and map edges add the worn, hand-painted
	# variation visible in the target screenshot.
	for dirt_position in [
		Vector2i(4, 2), Vector2i(5, 2), Vector2i(4, 3),
		Vector2i(12, 3), Vector2i(13, 3), Vector2i(13, 4),
		Vector2i(3, 8), Vector2i(4, 8), Vector2i(4, 9),
		Vector2i(14, 10), Vector2i(15, 10), Vector2i(15, 11),
	]:
		data.get_cell(dirt_position).terrain = "dirt"

	# Deliberately placed clusters reinforce the frame without covering the
	# central combat area. Automatic short grass fills the quieter gaps.
	for grass_data in [
		[Vector2i(1, 1), -18.0, Vector3(1.20, 1.30, 1.20)],
		[Vector2i(2, 2), 14.0, Vector3(1.00, 1.16, 1.00)],
		[Vector2i(1, 5), 28.0, Vector3(1.12, 1.24, 1.12)],
		[Vector2i(16, 5), -10.0, Vector3(1.06, 1.18, 1.06)],
		[Vector2i(15, 8), 22.0, Vector3(1.16, 1.28, 1.16)],
		[Vector2i(2, 11), -26.0, Vector3(1.18, 1.32, 1.18)],
		[Vector2i(16, 12), 8.0, Vector3(1.10, 1.22, 1.10)],
	]:
		_add_map_decoration(data, grass_data[0], "grass_tall", grass_data[1], grass_data[2])

	return data
