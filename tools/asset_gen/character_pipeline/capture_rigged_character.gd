extends SceneTree
## Drives the standalone test character (scenes/characters/standalone/test.tscn) as the explorer of
## JRPGWorldSample2 with real key input and captures it standing, walking and running, then after
## cycling the whole roster back to it.
## Needs a renderer (not --headless): godot --path . --script res://tools/asset_gen/character_pipeline/capture_rigged_character.gd -- [out_dir]
## Images: <out_dir>/idle.png, walk_<n>.png, run_<n>.png, stop.png, switched.png (default artifacts/rigged_character).

const SAMPLE := "res://samples/JRPGWorldSample2.tscn"
const CHARACTER_ID := "standalone_test"

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok: failures += 1


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/rigged_character"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var world = (load(SAMPLE) as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(4.0).timeout
	var player = world.player
	check(player.model.character_id == CHARACTER_ID, "the explorer starts as the test character")
	var animation: AnimationPlayer = player.animation_player
	for clip: String in ["idle", "walk", "run"]:
		check(animation.has_animation(clip) and animation.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, clip + " clip loops")
	check(player.sword_combat == null, "no weapon is installed")
	world.hud.visible = false
	world.field_weather.controls.visible = false
	world.distance = 6.0
	world.pitch = 0.3
	world._focus_player()
	world._update_camera()
	await create_timer(0.3).timeout
	check(animation.current_animation == "idle", "stands in idle")
	await _shot(out_dir + "/idle.png")
	var start: Vector3 = player.position
	_key(KEY_D, true)
	for n in 3:
		await create_timer(0.31).timeout
		await _shot(out_dir + "/walk_%d.png" % n)
	check(animation.current_animation == "walk", "walks while a direction is held: " + animation.current_animation)
	var walked: float = player.position.distance_to(start)
	check(walked > 1.0, "walking moves the explorer (%.1f m)" % walked)
	_key(KEY_SHIFT, true)
	await create_timer(0.8).timeout
	start = player.position
	for n in 3:
		await create_timer(0.23).timeout
		await _shot(out_dir + "/run_%d.png" % n)
	check(animation.current_animation == "run", "runs with Shift: " + animation.current_animation)
	check(player.position.distance_to(start) > walked * 0.9, "running is faster than walking")
	_key(KEY_SHIFT, false)
	_key(KEY_D, false)
	await create_timer(1.2).timeout
	check(animation.current_animation == "idle", "stops in idle: " + animation.current_animation)
	await _shot(out_dir + "/stop.png")
	# Cycle the whole roster (V) back to the test character, then walk toward the camera.
	for n in world.character_roster.size():
		_key(KEY_V, true)
		_key(KEY_V, false)
		await create_timer(0.15).timeout
	check(player.model.character_id == CHARACTER_ID, "the roster cycles back to the test character")
	_key(KEY_S, true)
	await create_timer(0.7).timeout
	check(player.animation_player.current_animation == "walk", "walks again after switching")
	await _shot(out_dir + "/switched.png")
	_key(KEY_S, false)
	print("RIGGED_CHARACTER_CAPTURE failures=", failures)
	quit(1 if failures > 0 else 0)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("CAPTURE ", path)
