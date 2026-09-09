extends SceneTree
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := Explorer.new()
	root.add_child(actor)
	actor.set_process(false)
	check(actor.use_3d and actor.model.visible and not actor.sprite.visible, "3D is default; original sprite remains available")
	var player: AnimationPlayer = actor.animation_player
	check(player != null and player.has_animation("walk") and player.has_animation("run"), "Source walk and run clips imported")
	check(is_equal_approx(player.get_animation("walk").length, 0.8) and is_equal_approx(player.get_animation("run").length, 0.6), "Original clip durations preserved")
	actor.walking = true
	actor._process(0)
	check(player.current_animation == "walk", "Walking selects walk")
	player.advance(0.2)
	player.advance(0)
	var head: Node3D = actor.model.find_child("ganmen", true, false)
	var walk_head := head.transform
	actor.running = true
	actor._process(0)
	player.advance(0.2)
	player.advance(0)
	check(player.current_animation == "run" and head.transform != walk_head, "Running selects original run pose")
	actor.walking = false
	actor._process(0)
	player.advance(0.2)
	player.advance(0)
	check(player.current_animation == "idle" and head.rotation.is_zero_approx(), "Stopping resets run-only head rotation")
	actor.world_facing = Vector3.FORWARD
	actor._process(0)
	check((actor.model.basis * Vector3.RIGHT).is_equal_approx(Vector3.FORWARD), "3D model faces world movement direction")
	var location := actor.position
	actor.set_3d_enabled(false)
	check(actor.sprite.visible and not actor.model.visible and actor.position == location, "2D switch preserves gameplay position")
	actor.walking = true
	actor.running = true
	actor.set_3d_enabled(true)
	check(actor.model.visible and not actor.sprite.visible and player.current_animation == "run", "Returning to 3D restores current locomotion")
	actor.free()
	var sprite_actor := Explorer.new()
	sprite_actor.use_3d = false
	root.add_child(sprite_actor)
	check(sprite_actor.sprite.visible and not sprite_actor.model.visible and not sprite_actor.animation_player.is_playing(), "Can start in original 2D mode")
	sprite_actor.free()
	if "--capture" in OS.get_cmdline_user_args():
		await capture()
	quit(1 if failed else 0)

func capture() -> void:
	root.size = Vector2i(1200, 700)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("c6d7e0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	scene.add_child(light)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.position = Vector3(5, 4, 9)
	camera.look_at(Vector3(0, 1, 0))
	for i in 4:
		var sample := Explorer.new()
		scene.add_child(sample)
		sample.set_process(false)
		sample.position.x = (i - 1.5) * 2.3
		sample.walking = i in [1, 2]
		sample.running = i == 2
		sample.world_facing = Vector3(0, 0, 1)
		sample._process(0)
		sample.animation_player.play(["idle", "walk", "run", "idle"][i], 0)
		sample.animation_player.seek(0.15, true)
		sample.animation_player.pause()
		if i == 3: sample.set_3d_enabled(false)
		var label := Label3D.new()
		label.text = ["IDLE", "WALK", "RUN", "2D"][i]
		label.position = sample.position + Vector3(0, 2.8, 0)
		label.font_size = 50
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		scene.add_child(label)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/world_jrpg/explorer_preview.png")
	scene.queue_free()
	await process_frame
