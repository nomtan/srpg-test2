class_name FaceController
extends Node

const EXPRESSIONS := ["normal", "closed", "surprised", "squint"]
const TEXTURE_ROOT := "res://assets/characters/_shared/face/face_%s/%s.png"

var face_id := ""
var current_expression := "normal"
var head_materials: Array[ShaderMaterial] = []
var texture_cache: Dictionary = {}
var expression_uv_scale := Vector2.ONE
var expression_uv_offset := Vector2.ZERO
var _blink_timer: SceneTreeTimer
var _blink_serial := 0


func bind_character(character: Node, requested_face_id: String, initial_expression := "normal", uv_scale := Vector2.ONE, uv_offset := Vector2.ZERO) -> bool:
	face_id = requested_face_id
	expression_uv_scale = uv_scale
	expression_uv_offset = uv_offset
	head_materials.clear()
	texture_cache.clear()
	var heads := character.find_children("Head", "MeshInstance3D", true, false)
	for head_node in heads:
		var head := head_node as MeshInstance3D
		if head.mesh == null:
			continue
		for surface in head.mesh.get_surface_count():
			var source := head.get_active_material(surface) as ShaderMaterial
			if source == null:
				continue
			var material := source.duplicate() as ShaderMaterial
			head.set_surface_override_material(surface, material)
			material.set_shader_parameter("expression_uv_scale", expression_uv_scale)
			material.set_shader_parameter("expression_uv_offset", expression_uv_offset)
			head_materials.append(material)
	if head_materials.is_empty():
		push_warning("FaceController: no Head ShaderMaterial found")
		return false
	for expression in EXPRESSIONS:
		_get_texture(expression)
	set_expression(initial_expression)
	return true


func set_expression(expression: String) -> void:
	if not EXPRESSIONS.has(expression):
		push_warning("FaceController: unknown expression '%s'" % expression)
		return
	current_expression = expression
	if _blink_serial == 0:
		_apply_expression(expression)


func reset_expression() -> void:
	set_expression("normal")


func blink() -> void:
	if head_materials.is_empty():
		return
	_blink_serial += 1
	var serial := _blink_serial
	_apply_expression("closed")
	await get_tree().create_timer(0.12).timeout
	if is_inside_tree() and _blink_serial == serial:
		_blink_serial = 0
		_apply_expression(current_expression)


func _apply_expression(expression: String) -> void:
	var texture := _get_texture(expression)
	if texture == null and expression != "normal":
		texture = _get_texture("normal")
	for material in head_materials:
		material.set_shader_parameter("expression_enabled", texture != null)
		if texture != null:
			material.set_shader_parameter("expression_texture", texture)


func _get_texture(expression: String) -> Texture2D:
	if texture_cache.has(expression):
		return texture_cache[expression] as Texture2D
	var path := TEXTURE_ROOT % [face_id, expression]
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	texture_cache[expression] = texture
	return texture
