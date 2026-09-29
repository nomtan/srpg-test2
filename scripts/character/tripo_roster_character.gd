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
	var replacement := material.duplicate() as ShaderMaterial
	replacement.set_shader_parameter("base_color_texture", texture)
	face.set_surface_override_material(0, replacement)
	return true
