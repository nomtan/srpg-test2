extends SceneTree
## Run after editor import with Godot --headless --path . --script this_file.

var failed := false


func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: ", description)
	else:
		failed = true
		push_error(description)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for body_index in range(1, 5):
		for face_index in range(1, 5):
			var def := CharacterDefinition.new()
			def.id = "test_%d_%d" % [body_index, face_index]
			def.body_id = "body%03d" % body_index
			def.face_id = "face%03d" % face_index
			var character := CharacterAssembler.assemble(def)
			check(character != null, def.id + " assembles")
			if character == null:
				continue
			root.add_child(character)
			var skeletons := character.find_children("*", "Skeleton3D", true, false)
			var players := character.find_children("*", "AnimationPlayer", true, false)
			var meshes := character.find_children("*", "MeshInstance3D", true, false)
			var socket := character.find_child("FaceSocket", true, false) as BoneAttachment3D
			var face := character.find_child("Face", true, false) as Node3D
			var old_model: Node3D
			if body_index == face_index:
				old_model = (load("res://assets/characters/generated/charcter%03d/character.glb" % body_index) as PackedScene).instantiate()
				root.add_child(old_model)
			check(skeletons.size() == 1 and players.size() == 1, def.id + " has one rig and player")
			check(meshes.size() == 2 and meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.get_active_material(0) is ShaderMaterial), def.id + " keeps Body/Face meshes and toon materials")
			check(socket != null and face != null and socket.is_ancestor_of(face), def.id + " attaches face to head")
			var expression_controller := character.find_child("ExpressionController", true, false) as ExpressionController
			check(expression_controller != null, def.id + " has ExpressionController")
			if expression_controller != null:
				var face_material := (meshes[1] as MeshInstance3D).get_active_material(0)
				check(face_material.get_shader_parameter("expression_parts_enabled") == (face_index != 4), def.id + " shows facial features only on uncovered faces")
				for expression in ["normal", "angry", "smile"]:
					check(character.set_expression(expression), def.id + " accepts " + expression)
				check(character.set_eyes("blink"), def.id + " blinks")
				check(character.set_eyebrows("confident"), def.id + " changes eyebrows only")
				check(character.set_mouth("open"), def.id + " opens mouth")
				check(expression_controller.current_eyes == "blink" and expression_controller.current_eyebrows == "confident" and expression_controller.current_mouth == "open", def.id + " keeps independent part states")
				check(character.find_children("*", "MeshInstance3D", true, false).size() == meshes.size() and (meshes[1] as MeshInstance3D).get_active_material(0) == face_material, def.id + " changes expression without allocating mesh or material")
			if skeletons.size() == 1 and players.size() == 1 and socket and face:
				var skeleton := skeletons[0] as Skeleton3D
				var player := players[0] as AnimationPlayer
				var head_index := skeleton.find_bone("head")
				check(head_index >= 0, def.id + " has head bone")
				var rest_inverse := skeleton.get_bone_global_rest(head_index).affine_inverse()
				check(face.transform.is_equal_approx(rest_inverse), def.id + " cancels the imported head rest transform")
				var mounted_mesh := face.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				for clip in ["idle", "walk", "attack", "hit"]:
					check(player.has_animation(clip), def.id + " has " + clip)
					if player.has_animation(clip):
						player.play(clip)
						player.seek(player.current_animation_length * 0.35, true)
						skeleton.force_update_all_bone_transforms()
						if old_model:
							var old_player := old_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
							old_player.play(clip)
							old_player.seek(old_player.current_animation_length * 0.35, true)
						await create_timer(0.02).timeout
						var expected := skeleton.global_transform * skeleton.get_bone_global_pose(head_index)
						check(socket.global_transform.is_equal_approx(expected), def.id + " face follows " + clip)
						check(mounted_mesh.global_transform.is_equal_approx(expected * rest_inverse), def.id + " keeps face orientation in " + clip)
						if old_model:
							var old_rig := old_model.find_child("Skeleton3D", true, false) as Skeleton3D
							var old_head := old_model.find_child("Head", true, false) as MeshInstance3D
							var old_index := old_rig.find_bone("head")
							var old_skin_transform := old_rig.global_transform * old_rig.get_bone_global_pose(old_index) * old_rig.get_bone_global_rest(old_index).affine_inverse()
							var old_center := old_skin_transform * old_head.mesh.get_aabb().get_center()
							var new_center := mounted_mesh.global_transform * mounted_mesh.mesh.get_aabb().get_center()
							check(old_center.distance_to(new_center) < 0.0001, def.id + " matches legacy head center in " + clip)
			if old_model:
				old_model.free()
			character.free()
	for index in range(1, 5):
		var old_scene := load("res://assets/characters/generated/charcter%03d/character.glb" % index) as PackedScene
		var body_scene := load("res://assets/characters/modular/body/%03d/model.glb" % index) as PackedScene
		var old_model := old_scene.instantiate()
		var body_model := body_scene.instantiate()
		root.add_child(old_model)
		root.add_child(body_model)
		var old_rig := old_model.find_child("Skeleton3D", true, false) as Skeleton3D
		var body_rig := body_model.find_child("Skeleton3D", true, false) as Skeleton3D
		var old_player := old_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var body_player := body_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(old_rig.get_bone_count() == body_rig.get_bone_count(), "body %d preserves rig" % index)
		for clip in ["idle", "walk", "attack", "hit"]:
			old_player.play(clip)
			body_player.play(clip)
			old_player.seek(old_player.current_animation_length * 0.35, true)
			body_player.seek(body_player.current_animation_length * 0.35, true)
			var old_pose := old_rig.get_bone_global_pose(old_rig.find_bone("head"))
			var body_pose := body_rig.get_bone_global_pose(body_rig.find_bone("head"))
			check(old_pose.is_equal_approx(body_pose), "body %d preserves %s head pose" % [index, clip])
		old_model.free()
		body_model.free()
		var scene := load("res://scenes/characters/tripo_roster/charcter%03d.tscn" % index) as PackedScene
		var actor := scene.instantiate()
		root.add_child(actor)
		check(actor.find_child("FaceSocket", true, false) != null, "roster %d builds modular model" % index)
		check(actor.animation_player != null and actor.animation_player.has_animation("idle"), "roster %d plays animation" % index)
		check(actor.set_expression("smile"), "roster %d routes expressions" % index)
		actor.free()
		var unit := BattleUnit.new()
		unit.configure("test_%d" % index, "Test", Vector2i.ZERO, "player")
		unit.setup_visual("res://scenes/characters/tripo_roster/charcter%03d.tscn" % index)
		root.add_child(unit)
		check(unit.animation_player != null and unit.animation_player.has_animation("idle"), "battle unit %d uses modular visual" % index)
		check(unit.set_expression("angry"), "battle unit %d routes expressions" % index)
		unit.free()
	var crowd := Node3D.new()
	root.add_child(crowd)
	var crowd_definition := load("res://assets/characters/modular/definitions/charcter001.tres") as CharacterDefinition
	for index in 60:
		var character := CharacterAssembler.assemble(crowd_definition)
		crowd.add_child(character)
	check(crowd.get_child_count() == 60 and crowd.find_children("*", "Skeleton3D", true, false).size() == 60, "60 characters instantiate with one rig each")
	var mesh_nodes := crowd.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.size() >= 120:
		check((mesh_nodes[0] as MeshInstance3D).mesh == (mesh_nodes[2] as MeshInstance3D).mesh, "crowd shares imported Body mesh resource")
		check((mesh_nodes[0] as MeshInstance3D).get_active_material(0) == (mesh_nodes[2] as MeshInstance3D).get_active_material(0), "crowd shares toon material")
		check((mesh_nodes[1] as MeshInstance3D).mesh == (mesh_nodes[3] as MeshInstance3D).mesh, "crowd shares imported Face mesh resource")
		check((mesh_nodes[1] as MeshInstance3D).get_active_material(0) != (mesh_nodes[3] as MeshInstance3D).get_active_material(0), "crowd owns independent expression material")
		var first := crowd.get_child(0) as AssembledCharacter
		var second := crowd.get_child(1) as AssembledCharacter
		var third := crowd.get_child(2) as AssembledCharacter
		first.set_expression("angry")
		third.set_expression("smile")
		var first_controller := first.get_node("ExpressionController") as ExpressionController
		var second_controller := second.get_node("ExpressionController") as ExpressionController
		var third_controller := third.get_node("ExpressionController") as ExpressionController
		check(first_controller.current_eyes == "angry" and second_controller.current_eyes == "normal" and third_controller.current_eyes == "happy", "same Face instances keep separate expression state")
	print("MODULAR_PARTS: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
