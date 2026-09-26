class_name BattleUnit
extends Node3D

enum AttackType { MELEE, RANGED }
enum FacingDirection { NORTH, EAST, SOUTH, WEST }
enum EnemyType { AGGRESSIVE, DEFENSIVE, SNIPER, GUARD, BOSS }
enum ElementType { NONE, EARTH, WATER, WIND, FIRE, THUNDER, ICE, LIGHT, DARK }

var unit_id: String
var unit_name: String
var grid_x: int
var grid_z: int
var move_range: int = 4
var jump_height: int = 1
var team: String
var has_acted: bool = false
var has_moved: bool = false
var has_used_action: bool = false
var max_hp: int = 100
var hp: int = 100
var attack_power: int = 30
var defense: int = 5
var attack_type: AttackType = AttackType.MELEE
var accuracy: int = 90
var evasion: int = 10
var min_attack_range: int = 1
var max_attack_range: int = 1
var is_dead: bool = false
var facing: FacingDirection = FacingDirection.SOUTH
var enemy_type: EnemyType = EnemyType.AGGRESSIVE
var job_id := ""
var job_name := ""
var element: ElementType = ElementType.NONE
var max_ap := 30
var ap := 30
var skill_ids: Array[String] = []
const MAX_EQUIPPED_SKILLS := 6
var learned_skill_ids: Array[String] = []
var equipped_skill_ids: Array[String] = []
var main_job_id := ""
var main_job_name := ""
var sub_job_id := ""
var sub_job_name := ""
var unlocked_job_ids: Array[String] = []
var job_levels: Dictionary = {}
var job_exps: Dictionary = {}
var level := 1
@warning_ignore("shadowed_global_identifier")
var exp := 0
var exp_to_next_level := 100
var job_level := 1
var job_exp := 0
var job_exp_to_next_level := 50
var strength := 10
var dexterity := 10
var vitality := 10
var mind := 10
var intelligence := 10
var agility := 10
var base_str := 10
var base_dex := 10
var base_vit := 10
var base_mnd := 10
var base_int := 10
var base_agi := 10
var build_stats: BuildStats
var ct := 0
var is_current_actor := false
var equipped_weapon_id := ""
var equipped_armor_id := ""
var equipped_accessory_id := ""
var temporary_defense_bonus := 0

var body_material: StandardMaterial3D
var base_color: Color
var status_bars: Sprite3D
var blob_shadow: Decal
var active_marker: Label3D


func configure(
	id: String,
	display_name: String,
	grid_pos: Vector2i,
	unit_team: String,
	movement: int = 4,
	jump: int = 1
) -> void:
	unit_id = id
	unit_name = display_name
	grid_x = grid_pos.x
	grid_z = grid_pos.y
	team = unit_team
	move_range = movement
	jump_height = jump
	name = unit_id


const FACING_MODEL_ANGLES := [180.0, 90.0, 0.0, -90.0]
const FACING_WORLD_VECTORS: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-1.0, 0.0, 0.0),
]

var model_instance: Node3D
var sprite_instance: AnimatedSprite3D
var character_rig_viewport: SubViewport
var character_rig_sprite: Sprite3D
var character_rig: PixelCharacterRig
var animation_player: AnimationPlayer
var weapon_attachment: BoneAttachment3D
var weapon_instance: Node3D
var face_attachment: BoneAttachment3D
var face_instance: MeshInstance3D
var attack_animation_name: StringName
var model_facing_offset_degrees := 0.0
var animation_profile := "onehand_sword"
var sprite_selected := false
var directional_sprite_enabled := false
var directional_attack_enabled := false
var directional_attack_playing := false
var character_rig_attack_playing := false
var _last_directional_animation: StringName
var _last_directional_flip_h := false

const DIRECTIONAL_SPRITE_FOOT_Y_RATIO := 298.0 / 400.0
const DIRECTIONAL_ATTACK_FPS := 8.0
const DIRECTIONAL_ATTACK_CHARGE_FRAMES := 3
const DIRECTIONAL_ATTACK_STRIKE_FRAMES := 3
const CHARACTER_RIG_PIXEL_SIZE := 0.006

