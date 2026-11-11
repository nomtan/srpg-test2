extends SceneTree
## Drives the standalone test character (scenes/characters/standalone/test.tscn) as the explorer of
## JRPGWorldSample2 with real key input and captures it standing, walking, running, attacking with the
## sword and shield (J slash, K overhead, L skill, G guard), then after cycling the whole roster back to it.
## Needs a renderer (not --headless): godot --path . --script res://tools/asset_gen/character_pipeline/capture_rigged_character.gd -- [out_dir]
## Images: <out_dir>/idle.png, walk_<n>.png, run_<n>.png, stop.png, slash_<n>.png, overhead_<n>.png, guard.png,
## skill_<n>.png, switched.png (default artifacts/rigged_character).

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
	check(player.sword_combat != null and player.current_weapon() == "sword_shield", "sword and shield are equipped: " + player.current_weapon())
	for clip: String in [player.idle_clip, player.walk_clip, player.run_clip]:
		check(animation.has_animation(clip) and animation.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, clip + " clip loops")
	var skeleton := player.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var modifiers := skeleton.get_children().filter(func(node: Node) -> bool: return node is SkeletonModifier3D)
	check(not modifiers.is_empty() and modifiers[-1].name == "ForearmTwist", "the forearm twist runs after the equipment's modifiers: " + str(modifiers.map(func(node: Node) -> String: return node.name)))
	var model_height: float = _model_height(player.model)
	check(absf(model_height - 1.8) < 0.08, "stands about 1.8 m tall (%.2f m)" % model_height)
	world.hud.visible = false
	world.field_weather.controls.visible = false
	world.distance = 6.0
	world.pitch = 0.3
	world._focus_player()
	world._update_camera()
	await create_timer(0.3).timeout
	check(animation.current_animation == player.idle_clip, "stands in idle: " + animation.current_animation)
	await _shot(out_dir + "/idle.png")
	var start: Vector3 = player.position
	_key(KEY_D, true)
	for n in 3:
		await create_timer(0.31).timeout
		await _shot(out_dir + "/walk_%d.png" % n)
	check(animation.current_animation == player.walk_clip, "walks while a direction is held: " + animation.current_animation)
	var walked: float = player.position.distance_to(start)
	check(walked > 1.0, "walking moves the explorer (%.1f m)" % walked)
	_key(KEY_SHIFT, true)
	await create_timer(0.8).timeout
	start = player.position
	for n in 3:
		await create_timer(0.23).timeout
		await _shot(out_dir + "/run_%d.png" % n)
	check(animation.current_animation == player.run_clip, "runs with Shift: " + animation.current_animation)
	check(player.position.distance_to(start) > walked * 0.9, "running is faster than walking")
	_key(KEY_SHIFT, false)
	_key(KEY_D, false)
	await create_timer(1.2).timeout
	check(animation.current_animation == player.idle_clip, "stops in idle: " + animation.current_animation)
	await _shot(out_dir + "/stop.png")
	for attack: Array in [[KEY_J, "slash", player.sword_combat.slash_clip], [KEY_K, "overhead", player.sword_combat.overhead_clip]]:
		_key(attack[0], true)
		_key(attack[0], false)
		await create_timer(0.05).timeout
		check(animation.current_animation == attack[2], attack[1] + " plays " + str(attack[2]) + ": " + animation.current_animation)
		for n in 3:
			await create_timer(0.09).timeout
			await _shot(out_dir + "/%s_%d.png" % [attack[1], n])
		await create_timer(1.2).timeout
	_key(KEY_G, true)
	await create_timer(0.5).timeout
	# The guard clip ends on the held pose, so the player has stopped by now.
	check(player.guarding and animation.assigned_animation == player.sword_combat.guard_clip, "guards while G is held: " + animation.assigned_animation)
	await _shot(out_dir + "/guard.png")
	_key(KEY_G, false)
	await create_timer(0.6).timeout
	_key(KEY_L, true)
	_key(KEY_L, false)
	await create_timer(0.05).timeout
	check(animation.current_animation == player.sword_combat.skill_clip, "skill plays: " + animation.current_animation)
	for n in 4:
		await create_timer(0.45).timeout
		await _shot(out_dir + "/skill_%d.png" % n)
	await create_timer(1.5).timeout
	# Cycle the whole roster (V) back to the test character, then walk toward the camera.
	for n in world.character_roster.size():
		_key(KEY_V, true)
		_key(KEY_V, false)
		await create_timer(0.15).timeout
	check(player.model.character_id == CHARACTER_ID, "the roster cycles back to the test character")
	_key(KEY_S, true)
	await create_timer(0.7).timeout
	check(player.animation_player.current_animation == player.walk_clip, "walks again after switching")
	await _shot(out_dir + "/switched.png")
	_key(KEY_S, false)
	print("RIGGED_CHARACTER_CAPTURE failures=", failures)
	quit(1 if failures > 0 else 0)


## World-space height of the model's skinned mesh in its rest pose.
func _model_height(model: Node3D) -> float:
	var top := -INF
	var bottom := INF
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
		break
	return top - bottom


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
