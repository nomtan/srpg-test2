extends SceneTree
## Character 001 greatsword: equipment, clips, and both hands staying on the handle.
## godot --headless --path . --script scripts/world_jrpg/verify_greatsword.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/greatsword/).
const MODEL = preload("res://scenes/characters/tripo_roster/charcter001.tscn")
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
	var capture := "--capture" in OS.get_cmdline_user_args()
	var model := MODEL.instantiate() as Node3D
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var combat := SwordCombat.new()
	check(combat.install(model, player), "Greatsword installs on Character 001")
	check(model.find_child("EquippedGreatsword", true, false) != null, "Character 001 holds the greatsword")
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
		for key: Dictionary in spec[1]:
			var pose: Dictionary = combat._pose(key)
			var shoulders: Vector3 = (combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.R"])).origin + combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.L"])).origin) * 0.5
			var wanted: Vector3 = shoulders + (key.grip as Vector3) * combat.arm_reach
			var hand: Transform3D = combat._global(pose, skeleton.find_bone(combat.rig["hand.R"]))
			var error := (hand * Vector3(0, palm, 0)).distance_to(wanted)
			check(error < REACH_TOLERANCE, "%s t=%.2f right hand reaches its key (%.4f)" % [spec[0], key.t, error])
			var handle := wanted - (key.blade as Vector3).normalized() * SwordCombat.GS_HAND_SPACING * SwordCombat.GS_SCALE
			var off_hand: Transform3D = combat._global(pose, left)
			error = (off_hand * Vector3(0, palm, 0)).distance_to(handle)
			check(error < HOLD_TOLERANCE, "%s t=%.2f left hand reaches the handle (%.4f)" % [spec[0], key.t, error])
	# Live hold: sample every clip, including the imported locomotion, with the modifier applied.
	# The modified pose is only readable while the modifier reports it has finished.
	var holder := skeleton.get_node("GreatswordTwoHandGrip") as SkeletonModifier3D
	var right := skeleton.find_bone(combat.rig["hand.R"])
	var gap := [0.0]
	holder.modification_processed.connect(func() -> void:
		var handle := skeleton.get_bone_global_pose(right) * grip.transform * Vector3(0, -SwordCombat.GS_HAND_SPACING * SwordCombat.GS_SCALE, 0)
		gap[0] = (skeleton.get_bone_global_pose(left) * Vector3(0, palm, 0)).distance_to(handle))
	for clip in ["idle", "walk", "hit", SwordCombat.GS_SWEEP, SwordCombat.GS_SMASH, SwordCombat.GS_GUARD]:
		player.play(clip, 0)
		var length := player.get_animation(clip).length
		var worst := 0.0
		var worst_time := 0.0
		for step in 25:
			var time := length * step / 24.0
			player.seek(time, true)
			await process_frame
			await process_frame
			if gap[0] > worst:
				worst = gap[0]
				worst_time = time
			if capture and step % 2 == 0:
				await _capture(model, camera, "%s_%02d" % [clip.replace("/", "_"), step])
		check(worst < HOLD_TOLERANCE, "%s keeps the left hand on the handle (worst %.4f at %.2fs)" % [clip, worst, worst_time])
	model.queue_free()
	await process_frame
	print("GREATSWORD: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _capture(model: Node3D, camera: Camera3D, file: String) -> void:
	# Front-left three-quarter view of the character (it faces +Z).
	for view in [["front", Vector3(1.6, 1.3, 3.0)], ["side", Vector3(3.3, 1.2, 0.2)]]:
		camera.look_at_from_position(model.global_position + view[1], model.global_position + Vector3(0, 0.85, 0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/greatsword/%s_%s.png" % [file, view[0]])
