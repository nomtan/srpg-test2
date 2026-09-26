extends SceneTree
## End-to-end import and BattleUnit integration, with an optional rendered map.
var failed := false
var actors: Array[BattleUnit] = []

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok:
		failed = true

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 900)
	var world := Node3D.new()
	root.add_child(world)
	var previous_skeleton: Skeleton3D
	var previous_player: AnimationPlayer
	for id in ["001", "002", "003"]:
		var path := "res://assets/characters/generated/charcter%s/character.glb" % id
		var packed := load(path) as PackedScene
		check(packed != null, id + " PackedScene imported")
		if packed == null:
			continue
		var standalone := packed.instantiate()
		check(standalone != null, id + " standalone instantiate")
		standalone.free()
		var actor := BattleUnit.new()
		actor.configure("charcter" + id, "Character " + id, Vector2i(3 + actors.size() * 2, 3), "player")
		world.add_child(actor)
		actor.setup_visual(path)
		actors.append(actor)
		var skeletons := actor.find_children("*", "Skeleton3D", true, false)
		check(skeletons.size() == 1, id + " exactly one Skeleton3D")
		if skeletons.size() != 1:
			continue
		var sk := skeletons[0] as Skeleton3D
		check(sk.get_bone_count() == 65 and sk.find_bone("head") >= 0, id + " 65 bones and head")
		for part in ["Body", "Head"]:
			var mesh := actor.find_child(part, true, false) as MeshInstance3D
			check(mesh != null and mesh.skin != null and mesh.get_node(mesh.skeleton) == sk, id + " " + part + " bound to shared skeleton")
			if mesh != null:
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as ShaderMaterial
					check(material != null and material.shader == preload("res://assets/characters/_shared/materials/character_toon.gdshader"), id + " " + part + " shared toon shader surface " + str(surface))
					check(material != null and material.get_shader_parameter("base_color_texture") != null, id + " " + part + " original texture retained surface " + str(surface))
		var player := actor.animation_player
		check(player != null and player.current_animation == "idle", id + " BattleUnit automatically plays idle")
		if player == null:
			continue
		for clip in ["idle", "walk", "attack", "hit"]:
			check(player.has_animation(clip), id + " clip " + clip)
			if not player.has_animation(clip):
				continue
			var anim := player.get_animation(clip)
			check(anim.loop_mode == (Animation.LOOP_LINEAR if clip in ["idle", "walk"] else Animation.LOOP_NONE), id + " loop policy " + clip)
			var origin := actor.transform
			player.play(clip, 0)
			player.seek(0, true)
			player.advance(0)
			var head_start := sk.get_bone_global_pose(sk.find_bone("head"))
			player.seek(anim.length * .35, true)
			player.advance(0)
			check(not head_start.is_equal_approx(sk.get_bone_global_pose(sk.find_bone("head"))), id + " head animates " + clip)
			check(actor.transform.is_equal_approx(origin) and actor.model_instance.position.is_zero_approx(), id + " no root motion " + clip)
		if previous_skeleton:
			for bone in sk.get_bone_count():
				check(sk.get_bone_name(bone) == previous_skeleton.get_bone_name(bone) and sk.get_bone_rest(bone).is_equal_approx(previous_skeleton.get_bone_rest(bone)), "shared rest " + sk.get_bone_name(bone))
			# Play the actual first character's Animation resources on the second.
			for clip in ["idle", "walk", "attack", "hit"]:
				var library := player.get_animation_library("")
				library.remove_animation(clip)
				library.add_animation(clip, previous_player.get_animation(clip))
				player.play(clip, 0)
				previous_player.play(clip, 0)
				for fraction in [0.0, .25, .5, .75, 1.0]:
					var time: float = player.get_animation(clip).length * fraction
					player.seek(time, true); player.advance(0)
					previous_player.seek(time, true); previous_player.advance(0)
					var matches := true
					for bone in sk.get_bone_count():
						matches = matches and sk.get_bone_pose(bone).is_equal_approx(previous_skeleton.get_bone_pose(bone))
					check(matches, "Shared animation reused: %s %.2f" % [clip, fraction])
		previous_skeleton = sk
		previous_player = player
	# Use the real battle grid/terrain renderer and BattleUnit visual path.
	var grid := GridSystem.new()
	world.add_child(grid)
	grid.generate_grid()
	for key in grid.cells.keys():
		if key.x >= 10 or key.y >= 8:
			grid.cells.erase(key)
	var terrain := VoxelMap.new()
	world.add_child(terrain)
	terrain.build_from_grid(grid)
	for actor in actors:
		actor.position = grid.grid_to_world(Vector2i(actor.grid_x, actor.grid_z))
		check(actor.position == grid.grid_to_world(Vector2i(actor.grid_x, actor.grid_z)), actor.unit_id + " placed on battle grid")
		actor.animation_player.play("idle", 0)
		actor.animation_player.seek(0, true)
		actor.animation_player.pause()
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.2
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.15, .18, .23)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .6
	world.add_child(env)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CameraController.DEFAULT_CAMERA_SIZE
	var center := (actors[0].position + actors[2].position) * .5 + Vector3.UP * .6
	cam.position = center + Vector3(7, 9, 12)
	cam.look_at(center)
	cam.current = true
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/character_batch/godot_battle_distance.png")
		cam.size = 7
		for clip in ["idle", "walk", "attack", "hit"]:
			for actor in actors:
				actor.animation_player.play(clip, 0)
				actor.animation_player.seek(actor.animation_player.get_animation(clip).length * .35, true)
				actor.animation_player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/character_batch/godot_" + clip + ".png")
	world.queue_free()
	await process_frame
	print("CHARACTER_BATCH_VALIDATION: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
