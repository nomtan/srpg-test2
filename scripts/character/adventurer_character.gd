class_name AdventurerCharacter
extends Node3D
## A stationary modular NPC, intentionally independent of Explorer input/movement.

const BODY = preload("res://assets/characters/meshy_adventure/adventurer_body.glb")
const TOON = preload("res://assets/characters/meshy_adventure/adventure_toon.gdshader")
const HAIRSTYLES := {
	"tousled": preload("res://assets/characters/meshy_adventure/hair_tousled.glb"),
	"swept": preload("res://assets/characters/meshy_adventure/hair_swept.glb"),
}
const EXPRESSIONS := {"neutral": "", "smile": "Smile", "blink": "Blink", "angry": "Angry"}
const JOB_ID := "adventurer"

@export var appearance: AdventurerAppearance
@export var animate_idle := true
var body: Node3D
var face: Node3D
var hair: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var current_expression := "neutral"
var _unskinned_parts: Dictionary = {}

func _ready() -> void:
	body = BODY.instantiate()
	body.name = "SharedAdventurerBody"
	_apply_toon(body)
	add_child(body)
	var rigs := body.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		skeleton = rigs[0] as Skeleton3D
		skeleton.skeleton_updated.connect(_sync_unskinned_parts)
	animation_player = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player:
		for clip in ["idle", "rig_check"]:
			if animation_player.has_animation(clip):
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	set_meta("job_id", JOB_ID)
	apply_appearance(appearance if appearance else AdventurerAppearance.new())
	if animate_idle:
		play_animation("idle")

func _meshes(part: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if part is MeshInstance3D:
		result.append(part)
	for child in part.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result

func _apply_toon(part: Node3D, texture: Texture2D = null, tint: Color = Color.WHITE) -> void:
	for mesh in _meshes(part):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			var base := texture if texture else (source.albedo_texture if source else null)
			if base == null:
				push_error("Adventure part requires the original Meshy Base Color: " + str(mesh.name))
				continue
			# Never mutate imported/shared materials when changing one character.
			var material := ShaderMaterial.new()
			material.shader = TOON
			material.set_shader_parameter("base_color_texture", base)
			material.set_shader_parameter("tint", tint)
			material.set_shader_parameter("use_expression_uv", mesh.get_meta("adventure_expression_uv", false))
			mesh.set_surface_override_material(surface, material)

func apply_appearance(value: AdventurerAppearance) -> void:
	if value == null or value.face_scene == null or value.hair_scene == null:
		push_warning("Adventurer appearance needs both a face and a hairstyle.")
		return
	# Copy the recipe so changes never leak to another character using this preset.
	appearance = value.duplicate() as AdventurerAppearance
	_replace_face(appearance.face_scene, appearance.face_texture)
	_replace_hair(appearance.hair_scene, appearance.hair_tint)
	if not set_expression(appearance.expression):
		set_expression("neutral")

func _replace_face(scene: PackedScene, texture: Texture2D) -> void:
	if is_instance_valid(face):
		_retire_part(face)
	face = scene.instantiate() as Node3D
	face.name = "FaceSlot"
	_apply_toon(face, texture)
	add_child(face)
	_bind_part(face)

func _replace_hair(scene: PackedScene, tint: Color) -> void:
	if is_instance_valid(hair):
		_retire_part(hair)
	hair = scene.instantiate() as Node3D
	hair.name = "HairSlot"
	_apply_toon(hair, null, tint)
	add_child(hair)
	_bind_part(hair)

func _bind_part(part: Node3D) -> void:
	if skeleton == null:
		return
	var imported_rigs := part.find_children("*", "Skeleton3D", true, false)
	var skinned := false
	for mesh in _meshes(part):
		if mesh.skin == null:
			continue
		var source_rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var skin := mesh.skin.duplicate() as Skin
		for i in skin.get_bind_count():
			var bone_name := skin.get_bind_name(i)
			if bone_name.is_empty() and source_rig:
				bone_name = source_rig.get_bone_name(skin.get_bind_bone(i))
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				push_error("Adventurer part uses an incompatible bone: " + str(bone_name))
				return
			skin.set_bind_name(i, bone_name)
			skin.set_bind_bone(i, bone)
		# Keep only the body's skeleton; all replacement skins point to it.
		if mesh != part:
			mesh.reparent(part, true)
		mesh.skin = skin
		mesh.skeleton = mesh.get_path_to(skeleton)
		skinned = true
	for imported in imported_rigs:
		imported.get_parent().remove_child(imported)
		imported.queue_free()
	if not skinned:
		# Legacy rigid heads/hair use the same feet-origin contract.
		_unskinned_parts[part] = part.transform
		_sync_unskinned_parts()

func _sync_unskinned_parts() -> void:
	if skeleton == null or _unskinned_parts.is_empty():
		return
	var head := skeleton.find_bone("head")
	if head < 0:
		return
	var to_character := global_transform.affine_inverse() * skeleton.global_transform
	var delta := to_character * skeleton.get_bone_global_pose(head) * skeleton.get_bone_global_rest(head).affine_inverse() * to_character.affine_inverse()
	for part: Node3D in _unskinned_parts:
		part.transform = delta * _unskinned_parts[part]

func play_animation(clip: String, blend: float = 0.15) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, blend)
	return true

func _retire_part(part: Node3D) -> void:
	# Release the render instance before its per-character materials.
	_unskinned_parts.erase(part)
	for mesh in _meshes(part):
		mesh.mesh = null
	remove_child(part)
	part.queue_free()

func set_face(scene: PackedScene, texture: Texture2D = null) -> bool:
	if scene == null or appearance == null:
		return false
	appearance.face_scene = scene
	appearance.face_texture = texture
	_replace_face(scene, texture)
	if not set_expression(current_expression):
		set_expression("neutral")
	return true

func set_hairstyle(id: String) -> bool:
	if not HAIRSTYLES.has(id) or appearance == null:
		return false
	appearance.hair_scene = HAIRSTYLES[id]
	_replace_hair(appearance.hair_scene, appearance.hair_tint)
	return true

func set_expression(id: String, strength: float = 1.0) -> bool:
	if not EXPRESSIONS.has(id) or face == null:
		return false
	var target: String = EXPRESSIONS[id]
	var supported := target.is_empty()
	for mesh in _meshes(face):
		for i in mesh.mesh.get_blend_shape_count():
			if mesh.mesh.get_blend_shape_name(i) == target:
				supported = true
	if not supported:
		return false
	for mesh in _meshes(face):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as ShaderMaterial
			if material:
				var mouth := clampf(strength, 0, 1) * (1.0 if id == "smile" else (-1.0 if id == "angry" else 0.0))
				material.set_shader_parameter("expression_mouth", mouth)
		for i in mesh.mesh.get_blend_shape_count():
			var shape := str(mesh.mesh.get_blend_shape_name(i))
			if shape in ["Smile", "Blink", "Angry"]:
				mesh.set_blend_shape_value(i, clampf(strength, 0, 1) if shape == target else 0.0)
	current_expression = id
	appearance.expression = id
	return true
