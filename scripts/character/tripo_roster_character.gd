extends Node3D
## Modular stationary character; animations can also be used by gameplay actors.
@export var character_id := ""
@export var display_name := ""
@export var dialogue: PackedStringArray = ["一緒に冒険へ出かけましょう。"]
@export var face_variant: PackedScene
@export var face_texture: Texture2D
var animation_player: AnimationPlayer
var face: MeshInstance3D
var face_outline: MeshInstance3D
var face_socket: BoneAttachment3D
var _original_face_mesh: Mesh
var _original_outline_mesh: Mesh
var _original_face_material: Material
var _original_face_skin: Skin
var _original_outline_skin: Skin

func _ready() -> void:
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	face = find_child("Face_Default", true, false) as MeshInstance3D
	face_outline = find_child("Face_Outline", true, false) as MeshInstance3D
	if face:
		_original_face_mesh = face.mesh
		_original_face_material = face.get_active_material(0)
		_original_face_skin = face.skin
	if face_outline:
		_original_outline_mesh = face_outline.mesh
		_original_outline_skin = face_outline.skin
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton and skeleton.find_bone("head") >= 0:
		face_socket = BoneAttachment3D.new()
		face_socket.name = "FaceSocket"
		face_socket.bone_name = "head"
		skeleton.add_child(face_socket)
	if face_variant:
		set_face_variant(face_variant)
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
	# Instance-local material prevents changing other characters or their clothing.
	var replacement := material.duplicate() as ShaderMaterial
	replacement.set_shader_parameter("base_color_texture", texture)
	face.set_surface_override_material(0, replacement)
	return true

func set_face_variant(variant: PackedScene) -> bool:
	# Export the edited Face_Default + Face_Outline with this character's rig.
	# Reuse the live skeleton and animation. No additional AnimationPlayer is kept.
	if variant == null or face == null or face_outline == null:
		return false
	var instance := variant.instantiate()
	var replacement := instance.find_child("Face_Default", true, false) as MeshInstance3D
	var outline := instance.find_child("Face_Outline", true, false) as MeshInstance3D
	if replacement == null or outline == null or replacement.skin == null or outline.skin == null:
		instance.free()
		return false
	# Named binds allow a head-only variant to use a different joint index order.
	var skeleton := face.get_node(face.skeleton) as Skeleton3D
	for part in [replacement, outline]:
		for index in part.skin.get_bind_count():
			var bone_name: StringName = part.skin.get_bind_name(index)
			if bone_name.is_empty() or skeleton.find_bone(bone_name) < 0:
				instance.free()
				return false
	face.mesh = replacement.mesh
	face.skin = replacement.skin
	face.set_surface_override_material(0, replacement.get_active_material(0))
	face_outline.mesh = outline.mesh
	face_outline.skin = outline.skin
	instance.free()
	return true

func reset_face() -> void:
	if face:
		face.mesh = _original_face_mesh
		face.skin = _original_face_skin
		face.set_surface_override_material(0, _original_face_material)
	if face_outline:
		face_outline.mesh = _original_outline_mesh
		face_outline.skin = _original_outline_skin