const IDLE_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_idle",
	&"animation.onehand_sword_idle",
	&"onehand_sword_idle",
	&"idle",
]
const RUN_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_run",
	&"animation.onehand_sword_run",
	&"animation_run",
	&"animation.run",
	&"onehand_sword_run",
	&"run",
	&"walk",
]
const ATTACK_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_attack",
	&"animation.onehand_sword_attack",
	&"onehand_sword_attack",
	&"attack",
]
const BOW_IDLE_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_idle",
	&"animation.bow_idle",
	&"bow_idle",
]
const BOW_RUN_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_run",
	&"animation.bow_run",
	&"bow_run",
	&"run",
]
const BOW_ATTACK_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_attack",
	&"animation.bow_attack",
	&"bow_attack",
]
const CHARACTER_FLAT_SHADER := preload("res://shaders/flat/flat_character.gdshader")
const CHARACTER_FACE_SHADER := preload("res://shaders/flat/flat_character_face.gdshader")
const UNIT_STATUS_BAR_SCRIPT := preload("res://scripts/ui/unit_status_bar_3d.gd")
const CHARACTER_VISUAL_SCALE := 0.85

# T5 (docs/dev/phase/phase17-step1.md): flat shading has no realtime shadow,
# so a blob shadow is the only ground-contact cue. Multiply-blend isn't a
# Decal blend mode in Godot 4 - a black radial texture blended via
# albedo/modulate alpha reads the same (darkens the ground) so that's what
# this uses instead.
const BLOB_SHADOW_TEXTURE_SIZE := 32
const BLOB_SHADOW_SIZE := Vector3(
	0.85 * CHARACTER_VISUAL_SCALE,
	0.6,
	0.85 * CHARACTER_VISUAL_SCALE
)
const BLOB_SHADOW_MAX_ALPHA := 0.55
const ACTIVE_MARKER_OFFSET_Y := 0.42
static var _blob_shadow_texture_cache: ImageTexture


func _process(_delta: float) -> void:
	if directional_sprite_enabled:
		_update_directional_sprite()


func setup_visual(
	model_path: String = "",
	model_scale: float = 1.0,
	model_y_offset: float = 0.0,
	facing_offset_degrees: float = 0.0,
	use_flat_shading: bool = false,
	requested_animation_profile: String = "onehand_sword",
	tunic_color: Color = Color.TRANSPARENT,
	accent_color: Color = Color.TRANSPARENT,
	sprite_texture_path: String = "",
	sprite_pixel_size: float = 0.0018,
	sprite_hframes: int = 1,
	sprite_vframes: int = 1,
	sprite_fps: float = 6.0,
	sprite_back_texture_path: String = "",
	sprite_attack_base_path: String = "",
	character_rig_scene_path: String = "",
	character_rig_character: String = "male"
) -> void:
	model_facing_offset_degrees = facing_offset_degrees
	animation_profile = requested_animation_profile
	body_material = StandardMaterial3D.new()
	if attack_type == AttackType.RANGED:
		base_color = Color("#65c8a0") if team == "player" else Color("#d47a42")
	else:
		base_color = Color("#4ba3ff") if team == "player" else Color("#dc4c4c")
	body_material.albedo_color = base_color
	body_material.metallic = 0.15

	if not character_rig_scene_path.is_empty():
		_create_character_rig_visual(character_rig_scene_path, character_rig_character)
	elif not sprite_texture_path.is_empty():
		_create_sprite_visual(
			sprite_texture_path,
			sprite_pixel_size,
			sprite_hframes,
			sprite_vframes,
			sprite_fps,
			sprite_back_texture_path,
			sprite_attack_base_path
		)
	elif not model_path.is_empty():
		var packed: PackedScene = load(model_path)
		model_instance = packed.instantiate()
		model_instance.scale = Vector3.ONE * model_scale * CHARACTER_VISUAL_SCALE
		model_instance.position = Vector3(
			0.0, model_y_offset * CHARACTER_VISUAL_SCALE, 0.0
		)
		add_child(model_instance)
		if use_flat_shading:
			_apply_flat_shading(model_instance, tunic_color, accent_color)
		var players := model_instance.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animation_player = players[0] as AnimationPlayer
			animation_player.animation_finished.connect(_on_animation_finished)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.28 * CHARACTER_VISUAL_SCALE
		capsule.height = 0.9 * CHARACTER_VISUAL_SCALE
		body.mesh = capsule
		body.position.y = 0.45 * CHARACTER_VISUAL_SCALE
		body.material_override = body_material
		add_child(body)

	status_bars = UNIT_STATUS_BAR_SCRIPT.new()
	status_bars.configure(team)
	status_bars.position.y = (
		1.72
		if sprite_instance or character_rig_sprite
		else (2.05 * CHARACTER_VISUAL_SCALE if model_instance else 1.45 * CHARACTER_VISUAL_SCALE)
	)
	add_child(status_bars)
	_create_active_marker()
	_create_blob_shadow()
	update_visual_state()
	update_facing_visual()
	refresh_status_bars()
	play_idle_animation()


