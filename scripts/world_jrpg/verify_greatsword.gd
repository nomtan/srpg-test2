extends SceneTree
## Character 001 greatsword: equipment, clips, and both hands staying on the handle.
## godot --headless --path . --script scripts/world_jrpg/verify_greatsword.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/greatsword/).
## Character 005's two-handed axe shares the clips: append -- --character 005.
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
# Hand-to-handle distance tolerated, in skeleton units (metres before the 1.35 display scale).
const HOLD_TOLERANCE := 0.012
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
	var args := OS.get_cmdline_user_args()
	var capture := "--capture" in args
	var id := args[args.find("--character") + 1] if "--character" in args else "001"
	var model := (load("res://scenes/characters/tripo_roster/charcter%s.tscn" % id) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var combat := SwordCombat.new()
	check(combat.install(model, player), "Two-handed weapon installs on Character " + id)
	var weapon := "EquippedGreataxe" if id == "005" else "EquippedGreatsword"
	check(model.find_child(weapon, true, false) != null, "Character %s holds %s" % [id, weapon])
	check(model.find_child("EquippedSword", true, false) == null and model.find_child("EquippedShield", true, false) == null, "No one-handed sword or shield")
	check(combat.two_handed and combat.guard_clip == SwordCombat.GS_GUARD, "Two-handed loadout can guard")
	for clip in [SwordCombat.GS_SWEEP, SwordCombat.GS_SMASH, SwordCombat.GS_GUARD]:
		check(player.has_animation(clip), "Clip exists: " + clip)
	var skeleton := combat.skeleton
	var grip := combat.grip
	var palm: float = combat.rig["palm"]
	var left := skeleton.find_bone(combat.rig["hand.L"])
	var camera: Camera3D
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/greatsword"))
		camera = Camera3D.new()
		root.add_child(camera)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, 30, 0)
		root.add_child(light)
	# Keyed reach: the right palm must arrive where each key asks for it.
	for spec in [[SwordCombat.GS_SWEEP, SwordCombat.GS_SWEEP_KEYS], [SwordCombat.GS_SMASH, SwordCombat.GS_SMASH_KEYS], [SwordCombat.GS_GUARD, SwordCombat.GS_GUARD_KEYS]]:
		for raw: Dictionary in spec[1]:
			var key := SwordCombat.gs_key(raw)
			var pose: Dictionary = combat._pose(key)
			var shoulders: Vector3 = (combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.R"])).origin + combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.L"])).origin) * 0.5
			var wanted: Vector3 = shoulders + (key.grip as Vector3) * combat.arm_reach
			var hand: Transform3D = combat._global(pose, skeleton.find_bone(combat.rig["hand.R"]))
			var error := (hand * Vector3(0, palm, 0)).distance_to(wanted)
			check(error < REACH_TOLERANCE, "%s t=%.2f right hand reaches its key (%.4f)" % [spec[0], key.t, error])
			if key.get("one_hand", false): continue
			var handle := wanted - (key.blade as Vector3).normalized() * SwordCombat.GS_HAND_SPACING
			var off_hand: Transform3D = combat._global(pose, left)
			error = (off_hand * Vector3(0, palm, 0)).distance_to(handle)
			check(error < HOLD_TOLERANCE, "%s t=%.2f left hand reaches the handle (%.4f)" % [spec[0], key.t, error])
	# Live hold: sample every clip, including the imported locomotion, with the modifier applied.
	# The modified pose is only readable while the modifier reports it has finished.
	var holder := skeleton.get_node("GreatswordTwoHandGrip") as SkeletonModifier3D
	var right := skeleton.find_bone(combat.rig["hand.R"])
	# Per frame: left-hand gap to the handle while gripping two-handed, and right-hand miss from the shouldered stance while carrying.
	var gap := [0.0, 0.0]
	holder.modification_processed.connect(func() -> void:
		var handle := skeleton.get_bone_global_pose(right) * grip.transform * Vector3(0, -SwordCombat.GS_HAND_SPACING, 0)
		gap[0] = (skeleton.get_bone_global_pose(left) * Vector3(0, palm, 0)).distance_to(handle) if holder.two_hand_weight >= 1.0 else 0.0
		var shoulders := (skeleton.get_bone_global_pose(skeleton.find_bone(combat.rig["upper_arm.R"])).origin + skeleton.get_bone_global_pose(skeleton.find_bone(combat.rig["upper_arm.L"])).origin) * 0.5
		var carried := shoulders + (SwordCombat.GS_READY.grip as Vector3) * combat.arm_reach
		gap[1] = (skeleton.get_bone_global_pose(right) * Vector3(0, palm, 0)).distance_to(carried) if holder.ready_weight >= 1.0 else 0.0)
	# Frozen so each sample stays at its seek time (slow capture frames would otherwise run clips to the end).
	player.speed_scale = 0.0
	for clip in ["idle", "walk", "hit", SwordCombat.GS_SWEEP, SwordCombat.GS_SMASH, SwordCombat.GS_GUARD]:
		player.play(clip, 0)
		var length := player.get_animation(clip).length
		var worst := 0.0
		var worst_time := 0.0
		var worst_carry := 0.0
		for step in 25:
			var time := length * step / 24.0
			player.seek(time, true)
			await process_frame
			await process_frame
			if gap[0] > worst:
				worst = gap[0]
				worst_time = time
			worst_carry = maxf(worst_carry, gap[1])
			if capture and step % 2 == 0:
				await _capture(model, camera, "%s_%02d" % [clip.replace("/", "_"), step])
		check(worst < HOLD_TOLERANCE, "%s keeps the left hand on the handle while gripping (worst %.4f at %.2fs)" % [clip, worst, worst_time])
		check(worst_carry < REACH_TOLERANCE, "%s keeps the sword on the shoulder while carrying (worst %.4f)" % [clip, worst_carry])
		if clip in ["idle", "walk"]:
			var crouched: bool = holder.idle_weight > 0.99
			check(crouched == (clip == "idle"), "%s %s the half crouch" % [clip, "holds" if clip == "idle" else "keeps its own legs, without"])
	for spec in [[SwordCombat.GS_SWEEP, 0.0, 0.0], [SwordCombat.GS_SWEEP, 0.34, 1.0], [SwordCombat.GS_SMASH, 0.39, 1.0], [SwordCombat.GS_SMASH, 0.85, 0.0], [SwordCombat.GS_GUARD, 0.14, 1.0]]:
		check(is_equal_approx(combat.two_hand_weight(spec[0], spec[1]), spec[2]), "%s t=%.2f grips with %s" % [spec[0], spec[1], "both hands" if spec[2] > 0 else "the right hand only"])
	model.queue_free()
	await process_frame
	print("GREATSWORD: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _capture(model: Node3D, camera: Camera3D, file: String) -> void:
	# Front-left three-quarter view of the character (it faces +Z).
	for view in [["front", Vector3(1.6, 1.3, 3.0)], ["side", Vector3(3.3, 1.2, 0.2)]]:
		camera.look_at_from_position(model.global_position + view[1], model.global_position + Vector3(0, 0.85, 0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/greatsword/%s_%s_%s.png" % [model.get("character_id"), file, view[0]])
