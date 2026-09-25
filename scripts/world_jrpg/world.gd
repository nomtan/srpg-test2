extends Node3D
## Independent exploration and encounter prototype. Existing battle scenes are untouched.
const Batch = preload("res://scripts/world_jrpg/voxel_batch.gd")
const Prop = preload("res://scripts/world_jrpg/voxel_prop.gd")
const SIZE := 400
const CHUNK := 32
const WATER := 2.6
@export var world_seed: int = 7319
var noise := FastNoiseLite.new()
var height_cache := PackedFloat32Array()
var obstacle_chunks: Dictionary = {}
var camera: Camera3D
var world_environment: Environment
const WeatherSystem = preload("res://scripts/world_jrpg/field_weather.gd")
var field_weather: Node
var focus := Vector3(64, 3, 64)
var yaw := -1.15
var pitch := 0.42
var distance := 23.0
var hud: CanvasLayer
const Actor = preload("res://scripts/world_jrpg/pixel_actor.gd")
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
const AdventurerNPC = preload("res://scenes/characters/adventurer_npc.tscn")
const TripoKnightNPC = preload("res://scenes/characters/tripo_knight_npc.tscn")
const TripoHeroNPC = preload("res://scenes/characters/tripo_hero_npc.tscn")
const WALK_SPEED := 4.5
const RUN_SPEED := 16.0
@export var use_3d_player := true
@export var player_model: PackedScene
@export var character_roster: Array[PackedScene] = []
var player_roster_index := -1
var character_text: Label
const Skirmish = preload("res://scripts/world_jrpg/skirmish.gd")
@export_file("*.json") var story_path := "res://assets/world_jrpg/story.json"
var player: Node3D
var npcs: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var story: Dictionary
var mode := "explore"
var overview := false
var cleared := false
var dialog_lines: Array = []
var dialog_index := 0
var dialog_callback: Callable
var dialog_panel: PanelContainer
var dialog_text: Label
var location_text: Label
var prompt_text: Label
var encounter_marker: Node3D
var encounter_position := Vector3.ZERO
var battle: Node3D
var return_position := Vector3.ZERO
var encounter_rearm := false

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	_cache_heights()
	_build_world()
	_setup_view()
	_setup_hud()
	_spawn_characters()
	_focus_player()
	_update_camera()
	for arg in OS.get_cmdline_user_args():
		if arg == "--view=overview":
			_preset(1)
		if arg == "--view=battle":
			player.position = encounter_position + Vector3(0, 0.05, 0)
			_start_battle()
		if arg == "--view=dialog":
			_show_dialog(story.npcs[0].name, story.npcs[0].lines)
		if arg == "--view=village":
			_preset(2)
		if arg == "--view=bridge":
			_preset(4)
		if arg == "--view=mountain":
			_preset(3)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			field_weather.apply_conditions(maxi(0, ["morning", "day", "evening", "night"].find(arg.get_slice("=", 1))), field_weather.weather_index)
		if arg.begins_with("--weather="):
			field_weather.apply_conditions(field_weather.time_index, maxi(0, ["clear", "rain", "cloudy", "snow"].find(arg.get_slice("=", 1))))
	if "--sample-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var capture_name := "cliff"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--view="): capture_name = arg.get_slice("=", 1)
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--time=") or arg.begins_with("--weather="): capture_name += "_" + arg.get_slice("=", 1)
		get_viewport().get_texture().get_image().save_png("res://assets/world_jrpg/preview_%s.png" % capture_name)
		get_tree().quit()

func _river(z: float) -> float:
	return 64.0 + sin(z * 0.055) * 13.0 + sin(z * 0.12) * 3.0

func _height(x: float, z: float) -> float:
	var ix := floori(x) + 1
	var iz := floori(z) + 1
	if not height_cache.is_empty() and ix >= 0 and iz >= 0 and ix < SIZE + 2 and iz < SIZE + 2:
		return height_cache[iz * (SIZE + 2) + ix]
	return _expanded_height(x, z)

func _cache_heights() -> void:
	height_cache.resize((SIZE + 2) * (SIZE + 2))
	for z in range(-1, SIZE + 1):
		for x in range(-1, SIZE + 1):
			height_cache[(z + 1) * (SIZE + 2) + x + 1] = _expanded_height(x, z)

