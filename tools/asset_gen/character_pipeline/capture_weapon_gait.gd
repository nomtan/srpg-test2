extends SceneTree
## Captures a loadout's own stance, walk and run (SwordGait.install_loadout: dual daggers, greatsword, greataxe), its
## attack clips mid-swing, and the weapon worn sheathed (the katana: its stance and gait, worn sheathed outside its clips), front, three-quarter, side and back.
## Needs a renderer (not --headless):
## godot --path . --script res://tools/asset_gen/character_pipeline/capture_weapon_gait.gd -- [out_dir] [loadout] [character ...]
## One image per character (artifacts/weapon_gait/<loadout>_<character>.png).

const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
# Panel: [clip ("idle"/"walk"/"run" are the loadout's own, "slash"/"overhead" its attacks), normalized phase,
# model yaw in degrees, sheathed]. Yaw 0 faces the camera; -90 shows the character's right side, 180 the back.
const PANELS := [
	["idle", 0.0, 0.0, false], ["idle", 0.0, -45.0, false], ["idle", 0.0, -90.0, false], ["idle", 0.5, 45.0, false],
	["walk", 0.0, 0.0, false], ["walk", 0.25, -90.0, false], ["run", 0.25, -90.0, false], ["run", 0.0, 0.0, false],
	["slash", 0.0, -45.0, false], ["overhead", 0.0, -90.0, false],
	["sheathed", 0.0, 180.0, true], ["sheathed", 0.0, 135.0, true], ["sheathed", 0.0, -90.0, true], ["sheathed", 0.0, 0.0, true],
	["sheathed_walk", 0.25, -90.0, true],
]
const SPACING := 1.3


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/weapon_gait"
	var loadout: String = args[1] if args.size() > 1 else "dual_daggers"
	var characters: Array = args.slice(2) if args.size() > 2 else ["charcter004"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(300 * PANELS.size(), 720)
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
			model.set_meta("loadout", loadout)
			# Loadouts that cannot be sheathed (the katana, always worn sheathed outside its clips) show the panel drawn.
			var sheathe: bool = panel[3] and loadout in SwordCombat.SHEATHABLE
			if sheathe: model.set_meta("sheathed", true)
			model.position.x = index * SPACING
			stage.add_child(model)
			var visual := model.get_node_or_null("Model") as Node3D
			(visual if visual else model).rotation_degrees.y = panel[2]
			var label := model.get_node_or_null("NameLabel") as Node3D
			if label: label.hide()
			models.append(model)
			var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var combat := SwordCombat.new()
			if not combat.install(model, player) or (not sheathe and combat.idle_clip.is_empty()) or (sheathe and not combat.stowed):
				push_error("%s: %s install failed" % [id, loadout])
				quit(1)
				return
			model.set_meta("combat", combat)
			var clip: String = {"idle": combat.idle_clip, "walk": combat.walk_clip, "run": combat.run_clip,
				"slash": combat.slash_clip, "overhead": combat.overhead_clip, "sheathed": "idle"}.get(panel[0], "")
			if panel[0] == "sheathed_walk" and not sheathe:
				clip = combat.walk_clip
			elif panel[0] == "sheathed_walk":
				GaitCycle.install(player, model.find_child("Skeleton3D", true, false) as Skeleton3D)
				clip = GaitCycle.WALK
			player.play(clip)
			# Attacks are shown at their impact.
			var at: float = combat.impact_time(clip) if panel[0] in ["slash", "overhead"] else player.current_animation_length * panel[1]
			player.seek(at, true)
			player.pause()
		var width := (PANELS.size() - 1) * SPACING
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = PANELS.size() * SPACING
		camera.position = Vector3(width * 0.5, 1.0, 6.0)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, loadout, id])
		for model in models:
			model.queue_free()
		await process_frame
	print("WEAPON_GAIT_CAPTURE ", out_dir)
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
