extends SceneTree
## Import, identity isolation, expression, NPC placement, and locomotion checks.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const NPC = preload("res://scenes/characters/adventurer_npc.tscn")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func meshes(part: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if part is MeshInstance3D:
		result.append(part)
	for child in part.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/meshy_adventure/" + path + ".png")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	await process_frame
	var npc := world.get_node("AdventurerNPC") as AdventurerCharacter
	check(npc != null, "Separate adventurer NPC spawned in actual exploration sample")
	if npc == null:
		quit(1)
		return
	check(world.player != npc and world.player.model_scene.resource_path.ends_with("meshy_hero2/hero2.glb"), "Existing controllable hero unchanged")
	var spawn := npc.position
	check(spawn.distance_to(world.player.position) > 1 and spawn.distance_to(world.player.position) < 4, "NPC stands near the start without overlapping player")
	check(is_equal_approx(spawn.y, world._surface(spawn.x, spawn.z) + .05), "NPC feet placed on terrain")
	check(not world._can_walk(spawn, spawn), "NPC participates in existing collision avoidance")
	check(world.npcs[0].actor == npc and world.npcs[0].data.id == "adventurer", "NPC uses existing interaction/dialogue system")
	var body := npc.body
	var body_mesh := meshes(body)[0]
	check(meshes(body).size() == 1 and meshes(npc.face).size() == 1 and meshes(npc.hair).size() == 1, "Each GLB contains only its requested part")
	for part in [npc.body, npc.face, npc.hair]:
		var material := meshes(part)[0].get_active_material(0) as ShaderMaterial
		check(material != null and material.get_shader_parameter("base_color_texture") is Texture2D, "Original texture and cel shader: " + str(part.name))
	var other := NPC.instantiate() as AdventurerCharacter
	other.appearance = npc.appearance
	root.add_child(other)
	other.visible = false
	await process_frame
	check(meshes(other.body)[0].mesh == body_mesh.mesh, "Characters reuse the same job-body mesh resource")
	check(other.appearance != npc.appearance, "Character recipes are independent even with a shared preset")
	for expression in ["smile", "blink", "angry", "neutral"]:
		check(npc.set_expression(expression), "Expression available: " + expression)
		var face_mesh := meshes(npc.face)[0]
		for i in face_mesh.mesh.get_blend_shape_count():
			var expected := 1.0 if str(face_mesh.mesh.get_blend_shape_name(i)).to_lower() == expression else 0.0
			check(is_equal_approx(face_mesh.get_blend_shape_value(i), expected), "Expression morph resets correctly: " + str(face_mesh.mesh.get_blend_shape_name(i)))
	check(not npc.set_expression("missing") and not npc.set_hairstyle("missing"), "Unsupported appearance values fail without replacing parts")
	check(npc.set_hairstyle("swept"), "Second hairstyle can be selected")
	await process_frame
	check(npc.body == body and npc.position == spawn, "Hair swap preserves shared body and world position")
	check(other.appearance.hair_scene != npc.appearance.hair_scene and other.current_expression == "neutral", "Appearance changes do not affect another character")
	check(npc.set_face(npc.appearance.face_scene), "Face is independently replaceable")
	await process_frame
	check(npc.body == body and npc.set_expression("smile"), "Face replacement preserves body and expression control")
	var original_body_material := body_mesh.get_active_material(0)
	var identity_texture := GradientTexture2D.new()
	check(npc.set_face(npc.appearance.face_scene, identity_texture), "Per-character face texture can be replaced")
	await process_frame
	check(meshes(npc.face)[0].get_active_material(0).get_shader_parameter("base_color_texture") == identity_texture and body_mesh.get_active_material(0) == original_body_material, "Face identity edit leaves body material intact")
	npc.set_face(npc.appearance.face_scene)
	await process_frame
	npc.set_expression("neutral")
	npc.set_hairstyle("tousled")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	var player_start: Vector3 = world.player.position
	world._process(.02)
	event = InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	world._process(0)
	check(world.player.position != player_start and npc.position == spawn, "Movement input controls hero while adventurer stays still")
	world.player.position = player_start
	var jobs := JobDatabase.new()
	root.add_child(jobs)
	check(jobs.get_job("adventurer").job_name == "冒険者" and jobs.get_job("adventurer").body_scene_path == npc.BODY.resource_path, "Adventure body registered to adventurer job")
	if "--capture" in OS.get_cmdline_user_args():
		world._focus_player()
		world._update_camera()
		await capture("game_start")
		world.hud.visible = false
		world.field_weather.controls.visible = false
		world.camera.position = npc.position + Vector3(-.15, 1.7, 4.8)
		world.camera.look_at(npc.position + Vector3(0, 1.15, 0))
		npc.rotation.y = 0
		for expression in ["neutral", "smile", "blink", "angry"]:
			npc.set_expression(expression)
			await capture("face_" + expression)
		npc.set_expression("neutral")
		npc.set_hairstyle("swept")
		await capture("hair_swept")
	other.queue_free()
	jobs.queue_free()
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
