extends Node3D

## Phase16-Step4: also doubles as the "見本市用マップ" showcase rig used to
## take comparable before/after screenshots while tuning palette/lighting.
## Uses the same Environment resource and the real game CameraController so
## screenshots taken here match what the battle scene actually looks like.

const BATTLE_ENVIRONMENT: Environment = preload("res://assets/environment/battle_atmosphere.tres")
const ScreenshotCaptureScript := preload("res://scripts/debug/screenshot_capture.gd")

@export var visual_theme: MapVisualTheme = preload("res://assets/terrain/theme_default.tres")


func _ready() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = visual_theme
	add_child(renderer)
	renderer.build_from_map_data(_create_preview_map())
	_create_measurement_guides()
	_create_lighting_and_camera()
	var screenshot := ScreenshotCaptureScript.new()
	screenshot.name = "ScreenshotCapture"
	add_child(screenshot)


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

			# Middle walkway column: dirt/water/lava so all five terrain
			# types are visible in one frame for palette review. Water and
			# lava stay at the same height as their neighbors (not sunk
			# into a pit next to a tall cliff) since that would sit in
			# the camera's blind spot.
			if x == 3 and z == 0:
				cell.terrain = "dirt"
			elif x == 3 and z == 1:
				cell.terrain = "water"
			elif x == 3 and z == 2:
				cell.terrain = "lava"

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
	environment_node.environment = BATTLE_ENVIRONMENT
	add_child(environment_node)

	# Keep in sync with Main.tscn's DirectionalLight3D so this rig's
	# screenshots are representative of the actual battle scene.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	light.light_color = Color(1, 0.949, 0.839, 1)
	light.light_energy = 1.3
	light.shadow_enabled = false
	light.shadow_opacity = 0.35
	light.shadow_bias = 0.05
	add_child(light)

	# Real game camera (standard angle/zoom) instead of an ad-hoc preview
	# camera, so composition matches what players actually see.
	var camera_controller := CameraController.new()
	camera_controller.name = "CameraController"
	add_child(camera_controller)
	var camera := camera_controller.setup()
	camera.current = true

