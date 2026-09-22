extends SceneTree
## Verify the previously used paladin as an optional model in the sample.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const PALADIN = preload("res://assets/characters/meshy_paladin/blue_plume_paladin.glb")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = SAMPLE.instantiate()
	world.player_model = PALADIN
	root.add_child(world)
	world.set_process(false)
	var actor = world.player
	actor.set_process(false)
	var player: AnimationPlayer = actor.animation_player
	check(actor.model_scene == world.player_model and actor.model.visible, "Sample spawns the configured Meshy model")
	check(actor.model_scene.resource_path.ends_with("blue_plume_paladin.glb"), "Sample uses the paladin GLB")
	check(player.has_animation("idle") and player.has_animation("walk"), "Idle and walk import successfully")
	check(is_equal_approx(player.get_animation("walk").length, 32.0 / 24.0), "Walk keeps its original loop duration")
	var skeleton := actor.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check(skeleton.get_bone_count() == 24, "All 24 bones are imported")
	var mesh := actor.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var material := mesh.get_active_material(0) as StandardMaterial3D
	check(mesh.skin != null and material != null and material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null, "Skin and color / normal / roughness textures are retained")
	player.advance(0)
	var foot := skeleton.find_bone("foot.L")
	var idle_foot := skeleton.get_bone_pose(foot)
	actor.walking = true
	actor.locomotion_speed = 4.5
	actor._process(0)
	player.advance(0.35)
	player.advance(0)
	check(player.current_animation == "walk" and skeleton.get_bone_pose(foot) != idle_foot, "Movement animates the skeleton")
	var phase := player.current_animation_position
	actor.running = true
	actor.locomotion_speed = 16.0
	actor._process(0)
	check(player.current_animation == "walk" and is_equal_approx(player.speed_scale, 1.25), "Sprint reuses the walk at the existing moderate cadence")
	check(is_equal_approx(player.current_animation_position, phase), "Sprint does not restart the walk")
	actor.walking = false
	actor.running = false
	actor._process(0)
	player.advance(0.2)
	player.advance(0)
	check(player.current_animation == "idle" and skeleton.get_bone_pose(foot).is_equal_approx(idle_foot), "Stopping returns the feet to the planted idle pose")
	for direction in [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
		actor.world_facing = direction
		actor._process(0)
		check((actor.model.basis * Vector3.RIGHT).is_equal_approx(direction), "Model faces movement " + str(direction))
	var location: Vector3 = actor.position
	actor.set_3d_enabled(false)
	check(actor.sprite.visible and not actor.model.visible, "Original 2D mode still works")
	actor.set_3d_enabled(true)
	check(actor.model.visible and not actor.sprite.visible and actor.position == location, "Returning to the paladin preserves position")
	if "--capture" in OS.get_cmdline_user_args():
		world.hud.visible = false
		world.player.world_facing = Vector3(0, 0, 1)
		actor._process(0)
		world.yaw = 0.55
		world.pitch = 0.22
		world.distance = 7.0
		world._focus_player()
		world._update_camera()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/meshy_paladin/jrpg_world_paladin.png")
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