func _create_character_rig_visual(scene_path: String, character: String) -> void:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_warning("Cannot create character rig: failed to load '%s'" % scene_path)
		return

	character_rig_viewport = SubViewport.new()
	character_rig_viewport.name = "CharacterRigViewport"
	character_rig_viewport.size = Vector2i(320, 320)
	character_rig_viewport.transparent_bg = true
	character_rig_viewport.disable_3d = true
	character_rig_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(character_rig_viewport)

	character_rig = packed.instantiate() as PixelCharacterRig
	if not character_rig:
		push_warning("Character rig scene root must be a PixelCharacterRig: '%s'" % scene_path)
		character_rig_viewport.queue_free()
		character_rig_viewport = null
		return
	character_rig.name = "CharacterRig"
	character_rig.show_ui = false
	character_rig.center_character_in_viewport = true
	character_rig.preview_character = character
	character_rig.weapon_texture = null
	character_rig_viewport.add_child(character_rig)

	character_rig_sprite = Sprite3D.new()
	character_rig_sprite.name = "CharacterRigBillboard"
	character_rig_sprite.texture = character_rig_viewport.get_texture()
	character_rig_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	character_rig_sprite.pixel_size = CHARACTER_RIG_PIXEL_SIZE
	_ground_character_rig_sprite()
	character_rig_sprite.shaded = false
	character_rig_sprite.double_sided = true
	character_rig_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(character_rig_sprite)
	directional_sprite_enabled = true


func _ground_character_rig_sprite() -> void:
	if not character_rig or not character_rig_sprite:
		return
	character_rig_sprite.position.y = (
		character_rig.get_center_to_foot_pixels() * CHARACTER_RIG_PIXEL_SIZE
	)


func _create_sprite_visual(
	texture_path: String,
	pixel_size: float,
	hframes: int,
	vframes: int,
	fps: float,
	back_texture_path: String = "",
	attack_base_path: String = ""
) -> void:
	var sprite_texture := load(texture_path) as Texture2D
	if not sprite_texture:
		push_warning("Cannot create unit sprite: failed to load '%s'" % texture_path)
		return
	var back_texture := load(back_texture_path) as Texture2D if not back_texture_path.is_empty() else null
	if not back_texture_path.is_empty() and not back_texture:
		push_warning("Cannot create directional unit sprite: failed to load '%s'" % back_texture_path)
		return
	var safe_hframes := maxi(hframes, 1)
	var safe_vframes := maxi(vframes, 1)
	var frame_size := Vector2(
		float(sprite_texture.get_width()) / float(safe_hframes),
		float(sprite_texture.get_height()) / float(safe_vframes)
	)
	var sprite_frames := SpriteFrames.new()
	sprite_frames.remove_animation(&"default")
	if back_texture:
		directional_sprite_enabled = true
		_add_sprite_sheet_animation(
			sprite_frames, &"front", sprite_texture,
			safe_hframes, safe_vframes, fps
		)
		_add_sprite_sheet_animation(
			sprite_frames, &"back", back_texture,
			safe_hframes, safe_vframes, fps
		)
		if not attack_base_path.is_empty():
			directional_attack_enabled = _add_directional_attack_animations(
				sprite_frames, attack_base_path
			)
	else:
		sprite_frames.add_animation(&"idle")
		sprite_frames.set_animation_loop(&"idle", true)
		sprite_frames.set_animation_speed(&"idle", maxf(fps, 0.1))
		for frame_index in safe_hframes * safe_vframes:
			var atlas := AtlasTexture.new()
			atlas.atlas = sprite_texture
			atlas.region = Rect2(
				Vector2(
					float(frame_index % safe_hframes),
					float(floori(float(frame_index) / float(safe_hframes)))
				) * frame_size,
				frame_size
			)
			sprite_frames.add_frame(&"idle", atlas)

	sprite_instance = AnimatedSprite3D.new()
	sprite_instance.name = "CharacterIllustration"
	sprite_instance.sprite_frames = sprite_frames
	sprite_instance.animation = &"front" if directional_sprite_enabled else &"idle"
	sprite_instance.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_instance.pixel_size = pixel_size
	if directional_sprite_enabled:
		sprite_instance.position.y = (
			frame_size.y * pixel_size * (DIRECTIONAL_SPRITE_FOOT_Y_RATIO - 0.5)
		)
	else:
		# Frames share a bottom anchor at y=861 in an 896px cell. This ratio keeps the
		# foot anchor on the map surface while the upper body breathes in place.
		sprite_instance.position.y = frame_size.y * pixel_size * 0.461
	sprite_instance.shaded = false
	sprite_instance.double_sided = true
	sprite_instance.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(sprite_instance)
	sprite_instance.animation_finished.connect(_on_sprite_animation_finished)
	if directional_sprite_enabled:
		sprite_instance.play(&"front")
	else:
		sprite_instance.play(&"idle")


