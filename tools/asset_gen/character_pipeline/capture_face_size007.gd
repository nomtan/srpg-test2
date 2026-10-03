extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1800, 650)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -40, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(0, 1.1, 6)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.1, 0))
	camera.make_current()
	var actors: Array[Node3D] = []
	for i in range(1, 8):
		var id := "charcter%03d" % i if i < 7 else "character007"
		var actor := (load("res://scenes/characters/tripo_roster/%s.tscn" % id) as PackedScene).instantiate() as Node3D
		stage.add_child(actor)
		actor.position.x = (i - 4) * 0.85
		actor.get_node("NameLabel").hide()
		actor.set_expression("normal")
		actor.play_animation("walk")
		actor.animation_player.seek(0.25, true)
		actor.animation_player.pause()
		actors.append(actor)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/face_size007/lineup.png")
	for i in 6:
		actors[i].hide()
	actors[6].position = Vector3.ZERO
	root.size = Vector2i(800, 800)
	camera.size = 1.3
	for view in ["front", "side"]:
		camera.position = Vector3(0, 1.5, 5) if view == "front" else Vector3(5, 1.5, 0)
		camera.look_at(Vector3(0, 1.5, 0))
		for phase in [0.0, 0.25, 0.5, 0.75]:
			actors[6].animation_player.seek(phase * actors[6].animation_player.current_animation_length, true)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/face_size007/neck007_%s_%02d.png" % [view, int(phase * 100)])
	stage.free()
	CharacterAssembler.clear_cached_materials()
	quit()
