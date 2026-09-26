extends SceneTree

const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func switch_event(keyboard := false, button_index: JoyButton = JOY_BUTTON_LEFT_STICK) -> InputEvent:
	if keyboard:
		var key := InputEventKey.new()
		key.keycode = KEY_V
		key.pressed = true
		return key
	var button := InputEventJoypadButton.new()
	button.button_index = button_index
	button.pressed = true
	return button

func run() -> void:
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	world.player.set_process(false)
	var actor = world.player
	var origin: Vector3 = actor.position
	var npc_ids: Array[int] = []
	for npc: Dictionary in world.npcs: npc_ids.append(npc.actor.get_instance_id())
	check(world.player_roster_index == 0, "Initial Character 001 is matched to the placed roster")
	var ids := ["charcter001", "charcter002", "charcter003"]
	for clip in ["idle", "walk", "run"]:
		actor.walking = clip != "idle"
		actor.running = clip == "run"
		actor.locomotion_speed = 16.0 if clip == "run" else 4.5
		actor.world_facing = Vector3(0.6, 0, 0.8)
		actor._update_model()
		for step in ids.size():
			actor.animation_player.seek(actor.animation_player.current_animation_length * .37, true)
			var next: int = (world.player_roster_index + 1) % ids.size()
			Input.parse_input_event(switch_event(step % 3 == 1, JOY_BUTTON_B if step % 3 == 0 else JOY_BUTTON_LEFT_STICK))
			Input.flush_buffered_events()
			check(world.player_roster_index == next and actor.model.character_id == ids[next], clip + ": switches in roster order to " + ids[next])
			check(world.player == actor and actor.position == origin, "Actor identity and position stay unchanged")
			var expected_clip: String = "walk" if clip == "run" and not actor.animation_player.has_animation("run") else clip
			check(actor.animation_player.current_animation == expected_clip, "Current movement animation is preserved")
			check(is_equal_approx(actor.model.rotation.y, -atan2(.8, .6)) and is_equal_approx(actor.model.get_node("Model").rotation.y, PI / 2), "Facing and source orientation are correct")
			check(actor.use_3d and not actor.sprite.visible and not actor.model.get_node("NameLabel").visible, "Player displays only the selected 3D model")
			check(world.character_text.text.ends_with(actor.model.display_name), "HUD shows the selected character")
			if clip != "idle":
				check(is_equal_approx(actor.animation_player.current_animation_position / actor.animation_player.current_animation_length, .37), "Gait phase survives replacement")
			await process_frame
			if "--capture" in OS.get_cmdline_user_args() and clip == "idle" and actor.model.character_id.begins_with("charcter"):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/character_batch/sample_" + actor.model.character_id + ".png")
		check(world.player_roster_index == 0, "Full roster wraps back to Character 001")
	var before: int = world.player_roster_index
	var release := switch_event(false, JOY_BUTTON_B) as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	var echo := switch_event(true) as InputEventKey
	echo.echo = true
	world._input(echo)
	check(world.player_roster_index == before, "Button release and keyboard repeat do not switch")
	for index in world.npcs.size():
		check(world.npcs[index].actor.get_instance_id() == npc_ids[index], "Placed NPC is not replaced")
	actor.walking = false
	actor.position = world.encounter_position + Vector3(0, .05, 0)
	world._start_battle()
	var battle_hero = world.battle.hero
	var battle_position: Vector3 = actor.position
	world.battle._command("attack")
	Input.parse_input_event(switch_event(false, JOY_BUTTON_B))
	Input.flush_buffered_events()
	check(world.player_roster_index == before and world.battle.stage == "menu", "Right face button cancels battle selection without switching character")
	world._input(switch_event())
	check(world.battle.hero == battle_hero and battle_hero == actor and actor.position == battle_position, "Battle keeps the same gameplay hero when the model changes")
	check(actor.model.character_id == "charcter002", "Switching also works in battle")
	world._finish_battle(false)
	await process_frame # Let the queued battle UI leave the real input pipeline.
	world._input(switch_event(true))
	check(world.mode == "dialog" and actor.model.character_id == "charcter003" and world.dialog_index == 0, "Switching also works in dialogue without advancing it")
	Input.parse_input_event(switch_event(false, JOY_BUTTON_B))
	Input.flush_buffered_events()
	check(world.mode == "explore" and actor.model.character_id == "charcter003", "Right face button closes dialogue without switching character")
	world.queue_free()
	await process_frame
	print("TRIPO_SWITCHING: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