func _add_sprite_sheet_animation(
	frames: SpriteFrames,
	animation_name: StringName,
	texture: Texture2D,
	hframes: int,
	vframes: int,
	fps: float
) -> void:
	var frame_size := Vector2(
		float(texture.get_width()) / float(hframes),
		float(texture.get_height()) / float(vframes)
	)
	frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, true)
	frames.set_animation_speed(animation_name, maxf(fps, 0.1))
	for frame_index in hframes * vframes:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(
			Vector2(
				float(frame_index % hframes),
				float(floori(float(frame_index) / float(hframes)))
			) * frame_size,
			frame_size
		)
		frames.add_frame(animation_name, atlas)


func _add_directional_attack_animations(frames: SpriteFrames, base_path: String) -> bool:
	for facing_name in ["front", "back"]:
		var charge_texture := load("%s/%s/1.png" % [base_path, facing_name]) as Texture2D
		var strike_texture := load("%s/%s/2.png" % [base_path, facing_name]) as Texture2D
		if not charge_texture or not strike_texture:
			push_warning("Cannot create directional attack animation for '%s'" % facing_name)
			return false
		var animation_name := StringName("attack_%s" % facing_name)
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, false)
		frames.set_animation_speed(animation_name, DIRECTIONAL_ATTACK_FPS)
		for _charge_frame in DIRECTIONAL_ATTACK_CHARGE_FRAMES:
			frames.add_frame(animation_name, charge_texture)
		for _strike_frame in DIRECTIONAL_ATTACK_STRIKE_FRAMES:
			frames.add_frame(animation_name, strike_texture)
	return true


func _apply_flat_shading(root: Node, tunic_color: Color, accent_color: Color) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material := mesh_instance.get_active_material(surface_index)
			var surface_color := Color.WHITE
			if source_material is BaseMaterial3D:
				surface_color = (source_material as BaseMaterial3D).albedo_color
				if source_material.resource_name == "tunic" and tunic_color.a > 0.0:
					surface_color = tunic_color
				elif source_material.resource_name == "accent" and accent_color.a > 0.0:
					surface_color = accent_color

			var flat_material := ShaderMaterial.new()
			flat_material.shader = CHARACTER_FLAT_SHADER
			flat_material.set_shader_parameter("albedo_color", surface_color)
			mesh_instance.set_surface_override_material(surface_index, flat_material)


static func _blob_shadow_texture() -> ImageTexture:
	if _blob_shadow_texture_cache:
		return _blob_shadow_texture_cache
	var size := BLOB_SHADOW_TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := size * 0.5
	for y in size:
		for x in size:
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			var alpha := (1.0 - smoothstep(0.55, 1.0, dist)) * BLOB_SHADOW_MAX_ALPHA
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	_blob_shadow_texture_cache = ImageTexture.create_from_image(image)
	return _blob_shadow_texture_cache


