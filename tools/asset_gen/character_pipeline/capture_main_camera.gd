extends SceneTree
## Inspect swap combinations through the real Main scene's CameraController.

const PAIRS := [[1, 1], [1, 2], [2, 1], [3, 4], [4, 3]]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var game := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await create_timer(0.5).timeout
	var controller := game.get_node("CameraController") as CameraController
	var camera := controller.camera
	if camera == null:
		push_error("Main camera did not initialize")
		quit(1)
		return
	if controller.focus_tween and controller.focus_tween.is_valid():
		controller.focus_tween.kill()
	var focus := controller.focus_target
	var right := camera.global_basis.x
	right.y = 0
	right = right.normalized()
	var lineup := Node3D.new()
	game.add_child(lineup)
	for layer in game.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var players: Array[AnimationPlayer] = []
	var characters: Array[AssembledCharacter] = []
	for index in PAIRS.size():
		var pair: Array = PAIRS[index]
		var definition := CharacterDefinition.new()
		definition.body_id = "body%03d" % pair[0]
		definition.face_id = "face%03d" % pair[1]
		var character := CharacterAssembler.assemble(definition)
		if character == null:
			quit(1)
			return
		lineup.add_child(character)
		characters.append(character as AssembledCharacter)
		character.global_position = focus + right * (index - 2) * 1.3
		var player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
		players.append(player)
	controller.camera.size = 5.0
	var offset := controller.focus_offset.normalized() * 8.0
	camera.global_position = focus + offset
	camera.look_at(focus + Vector3(0, 0.8, 0))
	for character in lineup.get_children():
		if character is Node3D:
			(character as Node3D).rotation.y = atan2(offset.x, offset.z)
	for clip in ["idle", "walk", "attack"]:
		for player in players:
			player.play(clip)
			player.seek(player.current_animation_length * 0.35, true)
			player.pause()
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/modular_main_%s.png" % clip)
	characters[0].set_expression("normal")
	characters[1].set_expression("angry")
	characters[2].set_expression("smile")
	characters[3].set_eyes("blink")
	characters[4].set_mouth("open")
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/phase3_main_expressions.png")
	quit()
