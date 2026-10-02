extends SceneTree
## Default: deterministic fixture. -- --face007 captures real production asset.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(640, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b7c4bd")
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -55, 0)
	stage.add_child(sun)
	var face: Node3D
	var controller: ExpressionController
	var production := OS.get_cmdline_user_args().has("--face007")
	if production:
		var definition := CharacterDefinition.new()
		definition.body_id = "body001"
		definition.face_id = "face007"
		face = CharacterAssembler.assemble(definition)
		if face != null:
			controller = face.find_child("ExpressionController", true, false) as ExpressionController
	else:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file("res://artifacts/expression_v2_fixture/model.glb", state) != OK:
			quit(1)
			return
		face = document.generate_scene(state)
		CharacterAssembler._apply_toon(face)
		controller = ExpressionController.new()
		face.add_child(controller)
		if not controller.bind_face(face):
			face.free()
			quit(1)
			return
	if face == null or controller == null:
		quit(1)
		return
	stage.add_child(face)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.7
	stage.add_child(camera)
	camera.make_current()
	var folder := "res://artifacts/phase5_%s_captures" % ("face007" if production else "fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	for view in ["front", "front_left", "front_right"]:
		camera.position = Vector3(0 if view == "front" else (-0.8 if view == "front_left" else 0.8), 1.15 if view == "front" else 1.7, 2)
		camera.look_at(Vector3(0, 1.15, 0.06))
		for preset in ["normal", "angry", "smile", "sad", "surprised"]:
			controller.set_expression(preset)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [folder, view, preset])
	print("CAPTURE_V2: ", folder)
	stage.free()
	CharacterAssembler.clear_cached_materials()
	quit()
