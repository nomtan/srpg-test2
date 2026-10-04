extends SceneTree
## Standard v1 runtime verification. Run after editor import with Godot --headless.

const REGISTRY_PATH := "res://assets/characters/modular/registry.json"
const REQUIRED_CLIPS := ["idle", "walk", "attack", "hit"]

var failed := false


func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: ", description)
	else:
		failed = true
		push_error(description)


func _initialize() -> void:
	call_deferred("run")


func _load_registry() -> Dictionary:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return {}
	var value = JSON.parse_string(file.get_as_text())
	return value as Dictionary if value is Dictionary else {}


func _number(part_id: String, kind: String) -> String:
	return part_id.trim_prefix(kind)


func _legacy_path(number: String) -> String:
	return "res://assets/characters/generated/charcter%s/character.glb" % number


func _definition(body_id: String, face_id: String, test_id: String) -> CharacterDefinition:
	var definition := CharacterDefinition.new()
	definition.id = test_id
	definition.body_id = body_id
	definition.face_id = face_id
	return definition


func run() -> void:
	var registry := _load_registry()
	check(not registry.is_empty(), "asset registry loads")
	if registry.is_empty():
		quit(1)
		return
	var reference: Dictionary = registry.get("reference_set", {})
	var body_ids: Array = reference.get("bodies", [])
	var face_ids: Array = reference.get("faces", [])
	var legacy_characters: Array = registry.get("legacy_characters", [])
	var roster_characters: Array = registry.get("roster_characters", [])
	check(body_ids.size() == 6 and face_ids.size() == 6, "registry declares the 6 Body x 6 Face reference set")
	await _verify_combinations(body_ids, face_ids, legacy_characters)
	await _verify_legacy_regression(legacy_characters)
	await _verify_roster_and_battle(roster_characters)
	await _verify_mixed_crowd(body_ids, face_ids)
	CharacterAssembler.clear_cached_materials()
	print("MODULAR_PARTS: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)


func _verify_combinations(body_ids: Array, face_ids: Array, legacy_characters: Array) -> void:
	var combination_count := 0
	for body_value in body_ids:
		for face_value in face_ids:
			var body_id := str(body_value)
			var face_id := str(face_value)
			var definition := _definition(body_id, face_id, "test_%s_%s" % [body_id, face_id])
			var character := CharacterAssembler.assemble(definition)
			check(character != null, definition.id + " assembles")
			if character == null:
				continue
			combination_count += 1
			root.add_child(character)
			var skeletons := character.find_children("*", "Skeleton3D", true, false)
			var players := character.find_children("*", "AnimationPlayer", true, false)
			var meshes := character.find_children("*", "MeshInstance3D", true, false)
			var socket := character.find_child("FaceSocket", true, false) as BoneAttachment3D
			var face := character.find_child("Face", true, false) as Node3D
			var body_number := _number(body_id, "body")
			var face_number := _number(face_id, "face")
			var legacy_id := "charcter" + body_number
			var old_model: Node3D
			if body_number == face_number and legacy_characters.has(legacy_id):
				old_model = (load(_legacy_path(body_number)) as PackedScene).instantiate()
				root.add_child(old_model)
			check(skeletons.size() == 1 and players.size() == 1, definition.id + " has one rig and player")
			check(meshes.size() == 2 and meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.get_active_material(0) is ShaderMaterial), definition.id + " keeps Body/Face meshes and toon materials")
			check(socket != null and face != null and socket.is_ancestor_of(face), definition.id + " attaches Face to head")
			var expression_controller := character.find_child("ExpressionController", true, false) as ExpressionController
			check(expression_controller != null, definition.id + " has ExpressionController")
			if expression_controller != null:
				var face_material := (meshes[1] as MeshInstance3D).get_active_material(0)
				check(face_material.get_shader_parameter("expression_parts_enabled") == (CharacterAssembler.SHOW_FACE_FEATURES and face_id != "face004"), definition.id + " preserves legacy helmet expression policy")
				for expression in ["normal", "angry", "smile"]:
					check(character.set_expression(expression), definition.id + " accepts " + expression)
				check(character.set_eyes("blink"), definition.id + " blinks")
				check(character.set_eyebrows("confident"), definition.id + " changes eyebrows only")
				check(character.set_mouth("open"), definition.id + " opens mouth")
				check(expression_controller.current_eyes == "blink" and expression_controller.current_eyebrows == "confident" and expression_controller.current_mouth == "open", definition.id + " keeps independent expression channels")
				check(character.find_children("*", "MeshInstance3D", true, false).size() == meshes.size() and (meshes[1] as MeshInstance3D).get_active_material(0) == face_material, definition.id + " changes expression without allocating mesh or material")
			if skeletons.size() == 1 and players.size() == 1 and socket and face:
				var skeleton := skeletons[0] as Skeleton3D
				var player := players[0] as AnimationPlayer
				var head_index := skeleton.find_bone("head")
				check(head_index >= 0, definition.id + " has head bone")
				var rest_inverse := skeleton.get_bone_global_rest(head_index).affine_inverse()
				check(face.transform.is_equal_approx(rest_inverse), definition.id + " cancels imported head rest")
				var mounted_mesh := face.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
				for clip in REQUIRED_CLIPS:
					check(player.has_animation(clip), definition.id + " has " + clip)
					if player.has_animation(clip):
						player.play(clip)
						player.seek(player.current_animation_length * 0.35, true)
						skeleton.force_update_all_bone_transforms()
						if old_model:
							var old_player := old_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
							old_player.play(clip)
							old_player.seek(old_player.current_animation_length * 0.35, true)
						await create_timer(0.01).timeout
						var expected := skeleton.global_transform * skeleton.get_bone_global_pose(head_index)
						check(socket.global_transform.is_equal_approx(expected), definition.id + " Face follows " + clip)
						check(mounted_mesh.global_transform.is_equal_approx(expected * rest_inverse), definition.id + " Face keeps rest orientation in " + clip)
						if old_model:
							var old_rig := old_model.find_child("Skeleton3D", true, false) as Skeleton3D
							var old_head := old_model.find_child("Head", true, false) as MeshInstance3D
							var old_index := old_rig.find_bone("head")
							var old_skin_transform := old_rig.global_transform * old_rig.get_bone_global_pose(old_index) * old_rig.get_bone_global_rest(old_index).affine_inverse()
							var old_local_center := old_head.mesh.get_aabb().get_center()
							var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/modular/face/%s/normalization.json" % face_number))
							if metadata.has("size_baseline"):
								var position: Array = metadata["position"]
								var pivot := Vector3(position[0], position[2], -position[1])
								var factor: float = metadata["scale"] / metadata["size_baseline"]["scale"]
								old_local_center = pivot + (old_local_center - pivot) * factor
							var old_center := old_skin_transform * old_local_center
							var new_center := mounted_mesh.global_transform * mounted_mesh.mesh.get_aabb().get_center()
							check(old_center.distance_to(new_center) < 0.0001, definition.id + " matches authorized Face size transform in " + clip)
			if old_model:
				old_model.free()
			character.free()
	check(combination_count == body_ids.size() * face_ids.size(), "all 36 registry combinations assemble")


