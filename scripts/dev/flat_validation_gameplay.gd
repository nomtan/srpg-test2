extends "res://scripts/dev/flat_validation.gd"

## Gameplay-oriented variant of the flat validation scene.
## Tactical data remains cell based, while the visual layer deliberately hides
## the square test-board silhouette and adds village-edge scenery.

const ROAD_X_BY_Z := [7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 12]


func _build_environment_and_camera() -> void:
	super()

	# Brighter, cleaner outdoor palette closer to the target pixel-art battle.
	params.background_color = Color("#86a963")
	params.fog_color = Color("#a9bf82")
	params.fog_density = 0.00025
	params.grass_texture_opacity = 0.17
	params.grass_texture_brightness = 0.92
	params.grass_hue_jitter = 0.018
	params.tall_grass_brightness = 0.86
	params.sat_jitter = 0.04
	params.val_jitter = 0.025
	params.grass_boundary_width = 0.30

	environment_resource.background_color = params.background_color
	environment_resource.fog_light_color = params.fog_color
	environment_resource.fog_density = params.fog_density
	environment_resource.adjustment_brightness = 1.05
	environment_resource.adjustment_contrast = 1.02
	environment_resource.adjustment_saturation = 0.94
	environment_resource.glow_intensity = 0.04

	# Crop the slab edges out of the gameplay frame. The target reads as a
	# continuous landscape, not a complete square diorama presented on a table.
	camera_controller.focus_offset = Vector3(22.0, 19.5, -28.0)
	camera_controller.focus_target = Vector3(9.2, 0.75, 7.0)
	var camera := camera_controller.get_viewport().get_camera_3d()
	if camera:
		camera.position = camera_controller.focus_target + camera_controller.focus_offset
		camera.size = 10.9
		camera.look_at_from_position(camera.position, camera_controller.focus_target, Vector3.UP)


func _build_terrain() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = VISUAL_THEME

	# Less uniform grass. Stronger edge overlays soften the route silhouette.
	renderer.grass_prop_chance = 0.17
	renderer.grass_prop_seed = 4171
	renderer.grass_transitions_enabled = true
	renderer.grass_transition_fringe_width = 0.32
	renderer.fluid_surface_fill_offset = 0.88
	renderer.painted_grass_overlays_enabled = true
	renderer.painted_grass_overlay_seed = 8123
	renderer.painted_grass_edge_fringe_width = 0.28
	add_child(renderer)

	validation_map = _create_validation_map()
	renderer.build_from_map_data(validation_map)
	_collect_terrain_materials(renderer)
	_add_gameplay_props()


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

	# Small irregular rear terrace. Avoid the former isolated rectangular block.
	for raised in [
		Vector2i(14, 0), Vector2i(15, 0),
		Vector2i(13, 1), Vector2i(14, 1), Vector2i(15, 1),
		Vector2i(14, 2), Vector2i(15, 2), Vector2i(16, 2),
		Vector2i(15, 3), Vector2i(16, 3),
	]:
		data.get_cell(raised).height = 2

	# Broad pale village road. Dirt is intentionally used as the warm paving
	# base because the current stone surface is charcoal and reads as holes.
	for z in MAP_DEPTH:
		var center_x: int = ROAD_X_BY_Z[z]
		var half_width := 2 if z in range(2, 12) else 1
		for x in range(center_x - half_width, center_x + half_width + 1):
			var position := Vector2i(x, z)
			if data.is_in_bounds(position):
				data.get_cell(position).terrain = "dirt"

	# Irregular shoulders and shallow bays make the route feel hand laid.
	for cutout in [
		Vector2i(6, 1), Vector2i(10, 2), Vector2i(6, 4), Vector2i(11, 5),
		Vector2i(7, 7), Vector2i(13, 8), Vector2i(8, 10), Vector2i(14, 11),
		Vector2i(10, 12),
	]:
		if data.is_in_bounds(cutout):
			data.get_cell(cutout).terrain = "grass"

	# Small worn-earth pockets around the road, not dark square paving inserts.
	for dirt_position in [
		Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4),
		Vector2i(13, 3), Vector2i(14, 3),
		Vector2i(2, 9), Vector2i(3, 9),
		Vector2i(14, 10), Vector2i(15, 10), Vector2i(15, 11),
	]:
		data.get_cell(dirt_position).terrain = "dirt"

	# Deliberate grass clusters: mostly shoulders and frame edges, with open
	# combat space around the unit and along the road center.
	for grass_data in [
		[Vector2i(1, 1), -18.0, Vector3(0.92, 1.02, 0.92)],
		[Vector2i(3, 2), 14.0, Vector3(0.84, 0.94, 0.84)],
		[Vector2i(2, 6), 28.0, Vector3(0.90, 1.00, 0.90)],
		[Vector2i(15, 4), -10.0, Vector3(0.88, 0.98, 0.88)],
		[Vector2i(15, 8), 22.0, Vector3(0.92, 1.02, 0.92)],
		[Vector2i(3, 11), -26.0, Vector3(0.94, 1.04, 0.94)],
		[Vector2i(16, 12), 8.0, Vector3(0.90, 1.00, 0.90)],
	]:
		_add_map_decoration(data, grass_data[0], "grass_tall", grass_data[1], grass_data[2])

	return data


