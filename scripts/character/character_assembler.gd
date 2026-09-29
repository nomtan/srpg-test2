class_name CharacterAssembler
extends RefCounted
## Builds one visual at spawn time from independently imported GLBs.

const PART_ROOT := "res://assets/characters/modular"
const CHARACTER_TOON := preload("res://assets/characters/_shared/materials/character_toon.gdshader")
static var _toon_materials: Dictionary = {}


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
		push_error("Missing Body or Face GLB for %s" % definition.id)
		return null
	var body := body_scene.instantiate() as Node3D
	var face := face_scene.instantiate() as Node3D
	if body == null or face == null:
		push_error("Invalid Body or Face scene for %s" % definition.id)
		return null
	var skeleton := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone("head") < 0:
		body.free()
		face.free()
		push_error("Body %s requires a head bone" % definition.body_id)
		return null
	var character := Node3D.new()
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
	face.transform = skeleton.get_bone_global_rest(skeleton.find_bone("head")).affine_inverse()
	var hair_socket := Node3D.new()
	hair_socket.name = "HairSocket"
	socket.add_child(hair_socket)
	_apply_toon(body)
	_apply_toon(face)
	var player := body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for clip in ["idle", "walk"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return character


static func _part_path(kind: String, id: String) -> String:
	if not id.begins_with(kind):
		return ""
	var number := id.trim_prefix(kind)
	if not number.is_valid_int() or int(number) <= 0:
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
			var key := source.albedo_texture.get_instance_id()
			if not _toon_materials.has(key):
				var toon := ShaderMaterial.new()
				toon.shader = CHARACTER_TOON
				toon.set_shader_parameter("base_color_texture", source.albedo_texture)
				_toon_materials[key] = toon
			mesh.set_surface_override_material(surface, _toon_materials[key])
