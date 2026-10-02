extends SceneTree
## Channel round-trip and isolation fixture. Does not claim Face007 art approval.

var failed := false

func check(ok: bool, description: String) -> void:
	print("PASS: " if ok else "FAIL: ", description)
	failed = failed or not ok

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file("res://artifacts/expression_v2_fixture/model.glb", state) != OK:
		quit(1)
		return
	var imported := document.generate_scene(state)
	var scene := PackedScene.new()
	scene.pack(imported)
	imported.free()
	var faces: Array[Node3D] = []
	var heads: Array[MeshInstance3D] = []
	var hairs: Array[MeshInstance3D] = []
	var controllers: Array[ExpressionController] = []
	for index in 60:
		var face := scene.instantiate() as Node3D
		root.add_child(face)
		CharacterAssembler._apply_toon(face)
		var controller := ExpressionController.new()
		face.add_child(controller)
		check(controller.bind_face(face), "fixture %d binds v2" % index)
		for node in face.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var material := mesh.get_active_material(0) as ShaderMaterial
			if material.resource_name == "Head":
				heads.append(mesh)
			else:
				hairs.append(mesh)
		faces.append(face)
		controllers.append(controller)
	check(heads.size() == 60 and hairs.size() == 60, "60 fixtures preserve Head/Hair surfaces")
	if heads.size() == 60 and hairs.size() == 60:
		var arrays := heads[0].mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		check(uv.size() == 24 and colors.size() == 24, "Blender TEXCOORD_1/COLOR_0 reach Godot UV2/COLOR")
		var enabled := false
		var excluded := false
		for color in colors:
			enabled = enabled or color.r > 0.5
			excluded = excluded or color.r < 0.5
		check(enabled and excluded, "mask retains excluded and enabled regions")
		for preset in ["normal", "angry", "smile", "sad", "surprised"]:
			check(controllers[0].set_expression(preset), "v2 accepts " + preset)
		for eyes in ExpressionController.EYES:
			check(controllers[0].set_eyes(eyes), "eyes " + eyes)
		for brows in ExpressionController.EYEBROWS:
			check(controllers[0].set_eyebrows(brows), "eyebrows " + brows)
		for mouth in ExpressionController.MOUTH:
			check(controllers[0].set_mouth(mouth), "mouth " + mouth)
		controllers[0].set_expression("angry")
		controllers[1].set_expression("normal")
		controllers[2].set_expression("smile")
		var meshes := {}
		var materials := {}
		var textures := {}
		for index in 60:
			var head := heads[index].get_active_material(0) as ShaderMaterial
			var hair := hairs[index].get_active_material(0) as ShaderMaterial
			check(head.get_shader_parameter("expression_uv_v2") == true, "Head selects UV mode")
			check(hair.get_shader_parameter("expression_parts_enabled") == false and hair.get_shader_parameter("eyes_atlas") == null, "Hair has no expression atlas")
			for mesh in [heads[index], hairs[index]]:
				meshes[mesh.mesh.get_instance_id()] = true
				var mat := mesh.get_active_material(0) as ShaderMaterial
				materials[mat.get_instance_id()] = true
				textures[mat.get_shader_parameter("base_color_texture").get_instance_id()] = true
			check(head.get_shader_parameter("eyes_atlas") == heads[0].get_active_material(0).get_shader_parameter("eyes_atlas"), "atlas is shared")
		check(heads[0].get_active_material(0).get_shader_parameter("eyes_row") == 3.0 and heads[1].get_active_material(0).get_shader_parameter("eyes_row") == 0.0 and heads[2].get_active_material(0).get_shader_parameter("eyes_row") == 7.0, "angry/normal/smile are isolated")
		check(meshes.size() == 2 and materials.size() == 61 and textures.size() == 2, "60 fixtures share mesh/base textures/Hair, with 60 independent Head materials")
		print("V2_FIXTURE_PERFORMANCE: unique_meshes=", meshes.size(), " unique_materials=", materials.size(), " unique_base_textures=", textures.size())
	for face in faces:
		face.free()
	CharacterAssembler.clear_cached_materials()
	print("EXPRESSION_V2: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
