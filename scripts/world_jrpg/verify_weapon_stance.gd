extends SceneTree
## Dual daggers, greatsword and greataxe set up like the sword and shield: their own stance, walk and run
## (SwordGait.install_loadout) held without the grip modifier's ready stance, attack clips that start from and end in the
## stance, ink slash arcs, and a freeze only when a blow connects (hit_slow, with each weapon's own hold and burst size).
## The katana: ink arcs and contact-only freezes too, a breathing stance and the gait with the left hand on the scabbard.
## godot --headless --path . --script scripts/world_jrpg/verify_weapon_stance.gd
## Rendered views: tools/asset_gen/character_pipeline/capture_weapon_gait.gd.
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const INK = preload("res://assets/fx/sword_slash/sword_slash_ink.tres")
const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
# [loadout, character, hold range in seconds, burst scale range]
const CASES := [
	["dual_daggers", "charcter002", Vector2(0.08, 0.14), Vector2(0.7, 1.0)],
	["greatsword", "charcter001", Vector2(0.18, 0.25), Vector2(1.2, 1.5)],
	["greataxe", "charcter005", Vector2(0.18, 0.25), Vector2(1.3, 1.5)],
]
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
	for spec: Array in CASES:
		var loadout: String = spec[0]
		var model := (load("res://scenes/characters/tripo_roster/%s.tscn" % spec[1]) as PackedScene).instantiate() as Node3D
		model.set_meta("loadout", loadout)
		root.add_child(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var combat := SwordCombat.new()
		check(combat.install(model, player), "%s installs" % loadout)
		check(not combat.idle_clip.is_empty() and [combat.idle_clip, combat.walk_clip, combat.run_clip].all(player.has_animation),
			"%s has its own stance, walk and run" % loadout)
		check(combat.ready_stance.is_empty() and not combat.rest_pose.is_empty(), "%s holds the stance, not the ready stance" % loadout)
		var skeleton := combat.skeleton
		var path := player.get_node(player.root_node).get_path_to(skeleton)
		var hand: String = combat.rig["hand.R"]
		var arm: String = combat.rig["upper_arm.R"]
		for clip: String in [combat.slash_clip, combat.overhead_clip]:
			var animation := player.get_animation(clip)
			var worst := 0.0
			for bone: String in [hand, arm]:
				var track := animation.find_track(NodePath("%s:%s" % [path, bone]), Animation.TYPE_ROTATION_3D)
				var rest := (combat.rest_pose[bone] as Transform3D).basis.get_rotation_quaternion()
				for time in [0.0, animation.length]:
					worst = maxf(worst, animation.rotation_track_interpolate(track, time).angle_to(rest))
			check(worst < 0.01, "%s %s starts from and ends in the stance (%.4f rad)" % [loadout, clip, worst])
			check(combat.slows_on_hit(clip), "%s %s freezes only when it connects" % [loadout, clip])
			var hold := combat.hit_hold(clip, -1.0)
			var size := combat.hit_scale(clip)
			check(hold >= spec[2].x and hold <= spec[2].y and size >= spec[3].x and size <= spec[3].y,
				"%s %s hit hold %.2fs, burst x%.2f" % [loadout, clip, hold, size])
		var fx := model.find_child("SwordSlashFx", true, false)
		var profiles: Array = []
		for slashes: Array in fx._slashes.values():
			for slash in slashes: profiles.append(slash.profile)
		check(not profiles.is_empty() and profiles.all(func(profile: SwordSlashProfile) -> bool:
			return profile.material == INK and is_equal_approx(profile.afterglow_time, 0.22)), "%s arcs are ink slashes" % loadout)
		if loadout == "dual_daggers":
			check(combat.hit_tilt(SwordCombat.DG_SLASH, 0.0) < 0.0 and combat.hit_tilt(SwordCombat.DG_SLASH_L, 0.0) > 0.0,
				"Each dagger's hit effect leans along its own swing")
		model.queue_free()
		await process_frame
	await _katana()
	print("WEAPON STANCE: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

## Katana (worn sheathed outside its clips, so no sheathing toggle): ink arcs, a freeze only on contact, a breathing stance
## that keeps the hand on the hilt, and the bare-handed walk and run with the left hand on the scabbard mouth.
func _katana() -> void:
	var model := (load("res://scenes/characters/tripo_roster/character007.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var combat := SwordCombat.new()
	check(combat.install(model, player), "katana installs")
	check(combat.walk_clip == GaitCycle.WALK and combat.run_clip == GaitCycle.RUN and combat.idle_clip == "idle", "katana walks and runs with the gait")
	for clip: String in [combat.slash_clip, combat.overhead_clip]:
		check(combat.slows_on_hit(clip) and combat.hit_hold(clip, -1.0) > 0.15 and combat.hit_scale(clip) > 1.0, "katana %s freezes only when it connects" % clip)
	check(combat.hit_tilt(SwordCombat.KT_IAI, 0.0) > 0.0, "The draw-cut's hit effect leans along its left-to-right cut")
	var fx := model.find_child("SwordSlashFx", true, false)
	var profiles: Array = []
	for slashes: Array in fx._slashes.values():
		for slash in slashes: profiles.append(slash.profile)
	check(profiles.all(func(profile: SwordSlashProfile) -> bool: return profile.material == INK), "katana arcs are ink slashes")
	var skeleton := combat.skeleton
	var holder := skeleton.find_child("KatanaGrip", false, false)
	var hips := skeleton.find_bone(combat.legs.hips)
	var hand := skeleton.find_bone(combat.rig["hand.R"])
	var left := skeleton.find_bone(combat.rig["hand.L"])
	# The modified pose is only readable while the modifier reports it has finished.
	var seen := {}
	holder.modification_processed.connect(func() -> void:
		var pelvis := skeleton.get_bone_global_pose(hips)
		seen["hips"] = pelvis.origin.y
		# The scabbard hangs from the pelvis, so the hand on the hilt keeps its place in the pelvis' frame.
		seen["grip"] = (pelvis.affine_inverse() * skeleton.get_bone_global_pose(hand)).origin
		var palm: Vector3 = skeleton.get_bone_global_pose(left) * Vector3(0, combat.rig["palm"], 0)
		seen["saya"] = palm.distance_to(combat.saya_hold(_pose(skeleton))[0]))
	player.play("idle", 0)
	for frame in 30: await process_frame
	var heights: Array[float] = []
	var grips: Array[Vector3] = []
	for sample in 2:
		holder._breath_time = sample * SwordCombat.KT_BREATH.length * 0.25
		await process_frame
		await process_frame
		heights.append(seen.hips)
		grips.append(seen.grip)
	check(absf(heights[0] - heights[1]) > 0.002 and grips[0].distance_to(grips[1]) < 0.003,
		"The stance breathes (hips %.4f) with the hand kept on the hilt (%.4f)" % [absf(heights[0] - heights[1]), grips[0].distance_to(grips[1])])
	player.play(combat.walk_clip, 0)
	for frame in 30: await process_frame
	check(holder.saya_weight > 0.99, "Walking keeps the left hand on the scabbard")
	check(seen.saya < 0.02, "The left palm sits on the scabbard mouth (%.4f)" % seen.saya)
	model.queue_free()
	await process_frame

func _pose(skeleton: Skeleton3D) -> Dictionary:
	var pose: Dictionary = {}
	for index in skeleton.get_bone_count(): pose[skeleton.get_bone_name(index)] = skeleton.get_bone_pose(index)
	return pose
