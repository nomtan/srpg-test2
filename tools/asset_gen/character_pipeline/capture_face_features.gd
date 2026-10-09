extends SceneTree
## Close-up front captures of every roster Face with the eyes / eyebrows / mouth
## overlay forced on, regardless of CharacterAssembler.SHOW_FACE_FEATURES.
## Output: artifacts/face_features/<definition>_<expression>.png and sheet rows.

const DEFINITIONS := ["charcter001", "charcter002", "charcter003", "charcter005", "charcter006", "character007"]
const EXPRESSIONS := ["normal", "angry", "smile", "sad", "surprised"]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var expressions: Array = EXPRESSIONS
	if "--normal-only" in OS.get_cmdline_user_args():
		expressions = ["normal"]
	root.size = Vector2i(420, 420)
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
	sun.rotation_degrees = Vector3(-28, -20, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 30.0
	stage.add_child(camera)
	camera.make_current()
	for id in DEFINITIONS:
		var definition := load("res://assets/characters/modular/definitions/%s.tres" % id) as CharacterDefinition
		var character := CharacterAssembler.assemble(definition) as AssembledCharacter
		if character == null:
			quit(1)
			return
		stage.add_child(character)
		var player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
		player.play("idle")
		player.seek(0.0, true)
		player.pause()
		var face := character.find_child("Face", true, false) as Node3D
		var controller := character.find_child("ExpressionController", true, false) as ExpressionController
		controller.bind_face(face, definition.expression_profile_id, true)
		var socket := character.find_child("FaceSocket", true, false) as Node3D
		var head := socket.global_position + Vector3(0, 0.12, 0)
		camera.position = head + Vector3(0, 0, 0.95)
		camera.look_at(head)
		for expression in expressions:
			character.set_expression(expression)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/face_features/%s_%s.png" % [id, expression])
		character.free()
	quit()
