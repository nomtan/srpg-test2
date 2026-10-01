class_name ExpressionController
extends Node

const ROOT := "res://assets/characters/_shared/face/expression"
const EYES := ["normal", "blink", "closed_strong", "angry", "sad", "surprised", "narrow", "happy"]
const EYEBROWS := ["normal", "angry", "sad", "worried", "surprised", "confident"]
const MOUTH := ["normal", "smile", "laugh", "open", "angry", "sad", "smirk"]
const ATLAS_PATHS := [ROOT + "/eyes_atlas.svg", ROOT + "/eyebrows_atlas.svg", ROOT + "/mouth_atlas.svg"]
const PARAMETERS := [&"eyes_row", &"eyebrows_row", &"mouth_row"]

var current_expression := "normal"
var current_eyes := "normal"
var current_eyebrows := "normal"
var current_mouth := "normal"
var _materials: Array[ShaderMaterial] = []
static var _atlases: Array[Texture2D] = []


func bind_face(face: Node3D, profile_id := "", show_features := true) -> bool:
	_materials.clear()
	if _atlases.is_empty():
		for path in ATLAS_PATHS:
			_atlases.append(load(path) as Texture2D)
	if _atlases.any(func(atlas: Texture2D) -> bool: return atlas == null):
		push_error("Expression atlases are missing")
		return false
	var profile_path := ROOT + "/profiles/%s.tres" % (profile_id if not profile_id.is_empty() else "default")
	var profile := load(profile_path) as ExpressionProfile
	if profile == null:
		push_error("Missing expression profile: " + profile_path)
		return false
	for child in face.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as ShaderMaterial
			if source == null:
				continue
			var material := source.duplicate() as ShaderMaterial
			mesh.set_surface_override_material(surface, material)
			material.set_shader_parameter("expression_face_rect", profile.face_rect)
			material.set_shader_parameter("expression_surface_depth", profile.surface_depth)
			material.set_shader_parameter("eyes_atlas", _atlases[0])
			material.set_shader_parameter("eyebrows_atlas", _atlases[1])
			material.set_shader_parameter("mouth_atlas", _atlases[2])
			material.set_shader_parameter("expression_parts_enabled", show_features)
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
