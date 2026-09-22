extends SceneTree
## Import, animation, material, face-swap and placement checks in the actual sample.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
var failed := false

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 1000)
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	var actors: Array[Node3D] = []
	for item: Dictionary in world.npcs:
		if item.actor.get_script() == load("res://scripts/character/tripo_roster_character.gd"):
			actors.append(item.actor)
	check(actors.size() == 9, "All nine requested Tripo characters are placed")
	check(world.player.model_scene == world.player_model, "Player uses the requested knight2 model")
	var known_ids := {}
	for actor in actors:
		var key: String = actor.character_id
		known_ids[key] = true
		check(not actor.display_name.contains("?"), key + ": Japanese label is intact")
		var origin := actor.position
		check(is_equal_approx(origin.y, world._surface(origin.x, origin.z) + 0.05), key + ": placed at terrain height")
		check(not world._can_walk(origin, origin), key + ": NPC collision is enabled")
		var model := actor.get_node("Model")
		check(model.get_meta("tripo_roster_version", 0) == 1, key + ": Toon import hook ran")
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		check(skeleton != null and skeleton.get_bone_count() == 26, key + ": 26-bone skeleton")
		if skeleton == null:
			continue
		check(actor.face_socket != null and actor.face_socket.bone_name == "head", key + ": head attachment socket")
		for part in ["Body", "Head_Shell", "Face_Default", "Body_Outline", "Head_Shell_Outline", "Face_Outline"]:
			var mesh := model.find_child(part, true, false) as MeshInstance3D
			check(mesh != null and mesh.skin != null, key + ": skinned " + part)
			if mesh == null:
				continue
			check(mesh.get_node(mesh.skeleton) == skeleton, key + ": shared skeleton for " + part)
			var material := mesh.get_active_material(0) as ShaderMaterial
			check(material != null, key + ": shader on " + part)
			if material and not part.ends_with("_Outline"):
				check(material.get_shader_parameter("base_color_texture") is Texture2D, key + ": original Base Color on " + part)
		var player: AnimationPlayer = actor.animation_player
		check(player != null and player.current_animation == "idle", key + ": automatically plays idle")
		if player == null:
			continue
		for clip in ["idle", "walk", "run"]:
			check(player.has_animation(clip), key + ": animation " + clip)
			if not player.has_animation(clip):
				continue
			var animation := player.get_animation(clip)
			var duration: float = {"idle": 2.0, "walk": 1.0, "run": 20.0 / 30.0}[clip]
			check(animation.loop_mode == Animation.LOOP_LINEAR and is_equal_approx(animation.length, duration), key + ": loop and duration " + clip)
			player.play(clip, 0)
			player.seek(0, true); player.advance(0)
			var initial: Array[Transform3D] = []
			for index in skeleton.get_bone_count(): initial.append(skeleton.get_bone_pose(index))
			player.seek(animation.length * .35, true); player.advance(0)
			var changed := 0
			for index in skeleton.get_bone_count():
				if not initial[index].is_equal_approx(skeleton.get_bone_pose(index)): changed += 1
			check(changed > 5 and actor.position == origin, key + ": in-place animated skeleton " + clip)
		player.play("idle", 0)
		var face: MeshInstance3D = actor.face
		var body := actor.find_child("Body", true, false) as MeshInstance3D
		var old_material := face.get_active_material(0)
		var body_material := body.get_active_material(0)
		var old_skin := face.skin
		var old_mesh := face.mesh
		var color := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		color.fill(Color.CORAL)
		var texture := ImageTexture.create_from_image(color)
		check(actor.set_face_texture(texture), key + ": texture replacement API")
		check(face.get_active_material(0) != old_material and body.get_active_material(0) == body_material, key + ": face texture edit leaves clothing unchanged")
		actor.reset_face()
		check(face.get_active_material(0) == old_material, key + ": restores original face texture")
		var model_path: String = model.scene_file_path
		var variant_path := model_path.get_base_dir().path_join("face_default.glb")
		var variant := load(variant_path) as PackedScene
		check(actor.set_face_variant(variant), key + ": standalone face GLB replacement")
		player.seek(.5, true); player.advance(0)
		check(face.get_node(face.skeleton) == skeleton, key + ": replaced face follows live skeleton")
		actor.reset_face()
		check(face.mesh == old_mesh and face.skin == old_skin, key + ": reset restores original mesh and bind skin")
	check(known_ids.size() == 9, "Nine distinct source models")
	# Reachability matters as well as visibility: leave room to approach every NPC.
	var reached := {Vector2i(64, 120): true}
	var pending: Array[Vector2i] = [Vector2i(64, 120)]
	var cursor := 0
	while cursor < pending.size():
		var point := pending[cursor]
		cursor += 1
		var from := Vector3(point.x * .5, world._surface(point.x * .5, point.y * .5) + .05, point.y * .5)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + direction
			if next.x < 40 or next.x > 80 or next.y < 90 or next.y > 130 or reached.has(next):
				continue
			var to := Vector3(next.x * .5, world._surface(next.x * .5, next.y * .5) + .05, next.y * .5)
			if world._can_walk(to, from):
				reached[next] = true
				pending.append(next)
	for actor in actors:
		var approachable := false
		for point: Vector2i in reached:
			var nearby := Vector3(point.x * .5, world._surface(point.x * .5, point.y * .5) + .05, point.y * .5)
			if nearby.distance_to(actor.position) < 2.2:
				approachable = true
				break
		check(approachable, actor.character_id + ": reachable from the player spawn")
	if "--capture" in OS.get_cmdline_user_args():
		world.hud.visible = false
		world.field_weather.controls.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/tripo_roster/godot_start.png")
		var center := Vector3(28.1, world._surface(28.1, 53.4) + 1.0, 53.4)
		world.camera.position = center + Vector3(-9, 10, 16)
		world.camera.look_at(center)
		for clip in ["idle", "walk", "run"]:
			for actor in actors:
				actor.animation_player.play(clip, 0)
				actor.animation_player.seek(0 if clip == "idle" else .25, true)
				actor.animation_player.advance(0)
				actor.animation_player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/tripo_roster/godot_" + clip + ".png")
	world.queue_free()
	await process_frame
	print("TRIPO_ROSTER_VALIDATION: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