func _expanded_height(x: float, z: float) -> float:
	if x < 128 and z < 128: return _legacy_height(x, z)
	var h := 5.0 + (noise.get_noise_2d(x * 0.65, z * 0.65) + 0.5) * 7.0
	var highland := maxf(0, 1.0 - Vector2((x - 305) / 85.0, (z - 65) / 70.0).length())
	h += highland * 24.0
	var coast := 366.0 + sin(x * 0.025) * 9.0
	h = lerpf(1.0, h, (1.0 - smoothstep(coast - 10.0, coast + 3.0, z)))
	# Preserve the original region; its southern sea becomes a sheltered bay.
	var blend := smoothstep(127.0, 155.0, maxf(x, z))
	h = lerpf(_legacy_height(x, z), h, blend)
	# Broad roads connect the old east gate with the distant coast and uplands.
	if absf(z - 80) < 3 and x >= 100 and x < 375: h = 3.5
	if absf(x - 210) < 3 and z >= 80 and z < 355: h = 3.5
	return floorf(h * 2.0) / 2.0

func _legacy_height(x: float, z: float) -> float:
	if z > 110.0 + sin(x * 0.08) * 3.0: return 1.0
	var rd := absf(x - _river(z))
	if rd < 4.0: return 1.5
	var mountain := maxf(0.0, 1.0 - Vector2((x - 103) / 32.0, (z - 23) / 34.0).length())
	var volcano := maxf(0.0, 1.0 - Vector2(x - 24, z - 22).length() / 23.0)
	var h := 3.5 + (noise.get_noise_2d(x, z) + 0.4) * 3.0 + mountain * 25.0
	h = maxf(h, 4.0 + volcano * 25.0)
	if volcano > 0.8: h = 23.0
	h = lerpf(3.0, h, smoothstep(4.0, 13.0, rd))
	# Windwatch plateau: abrupt east cliff, gradual southern approach.
	if x > 17 and x < 36 + floorf((sin(z * 0.33) + 1) * 1.4) and z > 47 and z < 70:
		h = maxf(h, 14.0)
	if x > 17 and x < 36 and z >= 70 and z < 94:
		h = maxf(h, 14.0 - (z - 70.0) * 0.5)
	h = lerpf(3.5, h, smoothstep(13.0, 18.0, Vector2(x - 46, z - 80).length()))
	if x > 78 and x < 104 and z > 33 and z < 57: h = 5.0
	# Accessible roads lead across the river and up to the castle gate.
	if absf(z - 80) < 3 and x > 35 and x < 101: h = 3.5
	if absf(x - 92) < 3 and z >= 54 and z <= 80: h = 3.5 + (80.0 - z) / 26.0 * 1.5
	# A carved southern trail reaches the volcano rim at a walkable gradient.
	if absf(x - 24) < 2.5 and z >= 30 and z <= 46: h = 20.5 - (z - 30.0) * 0.5
	if absf(x - 24) < 2.5 and z > 46 and z <= 49: h = 12.5 + (z - 46.0) * 0.5
	return floorf(h * 2.0) / 2.0

func _surface(x: float, z: float) -> float:
	if x > 45.5 and x < 48.5 and z >= 105 and z < 118.5: return 3.7
	if absf(z - 80) < 1.65 and absf(x - _river(80)) < 8: return 3.7
	return _height(floorf(x), floorf(z))

func _volcanic(x: float, z: float) -> bool:
	return Vector2(x - 24, z - 22).length() < 22

func _path(x: float, z: float) -> bool:
	return (absf(z - 80) < 2 and x >= 100 and x < 375) or (absf(x - 210) < 2 and z >= 80 and z < 355) or (absf(x - 92) < 2 and z > 52 and z < 82) or (x > 26 and x < 30 and z > 60 and z < 98) or (absf(z - 80.0) < 2.0 and x > 23 and x < 100) or (absf(x - (43.0 + sin(z * 0.07) * 4.0)) < 1.5 and z > 42)

