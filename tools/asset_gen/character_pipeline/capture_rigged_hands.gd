extends SceneTree
## Close-ups of the standalone test character's sword hand (scenes/characters/standalone/test.tscn) as an
## explorer with sword and shield, on an empty stage: the sword stance, the walk, the run, the slash, the overhead,
## the guard and the skill, each from the sword side and from the front, framed on the right wrist. Checks
## the gauntlet does not pinch or wring when the hand turns the grip.
## Needs a renderer: godot --path . --script res://tools/asset_gen/character_pipeline/capture_rigged_hands.gd -- [out_dir]
## Image: <out_dir>/hands.png, one row per pose (default artifacts/rigged_hands).

const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
const CHARACTER := preload("res://scenes/characters/standalone/test.tscn")
const SIZE := 360
# (clip getter, share of the clip's length)
const POSES := [["idle", 0.3], ["walk", 0.25], ["run", 0.25], ["slash", 0.35], ["overhead", 0.4], ["guard", 1.0], ["skill", 0.45]]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/rigged_hands"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(SIZE, SIZE)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.6, 0.66)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	root.add_child(sun)
	var player = Explorer.new()
	player.model_scene = CHARACTER
	player.start_in_roster_layout = true
	root.add_child(player)
	player.set_process(false)
	var camera := Camera3D.new()
	camera.fov = 30
	root.add_child(camera)
	camera.make_current()
	await process_frame
	var animation: AnimationPlayer = player.animation_player
	var skeleton := player.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := skeleton.find_bone("mixamorig_RightHand")
	var combat = player.sword_combat
	var clips := {"idle": player.idle_clip, "walk": player.walk_clip, "run": player.run_clip, "slash": combat.slash_clip,
		"overhead": combat.overhead_clip, "guard": combat.guard_clip, "skill": combat.skill_clip}
	var rows: Array[Image] = []
	for pose: Array in POSES:
		var clip: String = clips[pose[0]]
		animation.play(clip, 0)
		animation.seek(animation.get_animation(clip).length * pose[1], true)
		animation.pause()
		# ForearmTwist blends its per-clip holds in over a few frames; let them settle as in play.
		for frame in 20: await process_frame
		var row: Image = null
		# Skeleton space: the character faces +Z and its right (the sword side) is -X.
		var front := (skeleton.global_basis * Vector3.BACK).normalized()
		var right := (skeleton.global_basis * Vector3.LEFT).normalized()
		for view: Vector3 in [right + front * 0.35 + Vector3.UP * 0.15, front + right * 0.35 + Vector3.UP * 0.15]:
			await process_frame
			var wrist := skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
			camera.look_at_from_position(wrist + view.normalized() * 1.1, wrist)
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			if row == null:
				row = Image.create(SIZE * 2, SIZE, false, shot.get_format())
				row.blit_rect(shot, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
			else:
				row.blit_rect(shot, Rect2i(0, 0, SIZE, SIZE), Vector2i(SIZE, 0))
		rows.append(row)
		print("POSE ", pose[0], " ", clip)
	var sheet := Image.create(SIZE * 2, SIZE * rows.size(), false, rows[0].get_format())
	for index in rows.size():
		sheet.blit_rect(rows[index], Rect2i(0, 0, SIZE * 2, SIZE), Vector2i(0, SIZE * index))
	var path := ProjectSettings.globalize_path(out_dir + "/hands.png")
	sheet.save_png(path)
	print("CAPTURE ", path)
	quit(0)
