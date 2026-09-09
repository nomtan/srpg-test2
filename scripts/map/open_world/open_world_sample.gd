extends Node3D
## Independent finite open-world art sample; no battle/grid state dependencies.
const Batch = preload("res://scripts/map/open_world/voxel_batch.gd")
const Prop = preload("res://scripts/map/open_world/voxel_prop.gd")
const SIZE := 128
const CHUNK := 16
const WATER := 2.6
@export var world_seed: int = 7319
var noise := FastNoiseLite.new()
var camera: Camera3D
var focus := Vector3(64, 3, 64)
var yaw := 0.55
var pitch := 0.65
var distance := 105.0
var hud: CanvasLayer

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	_build_world()
	_setup_view()
	_setup_hud()
	for arg in OS.get_cmdline_user_args():
		if arg == "--view=village":
			_preset(2)
		if arg == "--view=mountain":
			_preset(3)
	if "--sample-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://open_world_preview.png")
		get_tree().quit()

func _river(z: float) -> float:
	return 64.0 + sin(z * 0.055) * 13.0 + sin(z * 0.12) * 3.0

func _height(x: float, z: float) -> float:
	var river_distance := absf(x - _river(z))
	if river_distance < 4.0:
		return 1.5
	var mountain := maxf(0.0, 1.0 - Vector2((x - 100) / 34.0, (z - 24) / 34.0).length())
	var h := 3.5 + (noise.get_noise_2d(x, z) + 0.4) * 3.0 + mountain * 23.0
	h = lerpf(3.0, h, smoothstep(4.0, 13.0, river_distance))
	# Settlement and bridge approaches have a continuous, level ground plane.
	var village := Vector2(x - 46, z - 80).length()
	h = lerpf(3.5, h, smoothstep(14.0, 22.0, village))
	if absf(z - 80.0) < 3.0 and x > 43 and x < 82:
		h = 3.5
	return floorf(h * 2.0) / 2.0

func _path(x: float, z: float) -> bool:
	return (absf(z - 80.0) < 2.0 and x > 23 and x < 100) or (absf(x - (43.0 + sin(z * 0.07) * 4.0)) < 1.5 and z > 42)

func _build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for cz in range(0, SIZE, CHUNK):
		for cx in range(0, SIZE, CHUNK):
			var chunk := Node3D.new()
			chunk.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			add_child(chunk)
			var b := Batch.new()
			for z in range(cz, cz + CHUNK):
				for x in range(cx, cx + CHUNK):
					var h := _height(x, z)
					var river_distance := absf(x - _river(z))
					var color := "grass"
					if h > 17: color = "snow"
					elif h > 10: color = "rock_light" if h > 13 else "rock"
					elif river_distance < 6: color = "sand"
					elif _path(x, z): color = "path"
					else: color = ["grass", "grass_light", "grass_dark"][rng.randi_range(0, 2)]
					# Only exposed side depth is emitted, avoiding buried columns.
					var low := h
					for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						low = minf(low, _height(x + d.x, z + d.y))
					if x == 0 or z == 0 or x == SIZE - 1 or z == SIZE - 1: low = -1.0
					if low < h - 0.25:
						b.box(Vector3(x + 0.5, (low + h - 0.25) / 2, z + 0.5), Vector3(1, h - 0.25 - low, 1), "rock" if h > 9 else "earth")
					b.box(Vector3(x + 0.5, h - 0.125, z + 0.5), Vector3(1, 0.25, 1), color)
					if river_distance < 4:
						b.box(Vector3(x + 0.5, WATER, z + 0.5), Vector3(1, 0.15, 1), "water")
						if rng.randf() < 0.045:
							b.box(Vector3(x + 0.5, WATER + 0.09, z + 0.5), Vector3(0.65, 0.025, 0.12), "foam")
					elif color.begins_with("grass") and not _reserved(x, z):
						var roll := rng.randf()
						if roll < (0.085 if x < 32 or z < 50 else 0.018):
							Prop.append(b, "pine" if z < 58 else "oak", Vector3(x + 0.5, h, z + 0.5), rng.randf_range(0.8, 1.35))
						elif roll < 0.095:
							Prop.append(b, "rock", Vector3(x + 0.5, h, z + 0.5), rng.randf_range(0.5, 1.0))
						elif roll < 0.15:
							b.box(Vector3(x + 0.5, h + 0.16, z + 0.5), Vector3(0.16, 0.32, 0.16), "flower")
			b.commit(chunk)
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	for pos in [Vector2(37, 74), Vector2(47, 72), Vector2(38, 87), Vector2(50, 89)]:
		var house := Prop.new()
		house.kind = "cottage"
		house.position = Vector3(pos.x, 3.5, pos.y)
		landmarks.add_child(house)
	var tower := Prop.new()
	tower.kind = "tower"
	tower.position = Vector3(93, _height(93, 42), 42)
	landmarks.add_child(tower)
	var bridge := Batch.new()
	var center := _river(80)
	for i in range(-7, 8):
		bridge.box(Vector3(center + i, 3.55, 80), Vector3(0.96, 0.3, 4.0), "wood")
		if i % 2 == 0:
			for z in [78.15, 81.85]:
				bridge.box(Vector3(center + i, 3.9, z), Vector3(0.22, 1.6, 0.22), "trunk")
	for z in [78.15, 81.85]:
		bridge.box(Vector3(center, 4.45, z), Vector3(15, 0.18, 0.18), "wood")
	bridge.commit(landmarks)
	print("[OpenWorldSample] Built 128 x 128 terrain, 64 chunks; seed=", world_seed)

