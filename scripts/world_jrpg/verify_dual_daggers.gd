extends SceneTree
## Character 002 dual daggers: equipment, clips, alternating hands, the mirrored left slash,
## the simultaneous double cut and the crossed guard.
## godot --headless --path . --script scripts/world_jrpg/verify_dual_daggers.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/dual_daggers/).
const MODEL = preload("res://scenes/characters/tripo_roster/charcter002.tscn")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
# Mirror tolerance in skeleton units (metres before the 1.35 display scale).
const MIRROR_TOLERANCE := 0.03
const CROSS_TOLERANCE := 0.03
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
	check(combat.install(model, player), "Dual daggers install on Character 002")
	check(model.find_child("EquippedDaggerR", true, false) != null and model.find_child("EquippedDaggerL", true, false) != null, "Character 002 holds a dagger in each hand")
	check(model.find_child("EquippedSword", true, false) == null and model.find_child("EquippedShield", true, false) == null, "No one-handed sword or shield")
	check(combat.guard_clip == SwordCombat.DG_GUARD and combat.overhead_clip == SwordCombat.DG_OVERHEAD, "Dual loadout can guard and double-cut")
	for clip in [SwordCombat.DG_SLASH, SwordCombat.DG_SLASH_L, SwordCombat.DG_OVERHEAD, SwordCombat.DG_GUARD]:
		check(player.has_animation(clip), "Clip exists: " + clip)
	var order := [combat.next_slash_clip(), combat.next_slash_clip(), combat.next_slash_clip()]
	check(order == [SwordCombat.DG_SLASH, SwordCombat.DG_SLASH_L, SwordCombat.DG_SLASH], "Slashes alternate right, left, right")
	check(combat.is_attack_clip(SwordCombat.DG_SLASH_L) and not combat.is_attack_clip(SwordCombat.DG_GUARD), "Left slash counts as an attack, guard does not")
	check(player.get_animation(SwordCombat.DG_SLASH).length == player.get_animation(SwordCombat.DG_SLASH_L).length, "Left slash has the right slash's timing")
	var skeleton := combat.skeleton
	var right := skeleton.find_bone(combat.rig["hand.R"])
	var left := skeleton.find_bone(combat.rig["hand.L"])
	# The auto-rig's forearms differ in length, so the hands can only mirror up to that difference.
	var forearm := func(side: String) -> float:
		return (skeleton.get_bone_global_rest(skeleton.find_bone(combat.rig["hand." + side])).origin - skeleton.get_bone_global_rest(skeleton.find_bone(combat.rig["forearm." + side])).origin).length()
	var reach_tolerance: float = absf(forearm.call("R") - forearm.call("L")) + MIRROR_TOLERANCE
	# Mirrored left slash (keyed frames; the source idle is itself asymmetric): the left dagger follows the right slash reflected across the body.
	var worst := [0.0, 0.0]
	for key: Dictionary in SwordCombat.SLASH_KEYS.filter(func(key: Dictionary) -> bool: return key.has("blade")):
		_mirror_error(worst, _blade(combat, combat._pose(key), right, combat.grip), _blade(combat, combat._pose(combat._mirror_keys([key])[0]), left, combat.off_grip))
	check(worst[0] < 2.0 and worst[1] < reach_tolerance, "Left slash mirrors the right slash (blade %.2f deg, grip %.4f)" % worst)
	# Double cut: both daggers move together, mirror images of each other.
	worst = [0.0, 0.0]
	for key: Dictionary in combat._both(SwordCombat.DG_OVERHEAD_KEYS).filter(func(key: Dictionary) -> bool: return key.has("blade")):
		var pose: Dictionary = combat._pose(key)
		_mirror_error(worst, _blade(combat, pose, right, combat.grip), _blade(combat, pose, left, combat.off_grip))
	check(worst[0] < 2.0 and worst[1] < reach_tolerance, "Double cut swings both daggers together (blade %.2f deg, grip %.4f)" % worst)
	var lowest := _blade(combat, combat._pose(combat._both(SwordCombat.DG_OVERHEAD_KEYS)[6]), right, combat.grip)
	var highest := _blade(combat, combat._pose(combat._both(SwordCombat.DG_OVERHEAD_KEYS)[4]), right, combat.grip)
	check(highest[0].y > lowest[0].y + 0.2 and lowest[1].y < lowest[0].y, "Double cut rises overhead and ends tip-down in front")
	# Guard: the two blades cross in front of the chest, the crossing on the blades rather than the handles.
	var guard: Dictionary = combat._pose(SwordCombat.DG_GUARD_KEYS[-1])
	var r := _blade(combat, guard, right, combat.grip)
	var l := _blade(combat, guard, left, combat.off_grip)
	var closest := Geometry3D.get_closest_points_between_segments(r[0], r[1], l[0], l[1])
	var gap: float = closest[0].distance_to(closest[1])
	var along: float = (closest[0] - r[0]).length() / (r[1] - r[0]).length()
	check(gap < CROSS_TOLERANCE and along > 0.2 and along < 0.95, "Guard crosses the dagger blades (gap %.4f at %.2f of the blade)" % [gap, along])
	check(r[0].x < 0.0 and l[0].x > 0.0 and r[1].x > l[1].x, "Guard blades form an X: right hand on the right, its tip to the left")
	var chest: Vector3 = combat._global(guard, skeleton.find_bone(combat.rig["spine"])).origin
	check(closest[0].z > chest.z + 0.1 and closest[0].y > chest.y, "Guard cross is raised in front of the chest")
	if capture:
		await _capture_clips(model, player)
	model.queue_free()
	await process_frame
	print("DUAL_DAGGERS: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

## Grip point and tip of one dagger in skeleton space for a pose.
func _blade(combat: RefCounted, pose: Dictionary, hand_bone: int, hand_grip: Node3D) -> Array:
	var hand: Transform3D = combat._global(pose, hand_bone) * hand_grip.transform
	return [hand.origin, hand * Vector3(0, SwordCombat.DG_GRIP.y * SwordCombat.DG_SCALE, 0)]

## Worst blade-direction angle (degrees) and grip distance between a right dagger reflected and a left dagger.
func _mirror_error(worst: Array, right: Array, left: Array) -> void:
	var flip := Vector3(-1, 1, 1)
	var angle := rad_to_deg(((right[1] - right[0]) * flip).angle_to(left[1] - left[0]))
	worst[0] = maxf(worst[0], angle)
	worst[1] = maxf(worst[1], (right[0] * flip).distance_to(left[0]))

func _capture_clips(model: Node3D, player: AnimationPlayer) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/dual_daggers"))
	var camera := Camera3D.new()
	root.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	for clip in ["idle", SwordCombat.DG_SLASH, SwordCombat.DG_SLASH_L, SwordCombat.DG_OVERHEAD, SwordCombat.DG_GUARD]:
		player.play(clip, 0)
		var length := player.get_animation(clip).length
		for step in 7:
			player.seek(length * step / 6.0, true)
			await process_frame
			# Front three-quarter and side views of the character (it faces +Z).
			for view in [["front", Vector3(1.2, 1.4, 3.2)], ["side", Vector3(3.3, 1.2, 0.2)]]:
				camera.look_at_from_position(model.global_position + view[1], model.global_position + Vector3(0, 0.85, 0))
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/dual_daggers/%s_%d_%s.png" % [clip.replace("/", "_"), step, view[0]])
