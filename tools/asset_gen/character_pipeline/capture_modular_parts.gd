extends SceneTree
## Capture a roster swap lineup with the exploration camera's FOV and lighting.

const PAIRS := [[1, 1], [1, 2], [2, 1], [3, 4], [4, 3]]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1500, 700)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b7c4bd")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2c2c7")
	environment.environment.ambient_light_energy = 0.32
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -55, 0)
	sun.light_color = Color("ffdda3")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 4)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position.y = -0.01
	stage.add_child(floor_instance)
	var camera := Camera3D.new()
	camera.fov = 52.0
	camera.position = Vector3(0, 2.0, 8.5)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.make_current()
	var players: Array[AnimationPlayer] = []
	for index in PAIRS.size():
		var pair: Array = PAIRS[index]
		var definition := CharacterDefinition.new()
		definition.id = "preview_%d" % index
		definition.body_id = "body%03d" % pair[0]
		definition.face_id = "face%03d" % pair[1]
		var model := CharacterAssembler.assemble(definition)
		if model == null:
			quit(1)
			return
		model.position.x = (index - 2) * 1.3
		stage.add_child(model)
		players.append(model.find_child("AnimationPlayer", true, false) as AnimationPlayer)
		var label := Label3D.new()
		label.text = "%03d x %03d" % [pair[0], pair[1]]
		label.position = model.position + Vector3(0, 1.9, 0)
		label.font_size = 38
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stage.add_child(label)
	for clip in ["idle", "walk", "attack"]:
		for player in players:
			player.play(clip)
			player.seek(player.current_animation_length * 0.35, true)
			player.pause()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/modular_%s_godot.png" % clip)
		for index in PAIRS.size():
			var pair: Array = PAIRS[index]
			var x := (index - 2) * 1.3
			camera.position = Vector3(x, 1.7, 3.5)
			camera.look_at(Vector3(x, 1.0, 0))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/modular_%03d_%03d_%s_godot.png" % [pair[0], pair[1], clip])
		camera.position = Vector3(0, 2.0, 8.5)
		camera.look_at(Vector3(0, 0.9, 0))
	quit()