func _verify_legacy_regression(legacy_characters: Array) -> void:
	for value in legacy_characters:
		var character_id := str(value)
		var number := character_id.trim_prefix("charcter")
		var old_scene := load(_legacy_path(number)) as PackedScene
		var body_scene := load("res://assets/characters/modular/body/%s/model.glb" % number) as PackedScene
		var old_model := old_scene.instantiate()
		var body_model := body_scene.instantiate()
		root.add_child(old_model)
		root.add_child(body_model)
		var old_rig := old_model.find_child("Skeleton3D", true, false) as Skeleton3D
		var body_rig := body_model.find_child("Skeleton3D", true, false) as Skeleton3D
		var old_player := old_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var body_player := body_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		check(old_rig.get_bone_count() == body_rig.get_bone_count(), character_id + " preserves rig")
		for clip in REQUIRED_CLIPS:
			old_player.play(clip)
			body_player.play(clip)
			old_player.seek(old_player.current_animation_length * 0.35, true)
			body_player.seek(body_player.current_animation_length * 0.35, true)
			var old_pose := old_rig.get_bone_global_pose(old_rig.find_bone("head"))
			var body_pose := body_rig.get_bone_global_pose(body_rig.find_bone("head"))
			check(old_pose.is_equal_approx(body_pose), character_id + " preserves " + clip + " head pose")
		old_model.free()
		body_model.free()


