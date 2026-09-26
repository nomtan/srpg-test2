class_name FaceController
extends Node

const EXPRESSIONS := ["normal", "closed", "surprised", "squint"]
const TEXTURE_ROOT := "res://assets/characters/_shared/face/face_%s/%s.png"
const FEATURE_ATLAS := "res://assets/characters/_shared/face/chibi_facial_features.png"
const VARIANT_ATLAS := "res://assets/characters/_shared/face/chibi_facial_features_variants.png"
const ATLAS_OFFSETS := {
	"normal": Vector2(0.0, 0.0),
	"closed": Vector2(0.5, 0.0),
	"surprised": Vector2(0.0, 0.5),
	"squint": Vector2(0.5, 0.5),
}

const REST_ATTRIBUTES_META := &"face_rest_attributes"
const FACE_002_RAISE_METERS := 0.05

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
	var model_scale_y := 1.0
	if character is Node3D:
		model_scale_y = (character as Node3D).global_transform.basis.get_scale().y
	var face_rect := Vector4(-0.23, 0.96 - 0.2 / maxf(model_scale_y, 0.001), 0.46, 0.32)
	var heads := character.find_children("Head", "MeshInstance3D", true, false)
	for head_node in heads:
		var head := head_node as MeshInstance3D
		if head.mesh == null:
			continue
		if face_id == "002":
			# Project from the bind pose so features sway with the skinned head.
			var rest_mesh := _with_rest_attributes(head.mesh)
			if rest_mesh != null:
				head.mesh = rest_mesh
		for surface in head.mesh.get_surface_count():
			var source := head.get_active_material(surface) as ShaderMaterial
			if source == null:
				continue
			var material := source.duplicate() as ShaderMaterial
			head.set_surface_override_material(surface, material)
			material.set_shader_parameter("expression_uv_scale", expression_uv_scale)
			material.set_shader_parameter("expression_uv_offset", expression_uv_offset)
			if face_id == "001" or face_id == "002":
				material.set_shader_parameter("expression_projected", true)
				material.set_shader_parameter("expression_face_rect", face_rect)
				if face_id == "002":
					# Face 002 includes the fringe in Head; keep the artwork on the face surface.
					material.set_shader_parameter("expression_surface_depth", Vector2(0.18, 0.32))
					# Face 002 artwork scale around the face center.
					material.set_shader_parameter("expression_feature_scale", 0.95)
					material.set_shader_parameter("expression_rest_custom", head.mesh.has_meta(REST_ATTRIBUTES_META))
					# Raise the artwork by FACE_002_RAISE_METERS in world space (rect is in Head mesh space).
					var head_scale_y := maxf(head.global_transform.basis.get_scale().y, 0.001)
					var raised_rect := face_rect + Vector4(0.0, FACE_002_RAISE_METERS / head_scale_y, 0.0, 0.0)
					material.set_shader_parameter("expression_face_rect", raised_rect)
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
			if face_id == "001" or face_id == "002":
				material.set_shader_parameter("expression_atlas_offset", ATLAS_OFFSETS[expression])


func _get_texture(expression: String) -> Texture2D:
	if texture_cache.has(expression):
		return texture_cache[expression] as Texture2D
	if face_id == "001" or face_id == "002":
		var atlas_path := FEATURE_ATLAS if expression == "normal" else VARIANT_ATLAS
		var atlas := load(atlas_path) as Texture2D if ResourceLoader.exists(atlas_path) else null
		texture_cache[expression] = atlas
		return atlas
	var path := TEXTURE_ROOT % [face_id, expression]
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	texture_cache[expression] = texture
	return texture


func _with_rest_attributes(mesh: Mesh) -> ArrayMesh:
	# Copy the mesh with bind-pose position/normal in CUSTOM0/CUSTOM1.
	if mesh.has_meta(REST_ATTRIBUTES_META):
		return mesh as ArrayMesh
	var source := mesh as ArrayMesh
	if source == null:
		return null
	var result := ArrayMesh.new()
	result.blend_shape_mode = source.blend_shape_mode
	for index in source.get_blend_shape_count():
		result.add_blend_shape(source.get_blend_shape_name(index))
	var custom_format := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) 		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var rest_position := PackedFloat32Array()
		var rest_normal := PackedFloat32Array()
		rest_position.resize(vertices.size() * 4)
		rest_normal.resize(vertices.size() * 4)
		for vertex in vertices.size():
			var normal := normals[vertex] if vertex < normals.size() else Vector3.BACK
			for axis in 3:
				rest_position[vertex * 4 + axis] = vertices[vertex][axis]
				rest_normal[vertex * 4 + axis] = normal[axis]
		arrays[Mesh.ARRAY_CUSTOM0] = rest_position
		arrays[Mesh.ARRAY_CUSTOM1] = rest_normal
		var flags := custom_format | (source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays,
			source.surface_get_blend_shape_arrays(surface), {}, flags)
		result.surface_set_material(surface, source.surface_get_material(surface))
		result.surface_set_name(surface, source.surface_get_name(surface))
	result.set_meta(REST_ATTRIBUTES_META, true)
	return result
