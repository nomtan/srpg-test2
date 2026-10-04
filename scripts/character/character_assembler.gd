class_name CharacterAssembler
extends RefCounted
## Builds one visual at spawn time from independently imported GLBs.

const PART_ROOT := "res://assets/characters/modular"
const CHARACTER_TOON := preload("res://assets/characters/_shared/materials/character_toon.gdshader")
## Global switch for the eyes / eyebrows / mouth overlay. Temporarily off.
const SHOW_FACE_FEATURES := false
static var _toon_materials: Dictionary = {}


static func clear_cached_materials() -> void:
	# Primarily for deterministic headless test shutdown and editor reloads.
	_toon_materials.clear()


static func assemble(definition: CharacterDefinition) -> Node3D:
	if definition == null:
		push_error("CharacterAssembler requires a CharacterDefinition")
		return null
	var body_path := _part_path("body", definition.body_id)
	var face_path := _part_path("face", definition.face_id)
	if body_path.is_empty() or face_path.is_empty():
		push_error("Invalid character part IDs for %s" % definition.id)
		return null
	var body_scene := load(body_path) as PackedScene
	var face_scene := load(face_path) as PackedScene
	if body_scene == null or face_scene == null:
		push_error("Missing character part GLB for %s" % definition.id)
		return null
	var body := body_scene.instantiate() as Node3D
	var face := face_scene.instantiate() as Node3D
	if body == null or face == null:
		if body: body.free()
		if face: face.free()
		push_error("Invalid character part scene for %s" % definition.id)
		return null
	if not _is_static_part(face):
		body.free()
		face.free()
		push_error("Face must contain no Skeleton3D or AnimationPlayer: %s" % definition.id)
		return null
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	var players := body.find_children("*", "AnimationPlayer", true, false)
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D if skeletons.size() == 1 else null
	var player: AnimationPlayer = players[0] as AnimationPlayer if players.size() == 1 else null
	if skeleton == null or skeleton.find_bone("head") < 0 or player == null:
		body.free()
		face.free()
		push_error("Body %s requires one Skeleton3D with head and one AnimationPlayer" % definition.body_id)
		return null
	for required_clip in ["idle", "walk", "attack", "hit"]:
		if not player.has_animation(required_clip):
			body.free()
			face.free()
			push_error("Body %s is missing %s" % [definition.body_id, required_clip])
			return null
	var character := AssembledCharacter.new()
	character.name = "Character"
	body.name = "Body"
	character.add_child(body)
	var socket := BoneAttachment3D.new()
	socket.name = "FaceSocket"
	socket.bone_name = "head"
	skeleton.add_child(socket)
	face.name = "Face"
	socket.add_child(face)
	# Face mesh coordinates are in the Body skeleton's rest space. Cancel the
	# imported head rest transform once, then let the socket supply each pose.
	var rest_inverse := skeleton.get_bone_global_rest(skeleton.find_bone("head")).affine_inverse()
	face.transform = rest_inverse
	_apply_toon(body)
	_apply_toon(face)
	var expression_controller := ExpressionController.new()
	expression_controller.name = "ExpressionController"
	character.add_child(expression_controller)
	# Face004 is a closed helmet, so facial features should not appear on its visor.
	if not expression_controller.bind_face(face, definition.expression_profile_id, SHOW_FACE_FEATURES and definition.face_id != "face004"):
		character.free()
		return null
	for clip in ["idle", "walk"]:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return character


static func _is_static_part(part: Node3D) -> bool:
	return not (part is Skeleton3D) and part.find_children("*", "Skeleton3D", true, false).is_empty() and part.find_children("*", "AnimationPlayer", true, false).is_empty()


static func _part_path(kind: String, id: String) -> String:
	if not id.begins_with(kind):
		return ""
	var number := id.trim_prefix(kind)
	if number.length() != 3 or not number.is_valid_int() or int(number) <= 0:
		return ""
	return "%s/%s/%03d/model.glb" % [PART_ROOT, kind, int(number)]


static func _apply_toon(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var semantic := _material_semantic(source.resource_name)
			var key := "%s:%s" % [source.albedo_texture.get_instance_id(), semantic]
			if not _toon_materials.has(key):
				var toon := ShaderMaterial.new()
				toon.resource_name = semantic
				toon.shader = CHARACTER_TOON
				toon.set_shader_parameter("base_color_texture", source.albedo_texture)
				toon.set_shader_parameter("expression_parts_enabled", false)
				toon.set_shader_parameter("expression_uv_v2", false)
				_toon_materials[key] = toon
			mesh.set_surface_override_material(surface, _toon_materials[key])


static func _material_semantic(source_name: String) -> String:
	var lowered := source_name.to_lower()
	if lowered.begins_with("head"):
		return "Head"
	if lowered.begins_with("hair"):
		return "Hair"
	return "LegacyCombined"
