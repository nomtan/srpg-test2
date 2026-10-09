class_name ExpressionController
extends Node

const ROOT := "res://assets/characters/_shared/face/expression"
const EYES := ["normal", "blink", "closed_strong", "angry", "sad", "surprised", "narrow", "happy"]
const EYEBROWS := ["normal", "angry", "sad", "worried", "surprised", "confident"]
const MOUTH := ["normal", "smile", "laugh", "open", "angry", "sad", "smirk"]
const ATLAS_PATHS := [ROOT + "/eyes_atlas.svg", ROOT + "/eyebrows_atlas.svg", ROOT + "/mouth_atlas.svg"]
## Legacy projected Faces wear Face002's painted features (build_face002_feature_atlases.py)
## over Face002's shared face_rect, so they match Face002 in position and texture.
const LEGACY_ATLAS_PATHS := [ROOT + "/legacy_eyes_atlas.png", ROOT + "/legacy_eyebrows_atlas.png", ROOT + "/legacy_mouth_atlas.png"]
const PARAMETERS := [&"eyes_row", &"eyebrows_row", &"mouth_row"]

var current_expression := "normal"
var current_eyes := "normal"
var current_eyebrows := "normal"
var current_mouth := "normal"
var _materials: Array[ShaderMaterial] = []
static var _atlases: Array[Texture2D] = []
static var _legacy_atlases: Array[Texture2D] = []


func bind_face(face: Node3D, profile_id := "", show_features := true) -> bool:
	_materials.clear()
	if profile_id.is_empty():
		for node in face.find_children("*", "MeshInstance3D", true, false):
			if node.has_meta("expression_profile"):
				profile_id = str(node.get_meta("expression_profile"))
				break
			# The glTF importer stores node extras as one "extras" dictionary.
			var extras = node.get_meta("extras", {})
			if extras is Dictionary and extras.has("expression_profile"):
				profile_id = str(extras["expression_profile"])
				break
	if _atlases.is_empty():
		for path in ATLAS_PATHS:
			_atlases.append(load(path) as Texture2D)
		for path in LEGACY_ATLAS_PATHS:
			_legacy_atlases.append(load(path) as Texture2D)
	if (_atlases + _legacy_atlases).any(func(atlas: Texture2D) -> bool: return atlas == null):
		push_error("Expression atlases are missing")
		return false
	var profile_path := ROOT + "/profiles/%s.tres" % (profile_id if not profile_id.is_empty() else "default")
	var profile := load(profile_path) as ExpressionProfile
	if profile == null:
		push_error("Missing expression profile: " + profile_path)
		return false
	var has_head := false
	var has_hair := false
	var has_unknown := false
	var meshes: Array[Node] = face.find_children("*", "MeshInstance3D", true, false)
	if face is MeshInstance3D:
		meshes.push_front(face)
	for child in meshes:
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			var semantic := source.resource_name if source != null else ""
			has_head = has_head or semantic.begins_with("Head")
			has_hair = has_hair or semantic.begins_with("Hair")
			has_unknown = has_unknown or not (semantic.begins_with("Head") or semantic.begins_with("Hair"))
	# Legacy exports can call their single combined surface Head. Hair is the
	# explicit separation marker; UV2 is also a v2 marker on Head-only assets.
	var uv_v2 := has_hair
	for child in meshes:
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			if mesh.get_active_material(surface) != null and mesh.get_active_material(surface).resource_name.begins_with("Head"):
				uv_v2 = uv_v2 or (mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
	if uv_v2 and (not has_head or not has_hair or has_unknown):
		push_error("Separated Face requires only Head* and Hair* surfaces")
		return false
	# Validate the entire asset before creating per-instance expression materials.
	if uv_v2:
		for child in meshes:
			var mesh := child as MeshInstance3D
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				if not mesh.get_active_material(surface).resource_name.begins_with("Head"):
					continue
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				if uv.size() != vertices.size() or colors.size() != vertices.size():
					push_error("Head requires ExpressionUV and ExpressionMask")
					return false
	for child in meshes:
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as ShaderMaterial
			if source == null:
				continue
			# Standard v1 faces name surfaces Head* / Hair*. Legacy reference
			# faces have one combined surface and remain compatible.
			if source.resource_name.begins_with("Hair"):
				continue
			if uv_v2 and not source.resource_name.begins_with("Head"):
				continue
			var material := source.duplicate() as ShaderMaterial
			mesh.set_surface_override_material(surface, material)
			material.set_shader_parameter("expression_face_rect", profile.face_rect)
			material.set_shader_parameter("expression_surface_depth", profile.surface_depth)
			material.set_shader_parameter("expression_skin_depth", profile.skin_depth)
			material.set_shader_parameter("expression_skin_depth_enabled", profile.skin_depth != null)
			var atlases := _atlases if uv_v2 else _legacy_atlases
			material.set_shader_parameter("eyes_atlas", atlases[0])
			material.set_shader_parameter("eyebrows_atlas", atlases[1])
			material.set_shader_parameter("mouth_atlas", atlases[2])
			material.set_shader_parameter("expression_parts_enabled", show_features)
			material.set_shader_parameter("expression_uv_v2", uv_v2)
			_materials.append(material)
	if _materials.is_empty():
		push_error("Face has no toon material for expressions")
		return false
	set_expression("normal")
	return true


func set_expression(expression: String) -> bool:
	if not expression.is_valid_filename():
		return false
	var path := ROOT + "/definitions/expression_%s.tres" % expression
	var definition := load(path) as ExpressionDefinition if ResourceLoader.exists(path) else null
	if definition == null:
		push_warning("Unknown expression: " + expression)
		return false
	if not EYES.has(definition.eyes) or not EYEBROWS.has(definition.eyebrows) or not MOUTH.has(definition.mouth):
		push_warning("Invalid expression definition: " + expression)
		return false
	current_expression = expression
	set_eyes(definition.eyes)
	set_eyebrows(definition.eyebrows)
	set_mouth(definition.mouth)
	return true


func set_eyes(value: String) -> bool:
	return _set_part(value, EYES, PARAMETERS[0])


func set_eyebrows(value: String) -> bool:
	return _set_part(value, EYEBROWS, PARAMETERS[1])


func set_mouth(value: String) -> bool:
	return _set_part(value, MOUTH, PARAMETERS[2])


func _set_part(value: String, choices: Array, parameter: StringName) -> bool:
	var index := choices.find(value)
	if index < 0:
		push_warning("Unknown expression part: " + value)
		return false
	if parameter == PARAMETERS[0]: current_eyes = value
	elif parameter == PARAMETERS[1]: current_eyebrows = value
	else: current_mouth = value
	for material in _materials:
		material.set_shader_parameter(parameter, float(index))
	return true