func _build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for cz in range(0, SIZE, CHUNK):
		for cx in range(0, SIZE, CHUNK):
			var chunk := Node3D.new()
			chunk.name = "Chunk_%d_%d" % [cx / CHUNK, cz / CHUNK]
			add_child(chunk)
			var b := Batch.new()
			for z in range(cz, mini(cz + CHUNK, SIZE)):
				for x in range(cx, mini(cx + CHUNK, SIZE)):
					var h := _height(x, z)
					var river_distance := absf(x - _river(z))
					var color := "grass"
					if _volcanic(x, z): color = "lava" if Vector2(x - 24, z - 22).length() < 4.8 else "basalt"
					elif h > 21 or (x > 83 and x < 128 and z < 30) or (h > 15 and x < 128): color = "snow"
					elif h > 10 and z < 47: color = "rock_light" if h > 13 else "rock"
					elif h < 3.5 or (x < 128 and (river_distance < 6 or (z > 105 and z < 128))): color = "sand"
					elif _path(x, z): color = "path"
					else: color = ["grass", "grass_light", "grass_dark"][rng.randi_range(0, 2)]
					# Only exposed side depth is emitted, avoiding buried columns.
					var low := h
					for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						low = minf(low, _height(x + d.x, z + d.y))
					if x == 0 or z == 0 or x == SIZE - 1 or z == SIZE - 1: low = -1.0
					if low < h - 0.25:
						var base := low
						while base < h - 0.25:
							var top := minf(base + 1.5, h - 0.25)
							var stratum := "cliff_light" if int(base / 1.5) % 3 == 0 else "cliff"
							b.box(Vector3(x + 0.5, (base + top) / 2, z + 0.5), Vector3(1, top - base, 1), stratum if h > 9 else "earth")
							base = top
					b.box(Vector3(x + 0.5, h - 0.125, z + 0.5), Vector3(1, 0.25, 1), color)
					if h < WATER:
						b.box(Vector3(x + 0.5, WATER, z + 0.5), Vector3(1, 0.15, 1), "sea" if z > 106 else "water")
						if rng.randf() < 0.045:
							b.box(Vector3(x + 0.5, WATER + 0.09, z + 0.5), Vector3(0.65, 0.025, 0.12), "foam")
					elif color.begins_with("grass") and not _reserved(x, z):
						var roll := rng.randf()
						var tree_density := 0.055 if x < 32 or z < 50 else 0.014
						if roll < tree_density:
							obstacles.append(Rect2(Vector2(x, z), Vector2.ONE))
							Prop.append(b, "pine" if z < 58 else "oak", Vector3(x + 0.5, h, z + 0.5), rng.randf_range(0.8, 1.35))
						elif roll < tree_density + 0.007:
							Prop.append(b, "rock", Vector3(x + 0.5, h, z + 0.5), rng.randf_range(0.5, 1.0))
						elif roll < tree_density + 0.045:
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
		obstacles.append(Rect2(pos - Vector2(2.8, 2.3), Vector2(5.6, 4.6)))
	_build_castle(landmarks)
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
	_build_details(landmarks)
	_build_riverside(landmarks)
	_index_obstacles()
	_build_grass()
	print("[JRPGWorld] Built ", SIZE, " x ", SIZE, " terrain; seed=", world_seed)

func _index_obstacles() -> void:
	obstacle_chunks.clear()
	for rect in obstacles:
		var bounds := rect.grow(0.3)
		for z in range(floori(bounds.position.y / CHUNK), floori(bounds.end.y / CHUNK) + 1):
			for x in range(floori(bounds.position.x / CHUNK), floori(bounds.end.x / CHUNK) + 1):
				var key := Vector2i(x, z)
				if not obstacle_chunks.has(key): obstacle_chunks[key] = []
				obstacle_chunks[key].append(bounds)

func _reserved(x: float, z: float) -> bool:
	if x > 43 and x < 51 and z > 101: return true
	if absf(x - 24) < 4 and z > 28 and z < 52: return true
	return (x > 16 and x < 37 and z > 46 and z < 99) or (x > 77 and x < 106 and z > 32 and z < 58) or Vector2(x - 44, z - 80).length() < 17 or Vector2(x - 93, z - 42).length() < 6 or absf(z - 80) < 4 or _path(x - 2, z) or _path(x + 2, z)

func _setup_view() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X
	var environment := Environment.new()
	world_environment = environment
	environment.background_mode = Environment.BG_SKY
	environment.fog_enabled = true
	environment.fog_light_color = Color("b7c4bd")
	environment.fog_light_energy = 0.65
	environment.fog_density = 0.0018
	environment.fog_sun_scatter = 0.25
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b2c2c7")
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -55, 0)
	sun.light_color = Color("ffdda3")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 52
	camera.far = 1200
	add_child(camera)
	camera.make_current()
	field_weather = WeatherSystem.new()
	field_weather.name = "FieldWeather"
	add_child(field_weather)
	field_weather.setup(self, sun)
	_update_camera()

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	# Keep an orbiting inspection camera above stepped terrain.
	if camera.position.x >= 0 and camera.position.x < SIZE and camera.position.z >= 0 and camera.position.z < SIZE:
		camera.position.y = maxf(camera.position.y, _height(camera.position.x, camera.position.z) + 3)
	camera.look_at(focus)

func _preset(index: int) -> void:
	overview = true
	yaw = 0.55
	pitch = 0.65
	match index:
		1:
			focus = Vector3(SIZE * 0.5, 5, SIZE * 0.5)
			distance = SIZE * 1.4
		2:
			focus = Vector3(48, 5.0, 80)
			yaw = 0.65
			pitch = 0.5
			distance = 27
		3:
			focus = Vector3(92, 13, 36)
			distance = 58
		4:
			focus = Vector3(55, 4.5, 80)
			yaw = 1.45
			pitch = 0.22
			distance = 22
	_update_camera()

