extends SceneTree
## Character 006 bow: equipment, clips, both hands on their marks, the nocked arrow's aim and the loosed arrow's flight.
## godot --headless --path . --script scripts/world_jrpg/verify_bow.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/bow/).
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const BowShotFxScript = preload("res://scripts/world_jrpg/bow_shot_fx.gd")
const MODEL = preload("res://scenes/characters/tripo_roster/charcter006.tscn")
# Palm-to-key distance tolerated, in skeleton units (metres before the 1.35 display scale).
const REACH_TOLERANCE := 0.02
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var model := MODEL.instantiate() as Node3D
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var combat := SwordCombat.new()
	check(combat.install(model, player), "Bow installs on Character 006")
	check(model.find_child("EquippedBow", true, false) != null, "Character 006 holds the bow")
	check(model.find_child("EquippedSword", true, false) == null and model.find_child("EquippedShield", true, false) == null, "No sword or shield")
	check(combat.slash_clip == SwordCombat.BW_SHOT and combat.overhead_clip == SwordCombat.BW_ARC and combat.guard_clip == SwordCombat.BW_GUARD, "Bow loadout shoots, arcs and guards")
	check(combat.is_attack_clip(SwordCombat.BW_ARC) and not combat.is_attack_clip(SwordCombat.BW_GUARD), "Both shots count as attacks, guard does not")
	for clip in [SwordCombat.BW_SHOT, SwordCombat.BW_ARC, SwordCombat.BW_GUARD]:
		check(player.has_animation(clip), "Clip exists: " + clip)
	var skeleton := combat.skeleton
	var palm: float = combat.rig["palm"]
	var left := skeleton.find_bone(combat.rig["hand.L"])
	var right := skeleton.find_bone(combat.rig["hand.R"])
	# Keyed reach: each palm must arrive where each key asks for it.
	for spec in [[SwordCombat.BW_SHOT, SwordCombat.BW_SHOT_KEYS], [SwordCombat.BW_ARC, SwordCombat.BW_ARC_KEYS], [SwordCombat.BW_GUARD, SwordCombat.BW_GUARD_KEYS]]:
		for raw: Dictionary in spec[1]:
			var key: Dictionary = SwordCombat.BW_READY.merged(raw) if raw.get("ready", false) else raw
			var pose: Dictionary = combat._pose(key)
			var shoulders: Vector3 = combat._shoulders(pose)
			var bow_point: Vector3 = shoulders + (key.bow as Vector3) * combat.arm_reach
			var error := (combat._global(pose, left) * Vector3(0, palm, 0)).distance_to(bow_point)
			check(error < REACH_TOLERANCE, "%s t=%.2f left hand holds the bow at its key (%.4f)" % [spec[0], key.t, error])
			if key.has("draw"):
				error = (combat._global(pose, right) * Vector3(0, palm, 0)).distance_to(shoulders + (key.draw as Vector3) * combat.arm_reach)
				check(error < REACH_TOLERANCE, "%s t=%.2f right hand draws to its key (%.4f)" % [spec[0], key.t, error])
	var fx := model.get_node("BowShotFx")
	var held := fx.get_node("NockedArrow") as Node3D
	var camera: Camera3D
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/bow"))
		camera = Camera3D.new()
		root.add_child(camera)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, 30, 0)
		root.add_child(light)
	# Frozen so each sample stays at its seek time (slow capture frames would otherwise run clips to the end).
	player.speed_scale = 0.0
	for clip in ["idle", "walk", SwordCombat.BW_SHOT, SwordCombat.BW_ARC, SwordCombat.BW_GUARD]:
		player.play(clip, 0)
		var length := player.get_animation(clip).length
		for step in 21:
			var time := length * step / 20.0
			player.seek(time, true)
			await process_frame
			await process_frame
			if capture and step % 2 == 0:
				await _capture(model, camera, "%s_%02d" % [clip.replace("/", "_"), step])
		if clip == "idle":
			var holder := skeleton.get_node("BowReadyGrip") as SkeletonModifier3D
			check(holder.ready_weight >= 1.0 and model.find_child("EquippedBow", true, false).is_visible_in_tree(), "Idle holds the bow low at the side")
			check(not held.visible, "No arrow is nocked outside the shots")
	# Full draw: the nocked arrow points down the line of fire (the character faces +Z).
	for spec in [[SwordCombat.BW_SHOT, 0.3, Vector3(0, 0, 1), 0.9], [SwordCombat.BW_ARC, 0.5, Vector3(0, 0.6, 0.8), 0.85]]:
		player.play(spec[0], 0)
		player.seek(spec[1], true)
		await process_frame
		await process_frame
		var aim: Vector3 = held.global_basis.y.normalized()
		check(held.visible and aim.dot(spec[2]) > spec[3], "%s aims the nocked arrow along %s (%s)" % [spec[0], spec[2], aim])
		check(not fx.get_node("BowString1").global_position.is_equal_approx(fx.get_node("BowString0").global_position), "%s draws the string" % spec[0])
	# Loose at full speed: the arrow leaves the bow and flies forward. Arrows loosed while stepping above expire first.
	await create_timer(BowShotFxScript.FLIGHT_TIME + 0.2).timeout
	check(fx.get_node_or_null("LoosedArrow") == null, "Loosed arrows expire after their flight")
	player.speed_scale = 1.0
	player.play(SwordCombat.BW_SHOT, 0)
	player.seek(0.3, true)
	var flying: Node3D
	for frame in 60:
		await process_frame
		flying = fx.get_node_or_null("LoosedArrow") as Node3D
		if flying: break
	check(flying != null, "The shot looses an arrow")
	if flying:
		var start := flying.global_position
		for frame in 6: await process_frame
		check(flying.global_position.z - start.z > 0.3, "The loosed arrow flies forward (%.2f)" % (flying.global_position.z - start.z))
		check(not held.visible, "The hand is empty after the release")
	model.queue_free()
	await process_frame
	print("BOW: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _capture(model: Node3D, camera: Camera3D, file: String) -> void:
	for view in [["front", Vector3(1.6, 1.3, 3.0)], ["side", Vector3(3.3, 1.2, 0.2)], ["back", Vector3(-2.6, 1.5, -2.2)]]:
		camera.look_at_from_position(model.global_position + view[1], model.global_position + Vector3(0, 0.85, 0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/bow/%s_%s.png" % [file, view[0]])
