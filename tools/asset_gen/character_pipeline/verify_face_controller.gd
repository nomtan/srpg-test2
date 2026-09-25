extends SceneTree

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var actors: Array[Node] = []
	var controllers: Array[FaceController] = []
	for id in ["001", "002"]:
		var scene := load("res://assets/characters/generated/golden_path_%s/character.glb" % id) as PackedScene
		assert(scene != null)
		var actor := scene.instantiate()
		root.add_child(actor)
		actors.append(actor)
		assert(actor.find_children("*", "Skeleton3D", true, false).size() == 1)
		assert((actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).get_bone_count() == 65)
		var players := actor.find_children("*", "AnimationPlayer", true, false)
		assert(not players.is_empty())
		for clip in ["idle", "walk", "attack", "hit"]:
			assert((players[0] as AnimationPlayer).has_animation(clip))
		var controller := preload("res://scripts/character/face_controller.gd").new() as FaceController
		actor.add_child(controller)
		assert(controller.bind_character(actor, id))
		assert(not controller.head_materials.is_empty())
		for expression in FaceController.EXPRESSIONS:
			controller.set_expression(expression)
			assert(controller.head_materials[0].get_shader_parameter("expression_enabled"))
		controllers.append(controller)
	controllers[0].set_expression("closed")
	controllers[1].set_expression("surprised")
	assert(controllers[0].head_materials[0] != controllers[1].head_materials[0])
	assert(controllers[0].head_materials[0].get_shader_parameter("expression_texture") != controllers[1].head_materials[0].get_shader_parameter("expression_texture"))
	print("FACE_CONTROLLER_VERIFY_OK")
	quit()
