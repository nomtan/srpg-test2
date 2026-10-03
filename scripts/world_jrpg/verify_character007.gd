extends SceneTree
## Character 007: modular Body007 + Face007, katana worn sheathed, drawn and sheathed again by its clips.
## godot --headless --path . --script scripts/world_jrpg/verify_character007.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/katana/).
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const CHARACTER = preload("res://scenes/characters/tripo_roster/character007.tscn")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
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
	var character := CHARACTER.instantiate() as Node3D
	root.add_child(character)
	var player: AnimationPlayer = character.animation_player
	for clip in ["idle", "walk", "attack", "hit"]:
		check(player.has_animation(clip), "Character007 has the shared %s clip" % clip)
	check(character.find_children("*", "Skeleton3D", true, false).size() == 1, "Face007 and Body007 share one humanoid_v1 skeleton")
	check(character.find_child("FaceSocket", true, false) != null, "Face007 follows the head through the shared FaceSocket")
	var combat := SwordCombat.new()
	check(combat.install(character, player), "Katana installs on Character007")
	for part in ["EquippedKatana", "SheathedKatana", "EmptyScabbard"]:
		check(character.find_child(part, true, false) != null, "Character007 carries " + part)
	check(combat.slash_clip == SwordCombat.KT_IAI and combat.overhead_clip == SwordCombat.KT_KESA and combat.guard_clip == SwordCombat.KT_GUARD, "Katana attacks are the draw-cut and the kesa cut, with a guard")
	for clip in SwordCombat.KT_CLIPS:
		check(player.has_animation(clip), "Clip exists: " + clip)
	var skeleton := combat.skeleton
	var palm: float = combat.rig["palm"]
	var left := skeleton.find_bone(combat.rig["hand.L"])
	# Keyed reach: the right palm arrives where each key asks, the left one on the handle in two-handed keys.
	for clip: String in SwordCombat.KT_CLIPS:
		for raw: Dictionary in SwordCombat.KT_CLIPS[clip]:
			var key := SwordCombat.gs_key(raw)
			if not key.has("grip"): continue
			var pose: Dictionary = combat._pose(key)
			var shoulders: Vector3 = (combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.R"])).origin + combat._global(pose, skeleton.find_bone(combat.rig["upper_arm.L"])).origin) * 0.5
			var wanted: Vector3 = shoulders + (key.grip as Vector3) * combat.arm_reach
			var hand: Transform3D = combat._global(pose, skeleton.find_bone(combat.rig["hand.R"]))
			var error := (hand * Vector3(0, palm, 0)).distance_to(wanted)
			check(error < REACH_TOLERANCE, "%s t=%.2f right hand reaches its key (%.4f)" % [clip, key.t, error])
			if key.get("one_hand", false): continue
			var handle := wanted - (key.blade as Vector3).normalized() * SwordCombat.GS_HAND_SPACING
			error = (combat._global(pose, left) * Vector3(0, palm, 0)).distance_to(handle)
			check(error < HOLD_TOLERANCE, "%s t=%.2f left hand reaches the handle (%.4f)" % [clip, key.t, error])
	var katana := character.find_child("EquippedKatana", true, false) as Node3D
	var sheathed := character.find_child("SheathedKatana", true, false) as Node3D
	var scabbard := character.find_child("EmptyScabbard", true, false) as Node3D
	# Live: sample each clip with the grip modifier applied (readable once it reports it has finished).
	var holder := skeleton.get_node("KatanaGrip") as SkeletonModifier3D
	var gap := [0.0, 0.0]
	var right := skeleton.find_bone(combat.rig["hand.R"])
	holder.modification_processed.connect(func() -> void:
		var handle := skeleton.get_bone_global_pose(right) * combat.grip.transform * Vector3(0, -SwordCombat.GS_HAND_SPACING, 0)
		var left_palm := skeleton.get_bone_global_pose(left) * Vector3(0, palm, 0)
		gap[0] = left_palm.distance_to(handle) if holder.two_hand_weight >= 1.0 else 0.0
		var pose: Dictionary = {}
		for index in skeleton.get_bone_count():
			pose[skeleton.get_bone_name(index)] = skeleton.get_bone_pose(index)
		gap[1] = left_palm.distance_to(combat.saya_hold(pose)[0]) if holder.saya_weight >= 1.0 else 0.0)
	var camera: Camera3D
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/katana"))
		character.get_node("NameLabel").hide()
		root.size = Vector2i(720, 720)
		camera = Camera3D.new()
		root.add_child(camera)
		camera.make_current()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, 30, 0)
		root.add_child(light)
	player.speed_scale = 0.0
	for clip in ["idle", "walk", "hit", SwordCombat.KT_IAI, SwordCombat.KT_KESA, SwordCombat.KT_GUARD]:
		player.play(clip, 0)
		var length := player.get_animation(clip).length
		var window: Vector2 = SwordCombat.KT_DRAWN.get(clip, Vector2(INF, INF))
		var worst := 0.0
		var worst_saya := 0.0
		var held_saya := false
		var swapped := true
		for step in 25:
			var time := length * step / 24.0
			player.seek(time, true)
			await process_frame
			await process_frame
			worst = maxf(worst, gap[0])
			worst_saya = maxf(worst_saya, gap[1])
			held_saya = held_saya or holder.saya_weight >= 1.0
			var out := time >= window.x and time < window.y
			swapped = swapped and katana.visible == out and scabbard.visible == out and sheathed.visible == not out
			if capture and step % 2 == 0:
				await _capture(character, camera, "%s_%02d" % [clip.replace("/", "_"), step])
		check(worst < HOLD_TOLERANCE, "%s keeps the left hand on the handle while gripping (worst %.4f)" % [clip, worst])
		if clip in [SwordCombat.KT_IAI, "idle"]:
			check(held_saya, "%s holds the scabbard in the left hand" % clip)
		check(worst_saya < HOLD_TOLERANCE, "%s keeps the left hand on the scabbard mouth while holding it (worst %.4f)" % [clip, worst_saya])
		check(swapped, "%s shows the katana %s" % [clip, "drawn only between its hilt keys" if window.x < INF else "sheathed throughout"])
	# The swap is invisible: at the hilt key the drawn katana lies where the sheathed one hangs.
	player.play(SwordCombat.KT_IAI, 0)
	player.seek(SwordCombat.KT_DRAWN[SwordCombat.KT_IAI].x, true)
	await process_frame
	await process_frame
	var drawn_at := katana.global_transform * (SwordCombat.KT_GRIP - Vector3(0, 0.4, 0))
	var sheathed_at := sheathed.global_transform * (SwordCombat.KT_GRIP - SwordCombat.KT_SHEATH_DROP - Vector3(0, 0.4, 0))
	check(drawn_at.distance_to(sheathed_at) < 0.03, "Drawn and sheathed katana coincide at the hilt key (%.4f)" % drawn_at.distance_to(sheathed_at))
	character.free()
	var world := SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	world.player.set_process(false)
	var placed: Node3D
	for npc in world.npcs:
		if npc.actor.get("character_id") == "character007":
			placed = npc.actor
	check(placed != null and world.character_roster.size() == 7, "JRPGWorldSample places Character007 as seventh roster actor")
	if placed:
		check(placed.has_meta("sword_combat") and placed.find_child("SwordPracticeTimer", true, false) != null, "Roster Character007 practices with the katana")
	world.player.set_model_scene(CHARACTER, true)
	check(world.player.sword_combat != null and world.player.attack(), "Selected Character007 attacks with the katana")
	check(world.player.animation_player.current_animation == SwordCombat.KT_IAI, "Player's horizontal attack is the draw-cut")
	world.free()
	CharacterAssembler.clear_cached_materials()
	await process_frame
	print("CHARACTER007: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _capture(model: Node3D, camera: Camera3D, file: String) -> void:
	# Front-left three-quarter view and the sword side of the character (it faces +Z).
	for view in [["front", Vector3(1.1, 1.1, 2.0)], ["side", Vector3(-2.2, 1.0, 0.3)]]:
		camera.look_at_from_position(model.global_position + view[1], model.global_position + Vector3(0, 0.85, 0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/katana/%s_%s.png" % [file, view[0]])
