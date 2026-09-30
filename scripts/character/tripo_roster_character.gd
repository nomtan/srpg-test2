extends Node3D
## Roster actor backed by a CharacterDefinition and a shared Body/Face assembler.

@export var character_id := ""
@export var display_name := ""
@export var definition: CharacterDefinition
@export var dialogue: PackedStringArray = ["一緒に冒険へ出かけましょう。"]
@export var face_texture: Texture2D

var animation_player: AnimationPlayer
var face: MeshInstance3D
var face_socket: BoneAttachment3D
var _assembled := false


func prepare_visual() -> void:
	if _assembled or definition == null:
		return
	var assembled := CharacterAssembler.assemble(definition)
	if assembled:
		$Model.add_child(assembled)
		_assembled = true


func _ready() -> void:
	prepare_visual()
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	face_socket = find_child("FaceSocket", true, false) as BoneAttachment3D
	if face_socket:
		var meshes := face_socket.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			face = meshes[0] as MeshInstance3D
	if face_texture:
		set_face_texture(face_texture)
	play_animation("idle")


func play_animation(clip: String) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, 0.15)
	return true


func set_face_texture(texture: Texture2D) -> bool:
	if face == null or texture == null:
		return false
	var material := face.get_active_material(0) as ShaderMaterial
	if material == null:
		return false
	# The assembler already gives this Face an instance-owned material.
	material.set_shader_parameter("base_color_texture", texture)
	return true


func set_expression(expression: String) -> bool:
	var character := $Model.get_child(0) as AssembledCharacter if $Model.get_child_count() > 0 else null
	return character.set_expression(expression) if character != null else false


func set_eyes(value: String) -> bool:
	var character := $Model.get_child(0) as AssembledCharacter if $Model.get_child_count() > 0 else null
	return character.set_eyes(value) if character != null else false


func set_eyebrows(value: String) -> bool:
	var character := $Model.get_child(0) as AssembledCharacter if $Model.get_child_count() > 0 else null
	return character.set_eyebrows(value) if character != null else false


func set_mouth(value: String) -> bool:
	var character := $Model.get_child(0) as AssembledCharacter if $Model.get_child_count() > 0 else null
	return character.set_mouth(value) if character != null else false