func _add_gameplay_props() -> void:
	# Simple temporary scenery establishes the target composition before final
	# authored tree, fence, flower and crate assets replace these primitives.
	_add_tree(Vector3(2.1, 1.0, 10.7), 1.15)
	_add_tree(Vector3(15.7, 1.0, 2.1), 0.95)
	_add_tree(Vector3(16.4, 1.0, 10.8), 1.05)
	_add_crate_stack(Vector3(13.8, 1.0, 6.0))
	_add_fence_run(Vector3(14.7, 1.0, 7.3), 4)
	_add_flower_patch(Vector3(4.2, 1.02, 7.7))
	_add_flower_patch(Vector3(12.8, 1.02, 3.7))


func _add_tree(position: Vector3, scale_factor: float) -> void:
	var root := Node3D.new()
	root.position = position
	root.scale = Vector3.ONE * scale_factor
	root.name = "GameplayTree"
	add_child(root)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 1.65
	trunk.mesh = trunk_mesh
	trunk.position.y = 0.82
	trunk.material_override = _make_material(Color("#795234"))
	root.add_child(trunk)

	for crown_data in [
		[Vector3(0.0, 1.85, 0.0), 0.92],
		[Vector3(-0.42, 1.62, 0.10), 0.68],
		[Vector3(0.42, 1.66, -0.05), 0.72],
	]:
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = crown_data[1]
		crown_mesh.height = crown_data[1] * 1.75
		crown.mesh = crown_mesh
		crown.position = crown_data[0]
		crown.material_override = _make_material(Color("#4f823e"))
		root.add_child(crown)


func _add_crate_stack(position: Vector3) -> void:
	for crate_data in [
		[Vector3(0.0, 0.32, 0.0), 0.0],
		[Vector3(0.62, 0.32, 0.08), 8.0],
		[Vector3(0.22, 0.92, 0.02), -6.0],
	]:
		var crate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.58, 0.58, 0.58)
		crate.mesh = mesh
		crate.position = position + crate_data[0]
		crate.rotation_degrees.y = crate_data[1]
		crate.material_override = _make_material(Color("#a76f3f"))
		add_child(crate)


func _add_fence_run(position: Vector3, count: int) -> void:
	for index in count:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 0.82, 0.14)
		post.mesh = mesh
		post.position = position + Vector3(float(index) * 0.72, 0.41, 0.0)
		post.material_override = _make_material(Color("#8b623e"))
		add_child(post)
	for rail_y in [0.28, 0.62]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(float(count - 1) * 0.72 + 0.16, 0.10, 0.12)
		rail.mesh = rail_mesh
		rail.position = position + Vector3(float(count - 1) * 0.36, rail_y, 0.0)
		rail.material_override = _make_material(Color("#9a714b"))
		add_child(rail)


func _add_flower_patch(position: Vector3) -> void:
	for flower_data in [
		[Vector3(-0.22, 0.0, -0.12), Color("#fff1a8")],
		[Vector3(0.08, 0.0, 0.16), Color("#f4cde1")],
		[Vector3(0.28, 0.0, -0.08), Color("#ffffff")],
		[Vector3(-0.04, 0.0, -0.30), Color("#ffe580")],
	]:
		var flower := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.075
		mesh.height = 0.12
		flower.mesh = mesh
		flower.position = position + flower_data[0]
		flower.material_override = _make_material(flower_data[1])
		add_child(flower)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _build_ui() -> void:
	super()
	if ui_layer:
		ui_layer.visible = false
