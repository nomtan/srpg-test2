extends Node3D

@export var visual_theme: MapVisualTheme = preload("res://assets/map/themes/phase16_theme.tres")


func _ready() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = visual_theme
	add_child(renderer)
	renderer.build_from_map_data(_create_preview_map())
	_create_measurement_guides()
	_create_lighting_and_camera()


func _create_preview_map() -> MapData:
	var data := MapData.new()
	data.width = 7
	data.depth = 6
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"

			# Left: grass plateau, one-level cliff and water connection.
			if x <= 2 and z >= 3:
				cell.height = 2
			elif x <= 2 and z == 2:
				cell.height = 0
				cell.terrain = "water"

			# Right: stone floor with stairs connecting the one-level rise.
			if x >= 4:
				cell.terrain = "stone_road"
				cell.height = 2 if z >= 3 else 1
			if x == 5 and z == 3:
				cell.terrain = "stair"

			_add_preview_props(cell)
			data.cells.append(cell)
	data.rebuild_lookup()
	return data


func _add_preview_props(cell: MapCellVisualData) -> void:
	var kind := ""
	if cell.position == Vector2i(1, 4): kind = "grass_patch"
	elif cell.position == Vector2i(5, 4): kind = "broken_stone"
	if kind.is_empty(): return
	var prop := MapDecorationData.new()
	prop.kind = kind
	prop.grid_position = cell.position
	cell.props.append(prop)


func _create_measurement_guides() -> void:
	var guides := Node3D.new()
	guides.name = "MeasurementGuides_1m"
	add_child(guides)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ffcc33")
	material.emission_enabled = true
	material.emission = Color("#8a5f00")
	for edge_data: Dictionary in [
		{"position": Vector3(0.5, 0.025, 0.02), "size": Vector3(1.0, 0.05, 0.04)},
		{"position": Vector3(0.5, 0.025, 0.98), "size": Vector3(1.0, 0.05, 0.04)},
		{"position": Vector3(0.02, 0.025, 0.5), "size": Vector3(0.04, 0.05, 1.0)},
		{"position": Vector3(0.98, 0.025, 0.5), "size": Vector3(0.04, 0.05, 1.0)},
		{"position": Vector3(0.02, 0.5, 0.02), "size": Vector3(0.04, 1.0, 0.04)},
	]:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = edge_data.size
		marker.mesh = box
		marker.position = edge_data.position
		marker.material_override = material
		guides.add_child(marker)


func _create_lighting_and_camera() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b7c1c7")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dce5e8")
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	light.light_energy = 1.2
	add_child(light)

	var camera := Camera3D.new()
	camera.position = Vector3(10.5, 9.0, 11.5)
	camera.look_at_from_position(camera.position, Vector3(3.5, 0.9, 3.0))
	camera.current = true
	add_child(camera)