func _build_castle(parent: Node3D) -> void:
	var b := Batch.new()
	var p := Vector3(92, 5, 43)
	for x in [-8, 8]:
		for z in [-7, 7]:
			Prop.append(b, "tower", p + Vector3(x, 0, z))
	for z in [-7, 7]:
		for x in range(-7, 8):
			if z == 7 and abs(x) < 2: continue
			b.box(p + Vector3(x, 2, z), Vector3(1, 4, 1), "rock_light")
			if x % 2 == 0: b.box(p + Vector3(x, 4.4, z), Vector3(0.8, 0.8, 1), "plaster")
	for x in [-8, 8]:
		b.box(p + Vector3(x, 2, 0), Vector3(1, 4, 14), "rock_light")
	b.box(p + Vector3(0, 3.5, -2), Vector3(8, 7, 7), "plaster")
	for i in 7:
		b.box(p + Vector3(0, 7.3 + i * 0.4, -2), Vector3(9 - i, 0.4, 8 - i), "roof" if i % 2 == 0 else "roof_light")
	for x in [-2.5, 0, 2.5]:
		b.box(p + Vector3(x, 4.5, 1.55), Vector3(0.65, 2, 0.1), "window")
	b.box(p + Vector3(0, 4.5, 7), Vector3(4, 1, 1), "rock_light")
	b.commit(parent)
	obstacles.append_array([Rect2(82, 34, 3, 19), Rect2(99, 34, 3, 19), Rect2(84, 35, 16, 2), Rect2(84, 49, 6, 3), Rect2(94, 49, 6, 3), Rect2(88, 37, 8, 8)])

func _build_details(parent: Node3D) -> void:
	var b := Batch.new()
	# Timber viewing deck at the edge of the plateau.
	b.box(Vector3(33, 14.08, 59), Vector3(5, 0.16, 9), "wood")
	for z in range(55, 64, 2):
		b.box(Vector3(35.4, 14.8, z), Vector3(0.16, 1.5, 0.16), "trunk")
	b.box(Vector3(35.4, 15.4, 59), Vector3(0.15, 0.18, 9), "wood")
	# Village well and market awning.
	for x in [-1, 1]:
		b.box(Vector3(44 + x, 4, 76), Vector3(0.4, 1, 2.4), "rock_light")
		b.box(Vector3(44 + x, 5.2, 76), Vector3(0.15, 3.0, 0.15), "trunk")
	b.box(Vector3(44, 6.7, 76), Vector3(3.0, 0.3, 3.0), "roof")
	obstacles.append(Rect2(42.6, 74.6, 2.8, 2.8))
	for x in range(48, 54):
		b.box(Vector3(x, 6.0, 83), Vector3(1, 0.15, 3), "plaster" if x % 2 == 0 else "flag")
	for x in [48, 53]:
		b.box(Vector3(x, 4.8, 83), Vector3(0.16, 2.5, 0.16), "wood")
	b.box(Vector3(50.5, 4.1, 83), Vector3(5, 1, 0.9), "wood")
	obstacles.append(Rect2(47.5, 82.4, 6, 1.2))
	# Small south-coast jetty, boats and a lighthouse.
	for z in range(105, 119):
		b.box(Vector3(47, 3.6, z), Vector3(3, 0.2, 0.94), "wood")
	for z in [110, 114, 118]:
		for x in [45.7, 48.3]: b.box(Vector3(x, 2.1, z), Vector3(0.2, 4, 0.2), "trunk")
	for z in [113, 118]:
		b.box(Vector3(51, 2.9, z), Vector3(2.2, 0.5, 4), "wood")
		b.box(Vector3(51, 4.6, z), Vector3(0.12, 3.4, 0.12), "trunk")
		b.box(Vector3(51.5, 5, z), Vector3(1.3, 1.8, 0.06), "plaster")
	Prop.append(b, "tower", Vector3(103, _height(103, 103), 103))
	b.commit(parent)
	for entry in [["風見の崖", 30, 58], ["リーヴェの町", 43, 85], ["暁の城", 92, 43], ["白銀の高地", 103, 22], ["燼の火山", 24, 22], ["南の海", 80, 115]]:
		var label := Label3D.new()
		label.text = entry[0]
		label.position = Vector3(entry[1], _height(entry[1], entry[2]) + 11, entry[2])
		label.font_size = 42
		label.pixel_size = 0.018
		label.visibility_range_begin = 35.0
		label.modulate = Color("fff2cb")
		label.outline_modulate = Color("243e47")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

