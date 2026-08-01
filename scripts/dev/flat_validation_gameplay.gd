extends "res://scripts/dev/flat_validation.gd"

## Gameplay-oriented variant of the flat validation scene.
## The tactical grid stays cell-based while presentation hides the tile test UI
## and frames the terrain like an in-game SRPG battlefield.

const ROAD_X_BY_Z := [7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 12]


func _build_environment_and_camera() -> void:
	super()

	# Muted natural greens avoid the fluorescent look seen in the first capture.
	params.background_color = Color("#718263")
	params.fog_color = Color("#91a47a")
	params.fog_density = 0.00045
	params.grass_texture_opacity = 0.22
	params.grass_texture_brightness = 0.82
	params.grass_hue_jitter = 0.025
	params.tall_grass_brightness = 0.92
	params.sat_jitter = 0.055
	params.val_jitter = 0.035
	params.grass_boundary_width = 0.24

	environment_resource.background_color = params.background_color
	environment_resource.fog_light_color = params.fog_color
	environment_resource.fog_density = params.fog_density
	environment_resource.adjustment_brightness = 0.98
	environment_resource.adjustment_contrast = 1.04
	environment_resource.adjustment_saturation = 0.86
	environment_resource.glow_intensity = 0.08

	# Move closer so the outer slab leaves the frame and the map reads as a
	# continuous battlefield rather than a floating square diorama.
	camera_controller.focus_offset = Vector3(24.0, 21.0, -30.0)
	camera_controller.focus_target = Vector3(8.8, 0.75, 7.1)
	var camera := camera_controller.get_viewport().get_camera_3d()
	if camera:
		camera.position = camera_controller.focus_target + camera_controller.focus_offset
		camera.size = 12.8
		camera.look_at_from_position(camera.position, camera_controller.focus_target, Vector3.UP)


func _build_terrain() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = VISUAL_THEME

	# Keep decoration concentrated enough to break repetition without covering
	# movement space. Boundary overlays soften grass-to-path silhouettes.
	renderer.grass_prop_chance = 0.235
	renderer.grass_prop_seed = 4171
	renderer.grass_transitions_enabled = true
	renderer.grass_transition_fringe_width = 0.28
	renderer.fluid_surface_fill_offset = 0.88
	renderer.painted_grass_overlays_enabled = true
	renderer.painted_grass_overlay_seed = 8123
	renderer.painted_grass_edge_fringe_width = 0.24
	add_child(renderer)

	validation_map = _create_validation_map()
	renderer.build_from_map_data(validation_map)
	_collect_terrain_materials(renderer)


func _create_validation_map() -> MapData:
	var data := MapData.new()
	data.width = MAP_WIDTH
	data.depth = MAP_DEPTH

	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"
			data.cells.append(cell)
	data.rebuild_lookup()

	# A small irregular rear terrace gives depth without becoming a large box.
	for raised in [
		Vector2i(13, 0), Vector2i(14, 0), Vector2i(15, 0),
		Vector2i(14, 1), Vector2i(15, 1), Vector2i(16, 1),
		Vector2i(15, 2), Vector2i(16, 2),
	]:
		data.get_cell(raised).height = 2

	# Use the warm dirt surface as the pale worn road. The previous stone road
	# was nearly black and dominated the whole composition.
	for z in MAP_DEPTH:
		var center_x: int = ROAD_X_BY_Z[z]
		var half_width := 2 if z in range(3, 11) else 1
		for x in range(center_x - half_width, center_x + half_width + 1):
			var position := Vector2i(x, z)
			if data.is_in_bounds(position):
				data.get_cell(position).terrain = "dirt"

	# Bite into the path edges so it resembles an old village road rather than
	# a rectangular tactical overlay.
	for cutout in [
		Vector2i(6, 1), Vector2i(9, 3), Vector2i(6, 5), Vector2i(11, 6),
		Vector2i(7, 8), Vector2i(13, 9), Vector2i(9, 11), Vector2i(13, 12),
	]:
		if data.is_in_bounds(cutout):
			data.get_cell(cutout).terrain = "grass"

	# A few darker stones suggest broken paving without returning to a black
	# continuous road surface.
	for stone_position in [
		Vector2i(8, 3), Vector2i(10, 5), Vector2i(8, 7),
		Vector2i(11, 8), Vector2i(10, 10), Vector2i(12, 11),
	]:
		data.get_cell(stone_position).terrain = "stone"

	# Grass clusters favor the perimeter and road shoulders, leaving the center
	# readable for units and combat effects.
	for grass_data in [
		[Vector2i(1, 1), -18.0, Vector3(1.05, 1.12, 1.05)],
		[Vector2i(3, 2), 14.0, Vector3(0.92, 1.04, 0.92)],
		[Vector2i(2, 6), 28.0, Vector3(1.00, 1.10, 1.00)],
		[Vector2i(15, 4), -10.0, Vector3(0.96, 1.08, 0.96)],
		[Vector2i(15, 8), 22.0, Vector3(1.02, 1.12, 1.02)],
		[Vector2i(3, 11), -26.0, Vector3(1.04, 1.14, 1.04)],
		[Vector2i(16, 12), 8.0, Vector3(0.98, 1.08, 0.98)],
	]:
		_add_map_decoration(data, grass_data[0], "grass_tall", grass_data[1], grass_data[2])

	return data


func _build_ui() -> void:
	super()
	# This scene now defaults to a clean gameplay preview. The inherited tuning
	# controls remain in code and can be re-enabled here while authoring.
	if ui_layer:
		ui_layer.visible = false