func _verify_roster_and_battle(roster_characters: Array) -> void:
	for value in roster_characters:
		var character_id := str(value)
		var path := "res://scenes/characters/tripo_roster/%s.tscn" % character_id
		var scene := load(path) as PackedScene
		var actor := scene.instantiate()
		root.add_child(actor)
		check(actor.find_child("FaceSocket", true, false) != null, character_id + " roster scene builds modular model")
		check(actor.animation_player != null and actor.animation_player.has_animation("idle"), character_id + " roster scene plays animation")
		check(actor.set_expression("smile"), character_id + " roster scene routes expressions")
		actor.free()
		var unit := BattleUnit.new()
		unit.configure("test_" + character_id, "Test", Vector2i.ZERO, "player")
		# Weapon clip installation is covered by its own tests; keep this check
		# focused on the modular visual and avoid allocating transient FX nodes.
		unit.setup_visual(path, 1.0, 0.0, 0.0, false, "")
		root.add_child(unit)
		check(unit.animation_player != null and unit.animation_player.has_animation("idle"), character_id + " BattleUnit uses modular visual")
		check(unit.set_expression("angry"), character_id + " BattleUnit routes expressions")
		unit.free()


func _verify_mixed_crowd(body_ids: Array, face_ids: Array) -> void:
	var crowd := Node3D.new()
	root.add_child(crowd)
	for index in 60:
		var type_index: int = index % mini(body_ids.size(), face_ids.size())
		var character := CharacterAssembler.assemble(_definition(str(body_ids[type_index]), str(face_ids[type_index]), "crowd_%d" % index))
		crowd.add_child(character)
	check(crowd.get_child_count() == 60 and crowd.find_children("*", "Skeleton3D", true, false).size() == 60, "60 mixed characters instantiate with one independent rig each")
	var mesh_nodes := crowd.find_children("*", "MeshInstance3D", true, false)
	check(mesh_nodes.size() == 120, "60 mixed characters use two mesh nodes each")
	if mesh_nodes.size() == 120:
		var first_body := mesh_nodes[0] as MeshInstance3D
		var first_face := mesh_nodes[1] as MeshInstance3D
		var repeated_body := mesh_nodes[12] as MeshInstance3D
		var repeated_face := mesh_nodes[13] as MeshInstance3D
		check(first_body.mesh == repeated_body.mesh, "same Body type shares imported mesh resource")
		check(first_body.get_active_material(0) == repeated_body.get_active_material(0), "same Body type shares toon material")
		check(first_face.mesh == repeated_face.mesh, "same Face type shares imported mesh resource")
		check(first_face.get_active_material(0) != repeated_face.get_active_material(0), "same Face type owns independent expression material")
		var first := crowd.get_child(0) as AssembledCharacter
		var second := crowd.get_child(6) as AssembledCharacter
		var third := crowd.get_child(12) as AssembledCharacter
		first.set_expression("angry")
		second.set_expression("normal")
		third.set_expression("smile")
		var first_controller := first.get_node("ExpressionController") as ExpressionController
		var second_controller := second.get_node("ExpressionController") as ExpressionController
		var third_controller := third.get_node("ExpressionController") as ExpressionController
		check(first_controller.current_eyes == "angry" and second_controller.current_eyes == "normal" and third_controller.current_eyes == "happy", "same Face instances keep angry/normal/smile state isolated")
		var unique_meshes := {}
		var unique_materials := {}
		var unique_textures := {}
		var triangle_total := 0
		for mesh_value in mesh_nodes:
			var mesh_node := mesh_value as MeshInstance3D
			unique_meshes[mesh_node.mesh.get_instance_id()] = true
			for surface in mesh_node.mesh.get_surface_count():
				triangle_total += mesh_node.mesh.surface_get_array_index_len(surface) / 3
				var material := mesh_node.get_active_material(surface) as ShaderMaterial
				if material:
					unique_materials[material.get_instance_id()] = true
					var texture := material.get_shader_parameter("base_color_texture") as Texture2D
					if texture:
						unique_textures[texture.get_instance_id()] = true
		print("PERFORMANCE: meshes=", mesh_nodes.size(), " unique_meshes=", unique_meshes.size(), " unique_materials=", unique_materials.size(), " unique_textures=", unique_textures.size(), " triangles=", triangle_total)
		check(unique_meshes.size() == 12, "60-unit reference mix shares 6 Body and 6 Face mesh resources")
		check(unique_textures.size() <= 14, "60-unit reference mix shares source textures")
		check(triangle_total > 0, "60-unit performance report records triangle total")