func _spawn_characters() -> void:
	story = JSON.parse_string(FileAccess.get_file_as_string(story_path))
	player = Explorer.new()
	if player_model: player.model_scene = player_model
	player.use_3d = use_3d_player
	player.name = "Explorer"
	add_child(player)
	player.position = Vector3(32, 14.05, 60)
	if character_roster.is_empty():
		# Separate stationary job-body preview, on the clear starting plateau.
		var adventurer := AdventurerNPC.instantiate() as Node3D
		add_child(adventurer)
		adventurer.position = Vector3(30.5, _surface(30.5, 57.5) + 0.05, 57.5)
		adventurer.rotation.y = -0.65
		npcs.append({"actor": adventurer, "data": {
			"id": "adventurer", "name": "冒険者", "job_id": "adventurer",
			"lines": ["やあ、旅の仲間だね。ここから一緒に世界を見渡してみよう。"]
		}})
		var knight := TripoKnightNPC.instantiate() as Node3D
		add_child(knight)
		knight.position = adventurer.position + Vector3(-2.4, 0, -1.8)
		knight.position.y = _surface(knight.position.x, knight.position.z) + 0.05
		knight.rotation.y = adventurer.rotation.y
		npcs.append({"actor": knight, "data": {
			"id": "tripo_knight", "name": "騎士",
			"lines": ["この辺りの見張りは任せてくれ。"]
		}})
		var hero := TripoHeroNPC.instantiate() as Node3D
		add_child(hero)
		hero.position = knight.position + Vector3(-2.4, 0, -1.8)
		hero.position.y = _surface(hero.position.x, hero.position.z) + 0.05
		hero.rotation.y = knight.rotation.y
		npcs.append({"actor": hero, "data": {
			"id": "tripo_hero", "name": "勇者",
			"lines": ["準備はできているよ。一緒に冒険へ出かけよう。"]
		}})
	else:
		_spawn_tripo_roster()
	for data: Dictionary in story.npcs:
		var actor := Actor.new()
		actor.palette_name = data.palette
		add_child(actor)
		var point := Vector2(data.position[0], data.position[1])
		actor.position = Vector3(point.x, _surface(point.x, point.y) + 0.05, point.y)
		var label := Label3D.new()
		label.text = data.name + "  ◇"
		label.position.y = 2.9
		label.font_size = 24
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		actor.add_child(label)
		npcs.append({"actor": actor, "data": data})
	var ep: Array = story.encounter.position
	encounter_position = Vector3(ep[0], _surface(ep[0], ep[1]), ep[1])
	encounter_marker = Node3D.new()
	add_child(encounter_marker)
	encounter_marker.position = encounter_position
	var b := Batch.new()
	for i in 4:
		b.box(Vector3(-1.5 + i, 0.07, -1.5), Vector3(0.7, 0.1, 0.15), "gold")
		b.box(Vector3(-1.5 + i, 0.07, 1.5), Vector3(0.7, 0.1, 0.15), "gold")
	b.commit(encounter_marker)
	var mark := Label3D.new()
	mark.text = "⚔\n街道の気配"
	mark.position.y = 3.5
	mark.font_size = 36
	mark.pixel_size = 0.026
	mark.modulate = Color("edc779")
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	encounter_marker.add_child(mark)

func _build_riverside(parent: Node3D) -> void:
	var b := Batch.new()
	var center := _river(80)
	# Separate boards, stone abutments and a second rail give the bridge weight.
	for i in range(-30, 31):
		b.box(Vector3(center + i * 0.25, 3.73, 80), Vector3(0.23, 0.05, 3.35), "wood" if i % 4 else "trunk")
	for z in [78.15, 81.85]:
		b.box(Vector3(center, 3.98, z), Vector3(15, 0.14, 0.16), "trunk")
	for x in [center - 6.5, center + 6.5]:
		b.box(Vector3(x, 2.75, 80), Vector3(1.1, 1.5, 3.5), "rock")
	# Coursed river walls leave gaps for reeds and descending banks.
	for z in range(61, 108, 2):
		if absf(z - 80) < 5: continue
		for side in [-1, 1]:
			var x: float = _river(z) + side * 5.2
			var h := _surface(x, z)
			b.box(Vector3(x, h + 0.18, z), Vector3(0.55, 0.36, 1.75), "rock")
			if z % 6 == 1: b.box(Vector3(x, h + 0.43, z), Vector3(0.62, 0.16, 1.6), "rock_light")
	# Bridge-side gardens and lanterns; the main street stays open.
	for point in [Vector2(54, 86), Vector2(55, 71), Vector2(66, 72), Vector2(66, 88), Vector2(42, 94)]:
		if _surface(point.x, point.y) < WATER: continue
		Prop.append(b, "oak", Vector3(point.x, _surface(point.x, point.y), point.y), 1.3)
		obstacles.append(Rect2(point - Vector2(0.3, 0.3), Vector2(0.6, 0.6)))
	for point in [Vector2(53, 78), Vector2(64, 78), Vector2(42, 83)]:
		var p := Vector3(point.x, _surface(point.x, point.y), point.y)
		b.box(p + Vector3(0, 1.5, 0), Vector3(0.17, 3, 0.17), "trunk")
		b.box(p + Vector3(0.25, 2.8, 0), Vector3(0.5, 0.55, 0.42), "gold")
		b.box(p + Vector3(0.25, 3.12, 0), Vector3(0.65, 0.13, 0.57), "trunk")
	for point in [Vector2(40, 89), Vector2(49, 85), Vector2(51, 85), Vector2(36, 78)]:
		var p := Vector3(point.x, _surface(point.x, point.y), point.y)
		b.box(p + Vector3(0, 0.35, 0), Vector3(0.72, 0.7, 0.72), "wood")
		for y in [0.1, 0.55]: b.box(p + Vector3(0, y, 0), Vector3(0.77, 0.07, 0.77), "trunk")
		obstacles.append(Rect2(point - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))
	b.commit(parent)

