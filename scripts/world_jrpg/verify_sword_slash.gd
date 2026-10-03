extends SceneTree
## Slash effects: the arc plays on its own, starts and peaks with each attack clip, keeps the hit-stop at the impact,
## and leaves nothing behind after an interrupted, repeated or freed attack.
## godot --headless --path . --script scripts/world_jrpg/verify_sword_slash.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/sword_slash/).
const SLASH_SCENE = preload("res://scenes/fx/sword_slash.tscn")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const SlashPlayer = preload("res://scripts/world_jrpg/sword_slash_player.gd")
const CHARACTERS := ["charcter004", "charcter001", "charcter002", "charcter003", "charcter005", "character007"]
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
	await _standalone()
	for id: String in CHARACTERS:
		await _attacks(id, capture)
	await _interrupt_and_repeat()
	print("SWORD SLASH: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

## Plays from a profile alone, with no character or weapon in the scene.
func _standalone() -> void:
	var slash := SLASH_SCENE.instantiate()
	slash.profile = load("res://assets/fx/sword_slash/sword_slash.tres")
	root.add_child(slash)
	var arc := slash.get_child(0, true) as MeshInstance3D
	check(arc.mesh != null and not arc.visible, "Standalone slash builds its arc and waits hidden")
	var done := [false]
	slash.finished.connect(func() -> void: done[0] = true)
	slash.play()
	check(arc.visible and slash.playing, "Standalone slash plays without a weapon")
	var elapsed := 0.0
	while slash.playing and elapsed < 2.0:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	check(done[0] and not arc.visible, "Standalone slash finishes and hides (%.2fs for %.2fs)" % [elapsed, slash.profile.duration()])
	slash.queue_free()
	await process_frame

func _attacks(id: String, capture: bool) -> void:
	var character := (load("res://scenes/characters/tripo_roster/%s.tscn" % id) as PackedScene).instantiate() as Node3D
	root.add_child(character)
	var player: AnimationPlayer = character.animation_player
	var combat := SwordCombat.new()
	check(combat.install(character, player), "%s installs its weapon" % id)
	var fx := character.find_child("SwordSlashFx", false, false)
	check(fx is SlashPlayer, "%s plays the slash effects instead of the blade trail" % id)
	check(character.find_children("*", "MeshInstance3D", true, false).all(func(mesh: MeshInstance3D) -> bool: return not mesh.mesh is ImmediateMesh),
		"%s has no blade-sampled trail mesh" % id)
	# The first playback of each generated clip stalls a frame while the clip is set up; take it before timing anything.
	for clip: String in [combat.slash_clip, combat.alt_slash_clip, combat.overhead_clip]:
		if clip.is_empty(): continue
		player.play(clip, 0)
		player.advance(0)
	player.play("idle", 0)
	for frame in 3: await process_frame
	if capture: await _capture(id, combat, fx, player)
	for clip: String in [combat.slash_clip, combat.alt_slash_clip, combat.overhead_clip]:
		if clip.is_empty(): continue
		var slashes: Array = fx._slashes.get(clip, [])
		check(not slashes.is_empty(), "%s %s has a slash effect" % [id, clip])
		var impact: float = fx.impacts[clip].impact
		player.speed_scale = 1.0
		player.play(clip, 0)
		var started := -1.0
		var stopped := -1.0
		var peaked := -1.0
		var longest := 0.0
		while player.current_animation == clip:
			await process_frame
			longest = maxf(longest, get_root().get_process_delta_time())
			var time := player.current_animation_position
			var slash = slashes[0]
			if started < 0.0 and slash.playing: started = time
			if peaked < 0.0 and slash.playing and slash._time >= slash.profile.swing_time: peaked = time
			if stopped < 0.0 and not is_equal_approx(player.speed_scale, 1.0): stopped = time
		var profile: SwordSlashProfile = slashes[0].profile
		check(started >= 0.0 and absf(started - profile.start_time) < 0.04, "%s %s arc appears at %.2fs (profile %.2fs, longest frame %.3fs)" % [id, clip, started, profile.start_time, longest])
		check(peaked >= 0.0 and absf(peaked - (profile.start_time + profile.swing_time)) < 0.05 and absf(peaked - impact) < 0.06,
			"%s %s full swing at %.2fs, impact %.2fs" % [id, clip, peaked, impact])
		check(stopped >= 0.0 and absf(stopped - impact) < 0.04, "%s %s hit-stop still lands at the impact (%.2fs)" % [id, clip, stopped])
		check(slashes.all(func(slash) -> bool: return not slash.playing), "%s %s leaves no arc after the clip" % [id, clip])
	character.queue_free()
	await process_frame

## Frames through each attack from the front and from above, the clip frozen at each sample and the arcs set to match.
func _capture(id: String, combat: RefCounted, fx: Node, player: AnimationPlayer) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/sword_slash"))
	var camera := Camera3D.new()
	root.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	fx.set_process(false)
	player.speed_scale = 0.0
	for clip: String in [combat.slash_clip, combat.alt_slash_clip, combat.overhead_clip]:
		if clip.is_empty(): continue
		var slashes: Array = fx._slashes[clip]
		var profile: SwordSlashProfile = slashes[0].profile
		player.play(clip, 0)
		for slash in slashes: slash.play(combat.skeleton)
		for step in 8:
			var time := profile.start_time + (profile.swing_time + profile.afterglow_time) * step / 8.0
			player.seek(time, true)
			for slash in slashes:
				slash._time = time - slash.profile.start_time
				slash._update()
			for view in [["front", Vector3(0.5, 1.6, 3.4)], ["top", Vector3(0.0, 3.6, 0.9)]]:
				camera.look_at_from_position(view[1], Vector3(0, 0.8, 0.3))
				# The shot shows the previous frame's state; draw once more before saving.
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/sword_slash/%s_%s_%s_%d.png" % [id, clip.replace("/", "_"), view[0], step])
		for slash in slashes: slash.stop()
	fx.set_process(true)
	player.speed_scale = 1.0
	camera.queue_free()
	light.queue_free()

## Interrupting fades the arc out; replaying restarts it; freeing the character mid-swing leaves nothing behind.
func _interrupt_and_repeat() -> void:
	var character := (load("res://scenes/characters/tripo_roster/charcter004.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(character)
	var player: AnimationPlayer = character.animation_player
	var combat := SwordCombat.new()
	combat.install(character, player)
	var fx := character.find_child("SwordSlashFx", false, false)
	var slash = fx._slashes[combat.slash_clip][0]
	player.play(combat.slash_clip, 0)
	while not slash.playing: await process_frame
	player.play("idle", 0.1)
	var elapsed := 0.0
	while slash.playing and elapsed < 0.5:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	check(not slash.playing and elapsed <= SlashPlayer.CANCEL_FADE + 0.05, "An interrupted attack fades its arc out (%.2fs)" % elapsed)
	player.play(combat.slash_clip, 0)
	while slash._time < slash.profile.swing_time * 0.5: await process_frame
	player.stop()
	player.play(combat.slash_clip, 0)
	await process_frame
	await process_frame
	check(not slash.playing or slash._time < slash.profile.swing_time * 0.5, "Attacking again does not carry the previous arc on")
	while not slash.playing or slash._time < slash.profile.swing_time * 0.5: await process_frame
	check(slash._opacity >= 1.0, "The repeated attack plays its own arc at full strength")
	var effects := fx.find_children("*", "", true, false)
	character.queue_free()
	await process_frame
	check(effects.all(func(node) -> bool: return not is_instance_valid(node)), "Freeing the character mid-swing frees its arcs")
