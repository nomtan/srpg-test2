extends SceneTree
## Validate the exported skin and look in the actual exploration scene.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
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
	root.add_child(world)
	world.set_process(false)
	var knight: Node3D = world.get_node("TripoKnightNPC")
	var adventurer: Node3D = world.get_node("AdventurerNPC")
	var origin := knight.position
	check(is_equal_approx(origin.distance_to(adventurer.position), 3.0), "Knight remains beside the adventurer")
	check(is_equal_approx(origin.y, world._surface(origin.x, origin.z) + .05), "Feet remain at terrain height")
	check(not world._can_walk(origin, origin), "NPC collision remains enabled")
	check(world.player.model_scene == world.player_model, "Controllable character uses the sample's configured model")
	var model := knight.get_node("Model")
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var body := model.find_child("Knight_Body", true, false) as MeshInstance3D
	var outline := model.find_child("Toon_Outline", true, false) as MeshInstance3D
	check(skeleton.get_bone_count() == 26, "All 26 bones imported")
	check(body != null and outline != null and body.skin != null and outline.skin != null, "Body and fine outline are both skinned")
	if body == null or outline == null:
		quit(1)
		return
	check(body.get_node(body.skeleton) == skeleton and outline.get_node(outline.skeleton) == skeleton, "Outline follows the same rig as the character")
	var toon := body.get_active_material(0) as ShaderMaterial
	check(model.get_meta("knight_toon_version", 0) == 1 and toon != null, "Godot restores the three-band Toon shader")
	if toon:
		check(toon.get_shader_parameter("base_color_texture") is Texture2D, "Toon uses the original Base Color")
	check(outline.material_override is ShaderMaterial, "Outline uses its own unshaded material")
	var player: AnimationPlayer = knight.animation_player
	check(player != null and player.current_animation == "idle", "Stationary NPC automatically plays idle")
	if player == null:
		quit(1)
		return
	for clip in {"idle": 2.0, "walk": 1.0, "run": 20.0 / 30.0}:
		check(player.has_animation(clip), "Animation imported: " + clip)
		if not player.has_animation(clip):
			quit(1)
			return
		var anim := player.get_animation(clip)
		var duration: float = {"idle": 2.0, "walk": 1.0, "run": 20.0 / 30.0}[clip]
		check(is_equal_approx(anim.length, duration) and anim.loop_mode == Animation.LOOP_LINEAR, "Duration and loop: " + clip)
		player.play(clip, 0)
		player.seek(0, true); player.advance(0)
		var start_pose: Array[Transform3D] = []
		for index in skeleton.get_bone_count(): start_pose.append(skeleton.get_bone_pose(index))
		player.seek(anim.length * .35, true); player.advance(0)
		var moving := 0
		for index in skeleton.get_bone_count():
			if not start_pose[index].is_equal_approx(skeleton.get_bone_pose(index)): moving += 1
		check(moving > 5, "Clip deforms the imported skeleton: " + clip)
		check(knight.position == origin, "Animation stays in place: " + clip)
	if "--capture" in OS.get_cmdline_user_args():
		world.hud.visible = false
		world.field_weather.controls.visible = false
		var center := (knight.position + adventurer.position) * .5 + Vector3(0, 1.15, 0)
		world.camera.position = center + Vector3(-5.0, 2.5, 7.5)
		world.camera.look_at(center)
		for clip in ["idle", "walk", "run"]:
			player.play(clip, 0)
			player.seek(0 if clip == "idle" else .25, true); player.advance(0); player.pause()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/tripo_knight/toon/godot_" + clip + ".png")
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
