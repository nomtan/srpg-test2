extends SceneTree
## Keep the first hero verified as an optional model in the sample.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const HERO = preload("res://assets/characters/meshy_hero/hero.glb")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = SAMPLE.instantiate()
	world.player_model = HERO
	root.add_child(world)
	world.set_process(false)
	var actor = world.player
	actor.set_process(false)
	var player: AnimationPlayer = actor.animation_player
	check(actor.model_scene == world.player_model and actor.model_scene.resource_path.ends_with("meshy_hero/hero.glb"), "Sample spawns the new hero GLB")
	check(player != null, "Imported AnimationPlayer exists")
	if player == null:
		quit(1)
		return
	for clip in {"idle": 2.0, "walk": 1.0, "run": 20.0 / 30.0}:
		check(player.has_animation(clip), "Imported clip: " + clip)
		if not player.has_animation(clip):
			quit(1)
			return
		var animation := player.get_animation(clip)
		var expected: float = {"idle": 2.0, "walk": 1.0, "run": 20.0 / 30.0}[clip]
		check(is_equal_approx(animation.length, expected) and animation.loop_mode == Animation.LOOP_LINEAR, "Duration and loop preserved: " + clip)
	var skeleton := actor.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check(skeleton.get_bone_count() == 26, "All 26 bones, including cape chains, imported")
	var mesh := actor.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var material := mesh.get_active_material(0) as StandardMaterial3D
	check(mesh.skin != null and material != null and material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null, "Skin and three PBR textures retained")
	player.play("idle", 0)
	player.seek(0, true)
	player.advance(0)
	var idle_pose: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		idle_pose.append(skeleton.get_bone_pose(i))
	var spawn: Vector3 = actor.position
	world.yaw = 0
	key(KEY_D, true)
	world._process(0.01)
	actor._process(0)
	player.advance(.25)
	check(player.current_animation == "walk" and actor.position.x > spawn.x, "Movement input walks and translates the hero")
	var phase := player.current_animation_position / player.current_animation_length
	key(KEY_SHIFT, true)
	world._process(0.01)
	actor._process(0)
	check(player.current_animation == "run" and is_equal_approx(player.speed_scale, 1.25), "Shift selects the dedicated run with existing sprint cadence")
	check(is_equal_approx(player.current_animation_position / player.current_animation_length, phase), "Walk-to-run keeps stride phase")
	player.advance(.2)
	player.advance(0)
	var animated_bones: Array[String] = []
	for i in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(i).is_equal_approx(idle_pose[i]):
			animated_bones.append(skeleton.get_bone_name(i))
	print("Animated bones: ", animated_bones)
	for bone in ["pelvis", "spine", "head", "upper_arm.L", "upper_arm.R", "thigh.L", "thigh.R", "shin.L", "shin.R", "cape.L", "cape.R", "cape_tip.L", "cape_tip.R"]:
		check(bone in animated_bones, "Run deforms " + bone)
	key(KEY_D, false)
	key(KEY_SHIFT, false)
	world._process(0)
	actor._process(0)
	player.advance(.2)
	player.seek(0, true)
	player.advance(0)
	check(player.current_animation == "idle", "Releasing movement returns to idle")
	var reset := true
	for i in skeleton.get_bone_count():
		reset = reset and skeleton.get_bone_pose(i).is_equal_approx(idle_pose[i])
	check(reset, "Stopping resets every bone, including run-only rotations")
	for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
		actor.world_facing = direction
		actor._process(0)
		check((actor.model.basis * Vector3.RIGHT).is_equal_approx(direction), "Facing follows movement " + str(direction))
	var location: Vector3 = actor.position
	actor.set_3d_enabled(false)
	check(actor.sprite.visible and not actor.model.visible, "2D toggle remains available")
	actor.set_3d_enabled(true)
	check(actor.model.visible and not actor.sprite.visible and actor.position == location, "3D toggle preserves position")
	if "--capture" in OS.get_cmdline_user_args():
		world.hud.visible = false
		actor.world_facing = Vector3(0, 0, 1)
		actor._process(0)
		world.yaw = .55
		world.pitch = .16
		world.distance = 5.3
		world._focus_player()
		world._update_camera()
		for clip in ["idle", "walk", "run"]:
			player.play(clip, 0)
			player.seek(.0 if clip != "walk" else .20, true)
			player.advance(0)
			player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/meshy_hero/jrpg_hero_" + clip + ".png")
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
