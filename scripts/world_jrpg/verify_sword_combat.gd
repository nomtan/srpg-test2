extends SceneTree
## Run headless for input/state/rig checks; add -- --capture for rendered poses.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
const Combat = preload("res://scripts/world_jrpg/sword_combat.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func button(index: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	return event

func run() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
		quit()
		return
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	var actor = world.player
	actor.set_process(false)
	var origin: Vector3 = actor.position
	var roster_index: int = world.player_roster_index
	check(actor.sword_combat != null, "Initial knight equips the requested sword")
	for event in [button(JOY_BUTTON_X), button(JOY_BUTTON_Y)]:
		var overhead: bool = event.button_index == JOY_BUTTON_Y
		var clip: String = Combat.OVERHEAD if overhead else Combat.SLASH
		actor.walking = true
		actor.running = true
		actor.locomotion_speed = 16.0
		actor._update_model()
		# Use the real input pipeline, including the model-switch handler.
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		check(actor.attacking and actor.animation_player.current_animation == clip, "Face button starts " + clip)
		check(world.player_roster_index == roster_index and not world.overview, "Attack does not switch model or camera")
		check(not actor.walking and not actor.running and is_equal_approx(actor.animation_player.speed_scale, 1.0), "Sprint stops and attack runs at native speed")
		var equipment: RefCounted = actor.sword_combat
		var hand_index: int = equipment.skeleton.find_bone("hand.R")
		actor.animation_player.advance(.16)
		var initial: Transform3D = equipment.skeleton.get_bone_global_pose(hand_index)
		actor._update_model()
		check(actor.animation_player.current_animation == clip, "Locomotion cannot overwrite attack")
		check(not actor.attack(not overhead), "Repeated and competing attacks cannot interrupt the swing")
		var key := InputEventKey.new()
		key.keycode = KEY_W
		key.physical_keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		world._process(.10)
		check(actor.position == origin and not actor.walking, "Movement input is locked during the swing")
		var release := key.duplicate() as InputEventKey
		release.pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		actor.animation_player.advance(.18)
		equipment.skeleton.force_update_all_bone_transforms()
		await process_frame
		var current: Transform3D = equipment.skeleton.get_bone_global_pose(hand_index)
		check(not initial.is_equal_approx(current), "Attack animates the actual hand bones")
		check(equipment.socket.transform.is_equal_approx(current), "Sword socket follows the animated right hand")
		check(actor.position == origin, "Attack has no gameplay root drift")
		actor.animation_player.advance(1.0)
		check(not actor.attacking and actor.animation_player.current_animation == "idle", "Attack completes and returns to idle")
		Input.parse_input_event(button(event.button_index, false))
		Input.flush_buffered_events()
	check(not actor.attacking, "Button releases do not start attacks")
	for key_code in [KEY_J, KEY_K]:
		var key := InputEventKey.new()
		key.keycode = key_code
		key.pressed = true
		world._unhandled_input(key)
		check(actor.attacking, "Keyboard alternative starts an attack")
		actor.cancel_attack()
		key.echo = true
		world._unhandled_input(key)
		check(not actor.attacking, "Keyboard echo cannot start an attack")
	actor.attack()
	world._show_dialog("test", ["test"])
	world._unhandled_input(button(JOY_BUTTON_Y))
	check(not actor.attacking and world.mode == "dialog" and world.dialog_index == 0, "Dialogue cancels attacks and ignores attack buttons")
	world._close_dialog()
	for index in 9:
		actor.attack()
		world._input(button(JOY_BUTTON_B))
		check(actor.sword_combat != null and not actor.attacking, "Character switch equips sword and clears attack: " + actor.model.character_id)
		check(actor.model.find_children("SwordHandSocket", "BoneAttachment3D", true, false).size() == 1, "Replacement has exactly one sword")
		for clip in [Combat.SLASH, Combat.OVERHEAD]:
			var animation: Animation = actor.animation_player.get_animation(clip)
			check(animation != null and animation.loop_mode == Animation.LOOP_NONE, "Both one-shot attacks exist on replacement")
			actor.animation_player.play(clip, 0)
			var lowest_tip := INF
			for frame in 61:
				actor.animation_player.seek(animation.length * frame / 60.0, true)
				actor.animation_player.advance(0)
				var equipment: RefCounted = actor.sword_combat
				var sword := equipment.grip.get_node("EquippedSword") as Node3D
				var hand: Transform3D = equipment.skeleton.get_bone_global_pose(equipment.skeleton.find_bone("hand.R"))
				var tip: Vector3 = equipment.skeleton.global_transform * hand * equipment.grip.transform * sword.transform * Vector3(0, .01, .48)
				lowest_tip = minf(lowest_tip, tip.y - actor.position.y)
			check(lowest_tip >= 0.0, actor.model.character_id + ": blade stays above ground in " + clip + " (%.2f)" % lowest_tip)
		actor._update_model()
		await process_frame
	check(world.player_roster_index == roster_index, "Character switching wraps back to the original knight")
	for npc: Dictionary in world.npcs:
		check(npc.actor.find_child("SwordHandSocket", true, false) == null, "Player equipment does not modify placed NPCs")
	world._unhandled_input(button(JOY_BUTTON_LEFT_SHOULDER))
	check(world.overview, "LB retains access to the overview camera")
	world.mode = "battle"
	world._unhandled_input(button(JOY_BUTTON_X))
	check(not actor.attacking, "Exploration attacks cannot bypass turn-based battle rules")
	world.queue_free()
	await process_frame
	print("SWORD_COMBAT: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func capture() -> void:
	root.size = Vector2i(1440, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.16,.20,.25)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20,20)
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.4
	camera.position = Vector3(0,3.8,8)
	camera.look_at(Vector3(0,1.3,0))
	for overhead in [false, true]:
		var actors: Array[Node3D] = []
		var times := [0.0, .23, .44] if overhead else [0.0, .14, .30]
		for index in 3:
			var actor := Explorer.new()
			actor.model_scene = load("res://scenes/characters/tripo_roster/knight_player.tscn")
			stage.add_child(actor)
			actor.position.x = (index - 1) * 2.6
			actor.world_facing = Vector3(.15,0,1)
			actor._update_model()
			actor.set_process(false)
			actor.animation_player.play(Combat.OVERHEAD if overhead else Combat.SLASH, 0)
			actor.animation_player.seek(times[index], true)
			actor.animation_player.advance(0)
			actor.animation_player.pause()
			actors.append(actor)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/sword_attacks/" + ("overhead" if overhead else "slash") + ".png")
		for actor in actors: actor.queue_free()
		await process_frame
	stage.queue_free()
	await process_frame
