extends SceneTree
## Render Face001/002 expression states with the same toon shader as the game.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(900, 700)
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
	sun.light_energy = 1.0
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.position = Vector3(0, 1.2, 1.9)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.17, 0))
	camera.make_current()
	for face_index in [1, 2]:
		var definition := CharacterDefinition.new()
		definition.body_id = "body001"
		definition.face_id = "face%03d" % face_index
		var character := CharacterAssembler.assemble(definition) as AssembledCharacter
		if character == null:
			quit(1)
			return
		stage.add_child(character)
		var player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
		player.play("idle")
		player.seek(player.current_animation_length * 0.35, true)
		player.pause()
		for expression in ["normal", "angry", "smile"]:
			character.set_expression(expression)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/phase3_face%03d_%s.png" % [face_index, expression])
		character.set_expression("normal")
		character.set_eyes("blink")
		character.set_mouth("open")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/phase3_face%03d_blink_open.png" % face_index)
		character.free()
	quit()