func _create_blob_shadow() -> void:
	blob_shadow = Decal.new()
	blob_shadow.name = "BlobShadow"
	blob_shadow.texture_albedo = _blob_shadow_texture()
	blob_shadow.size = BLOB_SHADOW_SIZE
	blob_shadow.position = Vector3(0.0, BLOB_SHADOW_SIZE.y * 0.5 - 0.05, 0.0)
	add_child(blob_shadow)


func _create_active_marker() -> void:
	active_marker = Label3D.new()
	active_marker.name = "ActiveMarker"
	active_marker.text = "▼"
	active_marker.position.y = status_bars.position.y + ACTIVE_MARKER_OFFSET_Y
	active_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	active_marker.font_size = 48
	active_marker.pixel_size = 0.008
	active_marker.modulate = Color("#ffd84a")
	active_marker.outline_modulate = Color("#3a2b08")
	active_marker.outline_size = 8
	active_marker.no_depth_test = true
	active_marker.visible = sprite_selected
	add_child(active_marker)


## Shrinks and fades the blob shadow as the unit rises off the ground
## (jump/float). Not yet wired to any movement animation - call this once
## the mover/skill systems track real-time height above ground.
func update_blob_shadow(height_above_ground: float) -> void:
	if not blob_shadow:
		return
	var falloff: float = clamp(1.0 - height_above_ground / 3.0, 0.15, 1.0)
	blob_shadow.size = Vector3(BLOB_SHADOW_SIZE.x, BLOB_SHADOW_SIZE.y, BLOB_SHADOW_SIZE.z) * Vector3(falloff, 1.0, falloff)
	blob_shadow.modulate.a = falloff


func attach_face_texture(texture_path: String, bone_name: String = "ganmen") -> void:
	if face_attachment:
		face_attachment.queue_free()
		face_attachment = null
		face_instance = null
	if not model_instance or texture_path.is_empty():
		return

	var skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Cannot attach face texture: character model has no Skeleton3D")
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone(bone_name) < 0:
		push_warning("Cannot attach face texture: bone '%s' was not found" % bone_name)
		return

	var face_texture := load(texture_path) as Texture2D
	if not face_texture:
		push_warning("Cannot attach face texture: failed to load '%s'" % texture_path)
		return

	face_attachment = BoneAttachment3D.new()
	face_attachment.name = "FaceAttachment"
	face_attachment.bone_name = bone_name
	skeleton.add_child(face_attachment)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4375, 0.375)
	var face_material := ShaderMaterial.new()
	face_material.shader = CHARACTER_FACE_SHADER
	face_material.set_shader_parameter("albedo_texture", face_texture)
	quad.material = face_material

	face_instance = MeshInstance3D.new()
	face_instance.name = "AnimeFace"
	face_instance.mesh = quad
	# Place the facial features slightly below the geometric center of the head.
	face_instance.position = Vector3(0.2525, 0.19, 0.0)
	face_instance.rotation_degrees.y = 90.0
	face_attachment.add_child(face_instance)


func play_walk_animation() -> void:
	if character_rig:
		character_rig.play(&"walk")
		return
	_play_animation(BOW_RUN_ANIMATION_NAMES if animation_profile == "bow" else RUN_ANIMATION_NAMES, Animation.LOOP_LINEAR)


func stop_walk_animation() -> void:
	play_idle_animation()


func play_idle_animation() -> void:
	attack_animation_name = &""
	character_rig_attack_playing = false
	if character_rig:
		character_rig.play(&"idle")
		return
	_play_animation(BOW_IDLE_ANIMATION_NAMES if animation_profile == "bow" else IDLE_ANIMATION_NAMES, Animation.LOOP_LINEAR)


