extends Node3D


func _ready() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	add_child(renderer)
	renderer.build_from_map_data(_create_sample_map())
	_create_lighting()
	_create_camera()


func _create_sample_map() -> MapData:
	var data := MapData.new()
	data.width = 8
	data.depth = 8
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.terrain = "grass"
			cell.height = 1
			if z == 4:
				cell.terrain = "bridge" if x in [3, 4] else "water"
				cell.height = 1 if cell.terrain == "bridge" else 0
			elif z >= 5:
				cell.height = 2
				cell.terrain = "stone_road" if x in [2, 3, 4, 5] else "grass"
			elif z == 2 and x in [1, 2, 3, 4, 5, 6]:
				cell.terrain = "stone_road"
			elif z == 3 and x in [0, 1]:
				cell.terrain = "dirt"
			if z == 5 and x in [3, 4]:
				cell.terrain = "stair"
			_add_sample_prop(cell)
			data.cells.append(cell)
	data.rebuild_lookup()
	return data


func _add_sample_prop(cell: MapCellVisualData) -> void:
	var kind := ""
	if cell.position in [Vector2i(1, 1), Vector2i(6, 6)]: kind = "grass_patch"
	elif cell.position == Vector2i(2, 6): kind = "broken_stone"
	elif cell.position == Vector2i(6, 2): kind = "flag_placeholder"
	if kind.is_empty(): return
	var prop := MapDecorationData.new()
	prop.kind = kind
	prop.grid_position = cell.position
	prop.rotation_degrees = float((cell.position.x * 37 + cell.position.y * 19) % 360)
	cell.props.append(prop)


func _create_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.shadow_enabled = true
	light.light_energy = 1.2
	add_child(light)


func _create_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(11.0, 10.0, 13.0)
	camera.look_at_from_position(camera.position, Vector3(4.0, 0.8, 4.0))
	camera.current = true
	add_child(camera)