func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 91
	# Fine vegetation is concentrated around the playable settlement and river.
	for cz in range(32, 128, 16):
		for cx in range(16, 112, 16):
			var detail := Node3D.new()
			detail.name = "Meadow_%d_%d" % [cx, cz]
			add_child(detail)
			var b := Batch.new()
			for z in range(cz, cz + 16):
				for x in range(cx, cx + 16):
					var h := _surface(x + 0.5, z + 0.5)
					if h < WATER or h > 15 or _volcanic(x, z) or _path(x, z): continue
					var p := Vector3(x + 0.5, h + 0.05, z + 0.5)
					if not _can_walk(p, p): continue
					if x > 30 and x < 36 and z > 54 and z < 64: continue
					var bank := absf(x - _river(z)) < 7
					var density := 5 if bank else 3
					for tuft in density:
						var base := Vector3(x + rng.randf(), h, z + rng.randf())
						# Ground each tuft on its own voxel, including the river/bridge edge.
						base.y = _surface(base.x, base.z)
						if base.y < WATER: continue
						b.vegetation.plant("reed" if bank else "grass", base, rng.randf_range(0.8, 1.25), rng.randf() * TAU, rng.randi_range(0, 2))
						if rng.randf() < 0.09:
							b.box(base + Vector3(0, 0.4, 0), Vector3(0.1, 0.08, 0.1), "flower_white")
			b.commit(detail)
			for mesh: GeometryInstance3D in detail.get_children():
				if not mesh.name.begins_with("Natural_"): mesh.visibility_range_end = 100

func _panel(at: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = at
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.10, 0.14, 0.94)
	style.border_color = Color("a18a5d")
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	return panel

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var info := VBoxContainer.new()
	_panel(Vector2(24, 24)).add_child(info)
	var title := Label.new()
	title.text = "A U R E L I A   /   風の向こうへ"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color("edcf94")
	info.add_child(title)
	location_text = Label.new()
	info.add_child(location_text)
	var help := Label.new()
	help.text = "WASD / 矢印 : 歩く   Shift : 走る   E : 会話\nJ / X・□ : 横薙ぎ　K / Y・△ : 上段斬り\n右ドラッグ : 視点   ホイール : 距離   M / LB : 全景\n1–4 : 景観   R : キャラクターに戻る   H : UI\nパッド：左 移動 + RB 走る　右 視点 / 押込 戻す\nA 会話　B・○ 切替（会話中は閉じる）　LT/RT 距離\n十字 景観　Back UI　B / V / 左押込：2D・3D切替"
	if not character_roster.is_empty():
		help.text = help.text.replace("2D・3D切替", "操作キャラ切替")
	help.add_theme_font_size_override("font_size", 16)
	info.add_child(help)
	if not character_roster.is_empty():
		character_text = Label.new()
		info.add_child(character_text)
	prompt_text = Label.new()
	prompt_text.modulate = Color("edcf94")
	info.add_child(prompt_text)
	dialog_panel = _panel(Vector2.ZERO)
	dialog_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialog_panel.offset_left = 48
	dialog_panel.offset_right = -48
	dialog_panel.offset_top = -210
	dialog_panel.offset_bottom = -32
	dialog_text = Label.new()
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.add_theme_font_size_override("font_size", 22)
	dialog_panel.add_child(dialog_text)
	dialog_panel.hide()

