extends Node3D

const BATTLE_ENVIRONMENT: Environment = preload("res://assets/environment/battle_atmosphere.tres")
const VISUAL_THEME: MapVisualTheme = preload("res://assets/terrain/theme_default.tres")
const CHARACTER_MODEL := "res://assets/characters/py/base_body.glb"
const CHARACTER_FACE_TEXTURE := "res://assets/characters/textures/anime_face_vain.png"

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_flat_grass_map()
	_spawn_character()
	var capture := ScreenshotCapture.new()
	add_child(capture)

func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.environment = BATTLE_ENVIRONMENT.duplicate()
	add_child(world_environment)

	var directional_light := DirectionalLight3D.new()
	directional_light.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	directional_light.light_color = Color(1.0, 0.949, 0.839)
	directional_light.light_energy = 1.3
	directional_light.shadow_enabled = false
	add_child(directional_light)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 54.0
	camera.position = Vector3(18.0, 28.0, -18.0)
	add_child(camera)
	camera.look_at(Vector3(18.0, 0.0, 14.0), Vector3.UP)
	camera.current = true

func _build_flat_grass_map() -> void:
	var data := MapData.new()
	data.width = 36
	data.depth = 28
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"
			# A broad crossing stone avenue previews the reference composition;
			# grass and dark grass occupy the surrounding patches.
			var dark_edge := 18 + roundi(sin(float(z) * 0.62) * 2.0)
			var is_stone_path := z in [12, 13, 14, 15, 16] or x in [16, 17, 18, 19, 20]
			if is_stone_path:
				cell.surface_cover = "stone_floor"
			else:
				cell.surface_cover = "grass_dark" if x >= dark_edge else "grass"
			data.cells.append(cell)
	data.rebuild_lookup()

	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = VISUAL_THEME
	renderer.grass_transitions_enabled = false
	renderer.painted_grass_overlays_enabled = true
	renderer.painted_grass_overlay_seed = 8123
	renderer.painted_grass_edge_fringe_width = 0.18
	add_child(renderer)
	renderer.build_from_map_data(data)

func _spawn_character() -> void:
	var unit := BattleUnit.new()
	unit.configure("vain_test", "Vain", Vector2i(18, 14), "player")
	unit.setup_visual(CHARACTER_MODEL, 1.02, -0.045, -90.0, true)
	unit.attach_face_texture(CHARACTER_FACE_TEXTURE)
	unit.position = Vector3(18.5, 1.0, 14.5)
	unit.face_toward(Vector2i(18, 13))
	if unit.status_bars:
		unit.status_bars.visible = false
	if unit.direction_marker:
		unit.direction_marker.visible = false
	add_child(unit)
