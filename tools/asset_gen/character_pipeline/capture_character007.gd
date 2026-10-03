extends SceneTree
## Roster lineup (front / side) of Character001-007 in the same idle frame, for Face007 fit review.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/character007")
	root.size = Vector2i(2000, 700)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, -40, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	stage.add_child(camera)
	var actors: Array[Node3D] = []
	for i in range(1, 8):
		var id := "charcter%03d" % i if i < 7 else "character007"
		var actor := (load("res://scenes/characters/tripo_roster/%s.tscn" % id) as PackedScene).instantiate() as Node3D
		stage.add_child(actor)
		actor.get_node("NameLabel").hide()
		actor.set_expression("normal")
		actor.animation_player.seek(0.0, true)
		actor.animation_player.pause()
		actors.append(actor)
	for view in ["front", "side"]:
		for i in actors.size():
			actors[i].position = Vector3((i - 3) * 0.9, 0, 0) if view == "front" else Vector3(0, 0, (i - 3) * 0.9)
			actors[i].rotation.y = 0.0
		camera.position = Vector3(0, 1.3, 8) if view == "front" else Vector3(8, 1.3, 0)
		camera.look_at(Vector3(0, 1.3, 0))
		camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/character007/lineup_%s.png" % view)
	stage.free()
	CharacterAssembler.clear_cached_materials()
	quit()
