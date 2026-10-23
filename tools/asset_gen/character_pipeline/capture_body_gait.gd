extends SceneTree
## Captures every Body (with its matching Face) in the idle and the procedural walk/run, front and side,
## to check left/right arm symmetry and how each Face sits on its neck.
## Needs a renderer (not --headless): godot --path . --script res://tools/asset_gen/character_pipeline/capture_body_gait.gd -- [out_dir] [NNN=x,y,z ...]
## One image per Body (artifacts/body_gait/bodyNNN.png) plus head close-ups (headNNN.png).

const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
const BODIES := ["001", "002", "003", "004", "005", "006", "007", "008", "009", "010"]
# Panel: [clip, normalized phase, model yaw in degrees]. Yaw 0 faces the camera; -90 shows the character's right side.
const PANELS := [
	["idle", 0.0, 0.0], ["idle", 0.0, -90.0],
	["gait/walk", 0.0, 0.0], ["gait/walk", 0.25, 0.0], ["gait/walk", 0.25, -90.0], ["gait/walk", 0.75, -90.0],
	["gait/run", 0.0, 0.0], ["gait/run", 0.25, 0.0], ["gait/run", 0.25, -90.0], ["gait/run", 0.75, -90.0],
]
const SPACING := 1.15
var _trial_offsets := {}
const HEAD_SPACING := 0.6
const HEAD_VIEWS := [0.0, -45.0, -90.0]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/body_gait"
	# Optional trial Face offsets on top of the Body's own, as NNN=x,y,z (rest space, +Y up, +Z forward).
	for arg: String in args.slice(1):
		var parts := arg.split("=")
		var xyz := parts[1].split_floats(",")
		_trial_offsets[parts[0]] = Vector3(xyz[0], xyz[1], xyz[2])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	root.size = Vector2i(400 * PANELS.size(), 760)
	var stage := _stage()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.make_current()
	for body_id: String in BODIES:
		var models: Array[Node3D] = []
		for index in PANELS.size():
			var panel: Array = PANELS[index]
			var model := _assemble(body_id)
			if model == null:
				quit(1)
				return
			model.position.x = index * SPACING
			model.rotation_degrees.y = panel[2]
			stage.add_child(model)
			models.append(model)
			var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
			if not GaitCycle.install(player, skeleton):
				push_error("gait install failed for body%s" % body_id)
				quit(1)
				return
			player.play(panel[0])
			player.seek(player.current_animation_length * panel[1], true)
			player.pause()
		var width := (PANELS.size() - 1) * SPACING
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = PANELS.size() * SPACING
		camera.position = Vector3(width * 0.5, 0.95, 6.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/body%s.png" % [out_dir, body_id])
		for model in models:
			model.queue_free()
		await process_frame
	# Close-ups of the head on the neck per Body: front, three-quarter and right side.
	root.size = Vector2i(300 * HEAD_VIEWS.size(), 400)
	for body_id: String in BODIES:
		var models: Array[Node3D] = []
		for index in HEAD_VIEWS.size():
			var model := _assemble(body_id)
			model.position.x = index * HEAD_SPACING
			model.rotation_degrees.y = HEAD_VIEWS[index]
			stage.add_child(model)
			models.append(model)
			var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			player.play("idle")
			player.seek(0.0, true)
			player.pause()
		camera.size = HEAD_VIEWS.size() * HEAD_SPACING
		camera.position = Vector3((HEAD_VIEWS.size() - 1) * HEAD_SPACING * 0.5, 1.1, 6.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/head%s.png" % [out_dir, body_id])
		for model in models:
			model.queue_free()
		await process_frame
	print("BODY_GAIT_CAPTURE ", out_dir)
	quit()


func _assemble(body_id: String) -> Node3D:
	var definition := CharacterDefinition.new()
	definition.id = "gait_" + body_id
	definition.body_id = "body" + body_id
	definition.face_id = "face" + body_id
	definition.face_offset = _trial_offsets.get(body_id, Vector3.ZERO)
	return CharacterAssembler.assemble(definition)


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
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40, 4)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(10, -0.005, 0)
	stage.add_child(floor_instance)
	return stage