func play_attack_animation() -> void:
	if character_rig:
		character_rig_attack_playing = true
		character_rig.play(&"attack")
		return
	if sprite_instance and directional_attack_enabled:
		directional_attack_playing = true
		var facing_name := "back" if _last_directional_animation == &"back" else "front"
		sprite_instance.play(StringName("attack_%s" % facing_name))
		return
	var candidates := BOW_ATTACK_ANIMATION_NAMES if animation_profile == "bow" else ATTACK_ANIMATION_NAMES
	attack_animation_name = _find_animation(candidates)
	if attack_animation_name.is_empty():
		return
	var animation := animation_player.get_animation(attack_animation_name)
	animation.loop_mode = Animation.LOOP_NONE
	animation_player.play(attack_animation_name)


func wait_for_attack_impact() -> void:
	if (not directional_attack_playing and not character_rig_attack_playing) or not is_inside_tree():
		return
	var charge_duration := 0.5 if character_rig_attack_playing else (
		float(DIRECTIONAL_ATTACK_CHARGE_FRAMES) / DIRECTIONAL_ATTACK_FPS
	)
	await get_tree().create_timer(charge_duration).timeout


func _play_animation(candidates: Array[StringName], loop_mode: Animation.LoopMode) -> void:
	var animation_name := _find_animation(candidates)
	if animation_name.is_empty():
		return
	var animation := animation_player.get_animation(animation_name)
	animation.loop_mode = loop_mode
	animation_player.play(animation_name)


func _find_animation(candidates: Array[StringName]) -> StringName:
	if not animation_player:
		return &""
	for candidate in candidates:
		if animation_player.has_animation(candidate):
			return candidate
	for available in animation_player.get_animation_list():
		for candidate in candidates:
			if String(available).ends_with("/" + String(candidate)):
				return available
	return &""


func _on_animation_finished(finished_animation: StringName) -> void:
	if not attack_animation_name.is_empty() and finished_animation == attack_animation_name:
		play_idle_animation()


func _on_sprite_animation_finished() -> void:
	if not directional_attack_playing:
		return
	directional_attack_playing = false
	_last_directional_animation = &""
	_update_directional_sprite()


func equip_weapon_visual(
	model_path: String,
	bone_name: String = "hand_right_te",
	local_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 180.0),
	local_scale: float = 0.78
) -> void:
	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null
		weapon_instance = null
	if not model_instance or model_path.is_empty():
		return

	var skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Cannot equip weapon: character model has no Skeleton3D")
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone(bone_name) < 0:
		push_warning("Cannot equip weapon: bone '%s' was not found" % bone_name)
		return

	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_name = bone_name
	skeleton.add_child(weapon_attachment)

	var packed: PackedScene = load(model_path)
	if not packed:
		push_warning("Cannot equip weapon: failed to load '%s'" % model_path)
		return
	weapon_instance = packed.instantiate()
	weapon_instance.name = "EquippedWeapon"
	weapon_instance.rotation_degrees = local_rotation_degrees
	weapon_instance.scale = Vector3.ONE * local_scale
	weapon_attachment.add_child(weapon_instance)


func equip_character_rig_weapon(
	texture_path: String,
	flip_face_on_back: bool = false,
	grip_position: Vector2 = Vector2(626, 1000),
	offhand_texture_path: String = "",
	offhand_grip_position: Vector2 = Vector2(626, 190),
	weapon_profile: StringName = &"sword"
) -> void:
	if not character_rig:
		return
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	var offhand_texture: Texture2D = (
		load(offhand_texture_path) as Texture2D
		if not offhand_texture_path.is_empty()
		else null
	)
	character_rig.equip_weapon(
		texture,
		flip_face_on_back,
		grip_position,
		offhand_texture,
		offhand_grip_position,
		weapon_profile
	)


func face_toward(target_pos: Vector2i) -> void:
	var delta := target_pos - Vector2i(grid_x, grid_z)
	face_along_grid_delta(delta)


func face_along_grid_delta(delta: Vector2i) -> void:
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		facing = FacingDirection.EAST if delta.x > 0 else FacingDirection.WEST
	elif delta.y != 0:
		facing = FacingDirection.SOUTH if delta.y > 0 else FacingDirection.NORTH
	update_facing_visual()


func set_facing(direction: FacingDirection) -> void:
	facing = direction
	update_facing_visual()


func update_facing_visual() -> void:
	if model_instance:
		model_instance.rotation_degrees.y = FACING_MODEL_ANGLES[int(facing)] + model_facing_offset_degrees
	if directional_sprite_enabled:
		_update_directional_sprite()


