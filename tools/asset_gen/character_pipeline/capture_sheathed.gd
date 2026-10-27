extends SceneTree
## Captures the sheathed sword and shield worn on the back, standing idle and over the bare-handed walk and run
## (GaitCycle), from behind, three-quarter back, the side and the front.
## Needs a renderer (not --headless): godot --path . --script res://tools/asset_gen/character_pipeline/capture_sheathed.gd -- [out_dir] [character ...]
## One image per character (artifacts/sheathed/<character>.png).

const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
# Panel: [clip, normalized phase, model yaw in degrees]. Yaw 0 faces the camera; 180 shows the back, -90 the right side.
const PANELS := [
	["idle", 0.0, 180.0], ["idle", 0.0, 135.0], ["idle", 0.0, -90.0], ["idle", 0.0, 90.0], ["idle", 0.0, 0.0],
	[GaitCycle.WALK, 0.25, 180.0], [GaitCycle.WALK, 0.25, -90.0], [GaitCycle.RUN, 0.25, 160.0], [GaitCycle.RUN, 0.75, -90.0],
]
const SPACING := 1.3


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/sheathed"
	var characters: Array = args.slice(1) if args.size() > 1 else ["charcter004"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(330 * PANELS.size(), 720)
	var stage := _stage()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	for id: String in characters:
		var models: Array[Node3D] = []
		for index in PANELS.size():
			var panel: Array = PANELS[index]
			var model := (load("res://scenes/characters/tripo_roster/%s.tscn" % id) as PackedScene).instantiate() as Node3D
			model.set_meta("loadout", "sword_shield")
			model.set_meta("sheathed", true)
			model.position.x = index * SPACING
			stage.add_child(model)
			var visual := model.get_node_or_null("Model") as Node3D
			(visual if visual else model).rotation_degrees.y = panel[2]
			var label := model.get_node_or_null("NameLabel") as Node3D
			if label: label.hide()
			models.append(model)
			var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var combat := SwordCombat.new()
			if not combat.install(model, player) or not combat.stowed:
				push_error("%s: sheathed install failed" % id)
				quit(1)
				return
			GaitCycle.install(player, model.find_child("Skeleton3D", true, false) as Skeleton3D)
			model.set_meta("combat", combat)
			player.play(panel[0])
			player.seek(player.current_animation_length * panel[1], true)
			player.pause()
		var width := (PANELS.size() - 1) * SPACING
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = PANELS.size() * SPACING
		camera.position = Vector3(width * 0.5, 1.0, 6.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, id])
		for model in models:
			model.queue_free()
		await process_frame
	print("SHEATHED_CAPTURE ", out_dir)
	quit()


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b7c4bd")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2c2c7")
	environment.environment.ambient_light_energy = 0.4
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(sun)
	return stage