func _spawn_tripo_roster() -> void:
	var initial_visual := player.model.get_node_or_null("Model") as Node3D
	for index in character_roster.size():
		var actor := character_roster[index].instantiate() as Node3D
		add_child(actor)
		if initial_visual and actor.get_node("Model").scene_file_path == initial_visual.scene_file_path:
			player_roster_index = index
			character_text.text = "操作キャラ：" + actor.display_name
		# Three rows on the clear starting plateau, with room to walk between them.
		var x := 24.5 + float(index % 3) * 3.6
		var z := 57.0 - floorf(float(index) / 3.0) * 3.6
		if actor.character_id.begins_with("golden_path_"):
			x = 28.0 if actor.character_id == "golden_path_001" else 35.0
			z = 63.0
		actor.position = Vector3(x, _surface(x, z) + 0.05, z)
		actor.rotation.y = -0.65
		npcs.append({"actor": actor, "data": {
			"id": "tripo_" + actor.character_id, "name": actor.display_name,
			"lines": Array(actor.dialogue)
		}})

func _focus_player() -> void:
	overview = false
	focus = player.position + Vector3(0, 1.0, 0)

func _can_walk(p: Vector3, from: Vector3) -> bool:
	if p.x < 1 or p.z < 1 or p.x >= SIZE - 1 or p.z >= SIZE - 1: return false
	if _surface(p.x, p.z) < WATER: return false
	if absf(_surface(p.x, p.z) - _surface(from.x, from.z)) > 0.76: return false
	if _volcanic(p.x, p.z) and Vector2(p.x - 24, p.z - 22).length() < 5: return false
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK)), []):
		if rect.has_point(Vector2(p.x, p.z)): return false
	for npc in npcs:
		if p.distance_to(npc.actor.position) < 0.7: return false
	return true

func _process(delta: float) -> void:
	if player == null: return
	if mode != "explore": return
	player.walking = false
	player.running = false
	player.locomotion_speed = 0.0
	var motion := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	motion = (motion + GamepadInput.stick()).limit_length()
	var look := GamepadInput.stick(true)
	if not look.is_zero_approx() or not is_zero_approx(GamepadInput.zoom()):
		yaw -= look.x * delta * 2.2
		pitch = clampf(pitch + look.y * delta * 1.5, 0.2, 1.35)
		distance = clampf(distance * exp(-GamepadInput.zoom() * delta), 9.0, SIZE * 1.8)
		_update_camera()
	if motion.length_squared() > 0 and not player.attacking:
		if overview:
			distance = 27
			_focus_player()
		player.running = Input.is_physical_key_pressed(KEY_SHIFT) or GamepadInput.held(JOY_BUTTON_RIGHT_SHOULDER)
		var velocity := (Vector3(cos(yaw), 0, -sin(yaw)) * motion.x + Vector3(sin(yaw), 0, cos(yaw)) * motion.y) * (RUN_SPEED if player.running else WALK_SPEED)
		player.world_facing = velocity.normalized()
		var start_position: Vector3 = player.position
		# Substeps keep water, cliffs and building bounds solid at low frame rates.
		var steps := maxi(1, ceili(velocity.length() * delta / 0.18))
		for i in steps:
			for offset in [Vector3(velocity.x, 0, 0), Vector3(0, 0, velocity.z)]:
				var next: Vector3 = player.position + offset * delta / steps
				if _can_walk(next, player.position):
					player.position = Vector3(next.x, _surface(next.x, next.z) + 0.05, next.z)
		var moved := Vector2(player.position.x - start_position.x, player.position.z - start_position.z)
		player.walking = not moved.is_zero_approx()
		if delta > 0.0: player.locomotion_speed = moved.length() / delta
		player.facing = (1 if motion.x > 0 else 2) if absf(motion.x) > absf(motion.y) else (0 if motion.y > 0 else 3)
	if not overview:
		_update_follow_focus(delta)
		_update_camera()
	location_text.text = "%s   /   探索中" % _region()
	prompt_text.text = "目標 : 町へ下り、橋の先の街道を調べる" if not cleared else "街道は安全になった。自由に各地を探索しよう。"
	for npc in npcs:
		if player.position.distance_to(npc.actor.position) < 3.2:
			prompt_text.text = "E / A  :  " + str(npc.data.name) + " と話す"
			break
	if encounter_rearm and player.position.distance_to(encounter_position) > float(story.encounter.radius) + 1.0:
		encounter_rearm = false
	if not cleared and not encounter_rearm and player.position.distance_to(encounter_position) < float(story.encounter.radius):
		_show_dialog(story.encounter.title, story.encounter.lines, _start_battle)

func _update_follow_focus(delta: float) -> void:
	# Horizontal lag varies with frame time and makes a fast runner rock
	# forward/back in screen space. Only soften the stepped terrain height.
	focus.x = player.position.x
	focus.z = player.position.z
	focus.y = lerpf(focus.y, player.position.y + 1.0, 1.0 - exp(-10.0 * delta))