func _update_directional_sprite() -> void:
	if (not sprite_instance and not character_rig_sprite) or not directional_sprite_enabled:
		return
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if not viewport:
		return
	var viewport_camera := viewport.get_camera_3d()
	if not viewport_camera:
		return
	var facing_vector := FACING_WORLD_VECTORS[int(facing)]
	# The battle camera is orthographic, so every unit is viewed from the
	# camera's backward axis. Using camera-to-unit positions makes panning alone
	# cross the front/back boundary even though the viewing direction is fixed.
	var to_camera := viewport_camera.global_basis.z
	to_camera.y = 0.0
	if to_camera.is_zero_approx():
		return
	to_camera = to_camera.normalized()
	var screen_right := viewport_camera.global_basis.x
	screen_right.y = 0.0
	if screen_right.is_zero_approx():
		return
	screen_right = screen_right.normalized()
	var shows_front := facing_vector.dot(to_camera) >= 0.0
	var points_right := facing_vector.dot(screen_right) > 0.0
	var next_animation: StringName = &"front" if shows_front else &"back"
	var next_flip_h := points_right if shows_front else not points_right
	if character_rig and character_rig_sprite:
		var next_direction := "front_left" if shows_front else "back_right"
		if character_rig.preview_direction != next_direction:
			character_rig.set_direction(next_direction)
			_ground_character_rig_sprite()
		character_rig_sprite.flip_h = next_flip_h
		_last_directional_animation = next_animation
		_last_directional_flip_h = next_flip_h
		return
	if directional_attack_playing:
		if next_flip_h != _last_directional_flip_h:
			sprite_instance.flip_h = next_flip_h
			_last_directional_flip_h = next_flip_h
		return
	if next_animation != _last_directional_animation:
		var previous_frame := sprite_instance.frame
		sprite_instance.play(next_animation)
		sprite_instance.frame = mini(
			previous_frame,
			sprite_instance.sprite_frames.get_frame_count(next_animation) - 1
		)
		_last_directional_animation = next_animation
	if next_flip_h != _last_directional_flip_h:
		sprite_instance.flip_h = next_flip_h
		_last_directional_flip_h = next_flip_h


func set_selected(selected: bool) -> void:
	sprite_selected = selected
	if body_material:
		body_material.emission_enabled = false
	_update_selection_visual()


func mark_acted(moved: bool = true) -> void:
	has_moved = moved
	has_acted = true
	update_visual_state()


func set_combat_stats(
	new_max_hp: int, power: int, armor: int, hit: int, dodge: int,
	type: AttackType = AttackType.MELEE, min_range: int = 1, max_range: int = 1
) -> void:
	max_hp = new_max_hp
	hp = max_hp
	attack_power = power
	defense = armor
	accuracy = hit
	evasion = dodge
	attack_type = type
	min_attack_range = min_range
	max_attack_range = max_range


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		die()
	update_visual_state()
	refresh_status_bars()


func die() -> void:
	is_dead = true
	visible = false


func is_alive() -> bool:
	return not is_dead and hp > 0


func get_status_name() -> String:
	if is_dead: return "Defeated"
	return "Acted" if has_acted else "Ready"

func configure_role(id: String, display_name: String, affinity: ElementType, new_max_ap: int, skills: Array[String]) -> void:
	job_id = id
	job_name = display_name
	main_job_id = id
	main_job_name = display_name
	sub_job_id = id
	sub_job_name = display_name
	element = affinity
	max_ap = new_max_ap
	ap = max_ap
	skill_ids = skills.duplicate()
	equipped_skill_ids = skills.duplicate()
	job_levels[id] = job_level
	job_exps[id] = job_exp
	refresh_status_bars()

func get_job_level_for(id: String) -> int: return int(job_levels.get(id, 1))
func get_job_exp_for(id: String) -> int: return int(job_exps.get(id, 0))
func set_job_level_for(id: String, value: int) -> void: job_levels[id] = value
func set_job_exp_for(id: String, value: int) -> void: job_exps[id] = value

func equip_skill(id: String) -> bool:
	if id in equipped_skill_ids: return true
	if equipped_skill_ids.size() >= MAX_EQUIPPED_SKILLS: return false
	equipped_skill_ids.append(id); return true