func _reserved(x: float, z: float) -> bool:
	return Vector2(x - 44, z - 80).length() < 17 or Vector2(x - 93, z - 42).length() < 6 or absf(z - 80) < 4 or _path(x - 2, z) or _path(x + 2, z)

func _setup_view() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("b9cdd0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d2e1dc")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("fff0cc")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 52
	camera.far = 500
	add_child(camera)
	camera.make_current()
	_update_camera()

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 28)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.16, 0.9)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	var label := Label.new()
	label.text = "W I L D W O O D   /   01\nVoxel open-world study\n\nWASD / Arrows  Move    Shift  Fast\nRight drag  Orbit    Wheel  Zoom\n1  Valley    2  Village    3  Highlands\nH  Hide UI"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("e5e7d8"))
	panel.add_child(label)

func _process(delta: float) -> void:
	var motion := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	motion = (motion + GamepadInput.stick()).limit_length()
	var look := GamepadInput.stick(true)
	if not look.is_zero_approx() or not is_zero_approx(GamepadInput.zoom()):
		yaw -= look.x * delta * 2.2
		pitch = clampf(pitch + look.y * delta * 1.5, 0.2, 1.35)
		distance = clampf(distance * exp(-GamepadInput.zoom() * delta), 10.0, 190.0)
		_update_camera()
	if motion.length_squared() > 0:
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var back := Vector3(sin(yaw), 0, cos(yaw))
		var speed := 40.0 if (Input.is_physical_key_pressed(KEY_SHIFT) or GamepadInput.held(JOY_BUTTON_LEFT_STICK)) else 16.0
		focus += (right * motion.x + back * motion.y) * delta * speed
		focus.x = clampf(focus.x, 4, SIZE - 4)
		focus.z = clampf(focus.z, 4, SIZE - 4)
		focus.y = maxf(WATER, _height(focus.x, focus.z)) + 1.0
		_update_camera()

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	# Keep an orbiting inspection camera above stepped terrain.
	if camera.position.x >= 0 and camera.position.x < SIZE and camera.position.z >= 0 and camera.position.z < SIZE:
		camera.position.y = maxf(camera.position.y, _height(camera.position.x, camera.position.z) + 3)
	camera.look_at(focus)

func _preset(index: int) -> void:
	yaw = 0.55
	pitch = 0.65
	match index:
		1:
			focus = Vector3(64, 3, 64)
			distance = 105
		2:
			focus = Vector3(47, 4, 79)
			distance = 39
		3:
			focus = Vector3(92, 13, 36)
			distance = 58
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	event = GamepadInput.as_key(event, {JOY_BUTTON_DPAD_UP: KEY_1, JOY_BUTTON_DPAD_RIGHT: KEY_2, JOY_BUTTON_DPAD_DOWN: KEY_3, JOY_BUTTON_BACK: KEY_H})
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch + event.relative.y * 0.005, 0.2, 1.35)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(10, distance * 0.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(190, distance * 1.1)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _preset(1)
			KEY_2: _preset(2)
			KEY_3: _preset(3)
			KEY_H: hud.visible = not hud.visible