func _region() -> String:
	var p := player.position
	if p.x >= 128 or p.z >= 128:
		if p.z > 345: return "遥かなる南海岸"
		if p.x > 240 and p.z < 135: return "東の大高原"
		if p.z > 180: return "南の大森林"
		return "東方の草原"
	if p.z > 103: return "南の海岸"
	if p.x < 36 and p.z > 47 and p.z < 72: return "風見の崖"
	if p.x > 79 and p.z < 33: return "白銀の高地"
	if _volcanic(p.x, p.z): return "燼の火山"
	if p.x > 79 and p.z < 58: return "暁の城"
	if p.x < 58 and p.z > 65 and p.z < 97: return "リーヴェの町"
	return "翠の草原"

func _show_dialog(speaker: String, lines: Array, after: Callable = Callable()) -> void:
	mode = "dialog"
	if player:
		player.walking = false
		player.cancel_attack()
	dialog_lines = []
	for line in lines: dialog_lines.append(speaker + "\n\n" + str(line) + "\n\n[E / Enter] 次へ    [Esc] 閉じる")
	dialog_index = 0
	dialog_callback = after
	dialog_text.text = dialog_lines[0]
	dialog_panel.show()
	hud.show()

func _close_dialog() -> void:
	dialog_panel.hide()
	mode = "explore"
	var after := dialog_callback
	dialog_callback = Callable()
	if after.is_valid(): after.call()

func _start_battle() -> void:
	mode = "battle"
	player.cancel_attack()
	player.locomotion_speed = -1.0
	encounter_marker.hide()
	return_position = player.position
	battle = Skirmish.new()
	add_child(battle)
	battle.begin(self, player, camera, Callable(self, "_finish_battle"))
	Batch.tactical_cutaway(player.position, 10.0)
	hud.hide()

func _finish_battle(won: bool) -> void:
	Batch.tactical_cutaway(Vector3.ZERO, 0.0)
	battle.queue_free()
	battle = null
	player.walking = false
	if not won: player.position = return_position
	encounter_rearm = not won
	cleared = won
	encounter_marker.visible = not won
	distance = 27
	camera.far = 1200
	_focus_player()
	_update_camera()
	hud.show()
	_show_dialog("街道の襲撃", [story.encounter.victory if won else story.encounter.defeat])

func _input(event: InputEvent) -> void:
	# B switches in exploration; dialogue/battle keep B for close/cancel.
	# V and L3 remain available in every mode without replacing the gameplay actor.
	var toggle: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V
	if event is InputEventJoypadButton and event.pressed:
		toggle = event.button_index == JOY_BUTTON_LEFT_STICK or (event.button_index == JOY_BUTTON_B and mode == "explore")
	if toggle and player:
		if not character_roster.is_empty():
			player_roster_index = (player_roster_index + 1) % character_roster.size()
			use_3d_player = true
			player.use_3d = true
			player.set_model_scene(character_roster[player_roster_index], true)
			character_text.text = "操作キャラ：" + player.model.display_name
		else:
			use_3d_player = not use_3d_player
			player.set_3d_enabled(use_3d_player)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if mode == "battle": return
	event = GamepadInput.as_key(event, {JOY_BUTTON_A: KEY_E, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_X: KEY_J, JOY_BUTTON_Y: KEY_K, JOY_BUTTON_LEFT_SHOULDER: KEY_M, JOY_BUTTON_RIGHT_STICK: KEY_R, JOY_BUTTON_BACK: KEY_H, JOY_BUTTON_DPAD_UP: KEY_1, JOY_BUTTON_DPAD_RIGHT: KEY_2, JOY_BUTTON_DPAD_DOWN: KEY_3, JOY_BUTTON_DPAD_LEFT: KEY_4})
	if event is InputEventKey and event.pressed and not event.echo:
		if mode == "dialog":
			if event.keycode == KEY_ESCAPE: _close_dialog()
			elif event.keycode == KEY_E or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				dialog_index += 1
				if dialog_index >= dialog_lines.size(): _close_dialog()
				else: dialog_text.text = dialog_lines[dialog_index]
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_J, KEY_K:
				player.attack(event.keycode == KEY_K)
				get_viewport().set_input_as_handled()
			KEY_E:
				for npc in npcs:
					if player.position.distance_to(npc.actor.position) < 3.2:
						_show_dialog(npc.data.name, npc.data.lines)
						break
			KEY_M:
				if overview:
					distance = 27
					_focus_player()
					_update_camera()
				else: _preset(1)
			KEY_R:
				distance = 27
				_focus_player()
				_update_camera()
			KEY_1: _preset(1)
			KEY_2: _preset(2)
			KEY_3: _preset(3)
			KEY_4: _preset(4)
			KEY_H: hud.visible = not hud.visible
	elif mode == "explore" and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch + event.relative.y * 0.005, 0.2, 1.35)
		_update_camera()
	elif mode == "explore" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(9, distance * 0.9)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(SIZE * 1.8, distance * 1.1)
		_update_camera()