func unequip_skill(id: String) -> void: equipped_skill_ids.erase(id)
func clear_equipped_skills() -> void: equipped_skill_ids.clear()
func get_build_data() -> Dictionary: return {"unit_id": unit_id, "main_job_id": main_job_id, "sub_job_id": sub_job_id, "equipped_skill_ids": equipped_skill_ids.duplicate()}

func add_exp(amount: int, growth: Dictionary) -> Array[Dictionary]:
	exp += amount
	var results: Array[Dictionary] = []
	while exp >= exp_to_next_level:
		exp -= exp_to_next_level
		level += 1
		results.append({"unit": self, "new_level": level, "growth": apply_level_growth(growth)})
	return results

func apply_level_growth(growth: Dictionary) -> Dictionary:
	max_hp += int(growth.get("max_hp", 5)); max_ap += int(growth.get("max_ap", 1))
	attack_power += int(growth.get("attack_power", 1)); defense += int(growth.get("defense", 1))
	accuracy += int(growth.get("accuracy", 1)); evasion += int(growth.get("evasion", 1))
	base_str += int(growth.get("str", growth.get("attack_power", 1)))
	base_dex += int(growth.get("dex", growth.get("accuracy", 1)))
	base_vit += int(growth.get("vit", growth.get("defense", 1)))
	base_mnd += int(growth.get("mnd", 1))
	base_int += int(growth.get("int", 1))
	base_agi += int(growth.get("agi", growth.get("evasion", 1)))
	hp = max_hp; ap = max_ap
	refresh_status_bars()
	return growth

func refresh_build_stats(status_calculator: Node) -> void:
	var hp_ratio := float(hp) / float(max_hp) if max_hp > 0 else 1.0
	build_stats = status_calculator.calculate_build_stats(self)
	var final_stats: Dictionary = status_calculator.calculate_final_base_stats(self)
	strength = int(final_stats.str); dexterity = int(final_stats.dex); vitality = int(final_stats.vit)
	mind = int(final_stats.mnd); intelligence = int(final_stats.int); agility = int(final_stats.agi)
	max_hp = status_calculator.calculate_max_hp(self, final_stats)
	attack_power = build_stats.attack_power; defense = build_stats.defense
	accuracy = build_stats.accuracy; evasion = build_stats.evasion
	move_range = build_stats.move_range; jump_height = build_stats.jump_height
	hp = clampi(roundi(max_hp * hp_ratio), 1, max_hp) if not is_dead else 0
	refresh_status_bars()


func refresh_status_bars() -> void:
	if status_bars:
		status_bars.update_values(hp, max_hp, ap, max_ap)

func add_job_exp(amount: int) -> Array[Dictionary]:
	var target_job := main_job_id if not main_job_id.is_empty() else job_id
	job_exp = get_job_exp_for(target_job) + amount
	job_level = get_job_level_for(target_job)
	var results: Array[Dictionary] = []
	while job_exp >= job_exp_to_next_level:
		job_exp -= job_exp_to_next_level
		job_level += 1
		set_job_level_for(target_job, job_level)
		results.append({"unit": self, "job_level": job_level})
	set_job_exp_for(target_job, job_exp)
	return results


func reset_action_state() -> void:
	has_acted = false
	has_moved = false
	has_used_action = false
	temporary_defense_bonus = 0
	update_visual_state()

func add_ct(amount: int) -> void: ct += amount
func is_ready_to_act() -> bool: return ct >= 100 and is_alive()
func reset_ct_after_action() -> void: ct = 0
func reset_ct_after_wait() -> void: ct = 20


func update_visual_state() -> void:
	visible = not is_dead
	if body_material:
		body_material.albedo_color = base_color
	_update_selection_visual()


func _update_selection_visual() -> void:
	if sprite_instance:
		sprite_instance.modulate = Color.WHITE
	if character_rig_sprite:
		character_rig_sprite.modulate = Color.WHITE
	if active_marker:
		active_marker.visible = sprite_selected


func snap_to_grid(grid: GridSystem) -> void:
	position = grid.grid_to_world(Vector2i(grid_x, grid_z), 0.05)
