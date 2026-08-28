@tool
extends Node2D
class_name PixelCharacterRig

## Runtime/editor animation setup for the reusable character cutout rig.
## Body proportions are never scaled; animation is limited to integer position
## keys and stepped joint rotations.

const FRAME_COUNT := 6
const FPS := 6.0
const ATTACK_ANIMATION_PLAYER_NAME := &"authored/attack"
const BOW_ATTACK_ANIMATION_PLAYER_NAME := &"authored/bow_attack"
const PREVIEW_SWORD_TEXTURE: Texture2D = preload("res://assets/weapons/sword/base.png")
const PREVIEW_SHORT_SWORD_TEXTURE: Texture2D = preload("res://assets/weapons/short_sword/base.png")
const PREVIEW_BOW_TEXTURE: Texture2D = preload("res://assets/weapons/bow/base.png")
const PREVIEW_ARROW_TEXTURE: Texture2D = preload("res://assets/weapons/allow/base.png")
const DEFAULT_WEAPON_GRIP_POSITION := Vector2(626, 1000)
const BOW_WEAPON_GRIP_POSITION := Vector2(562, 620)
const ARROW_GRIP_POSITION := Vector2(626, 190)
const CHARACTER_DIRECTORIES := {
	"male": {
		"front_left": "res://assets/characters/male/front_left",
		"back_right": "res://assets/characters/male/back_right",
	},
	"female": {
		"front_left": "res://assets/characters/female/front_left",
		"back_right": "res://assets/characters/female/back_right",
	},
}
const ATTACK_LIBRARY_PATHS := {
	"male": {
		"front_left": "res://scenes/characters/rig/character_attack_animations.tres",
		"back_right": "res://scenes/characters/rig/male_back_attack_animations.tres",
	},
	"female": {
		"front_left": "res://scenes/characters/rig/female_front_attack_animations.tres",
		"back_right": "res://scenes/characters/rig/female_back_attack_animations.tres",
	},
}
const RIG_EQUIPMENT_SETTINGS := {
	"male": {
		"front_weapon_rotation_degrees": 0.0,
		"male_front_weapon_rotation_offset_degrees": -75.0,
		"male_back_weapon_rotation_offset_degrees": 75.0,
		"male_front_weapon_screen_offset": Vector2(-3, 0),
		"male_back_weapon_screen_offset": Vector2(-3, -8),
	},
	"female": {
		"front_weapon_rotation_degrees": -70.0,
		"female_front_weapon_screen_offset": Vector2.ZERO,
		"female_back_weapon_rotation_offset_degrees": 75.0,
		"female_back_weapon_screen_offset": Vector2(-10, -3),
	},
}
const PART_NODE_PATHS := {
	"waist": ^"Root/Waist",
	"torso": ^"Root/Waist/Torso",
	"head": ^"Root/Waist/Torso/Head",
	"arm_l_upper": ^"Root/Waist/Torso/ArmLUpper",
	"arm_l_lower": ^"Root/Waist/Torso/ArmLUpper/ArmLLower",
	"hand_l": ^"Root/Waist/Torso/ArmLUpper/ArmLLower/HandL",
	"arm_r_upper": ^"Root/Waist/Torso/ArmRUpper",
	"arm_r_lower": ^"Root/Waist/Torso/ArmRUpper/ArmRLower",
	"hand_r": ^"Root/Waist/Torso/ArmRUpper/ArmRLower/HandR",
	"leg_l_upper": ^"Root/Waist/LegLUpper",
	"leg_l_lower": ^"Root/Waist/LegLUpper/LegLLower",
	"foot_l": ^"Root/Waist/LegLUpper/LegLLower/FootL",
	"leg_r_upper": ^"Root/Waist/LegRUpper",
	"leg_r_lower": ^"Root/Waist/LegRUpper/LegRLower",
	"foot_r": ^"Root/Waist/LegRUpper/LegRLower/FootR",
}

@export_enum("idle", "walk", "attack") var preview_animation := "idle":
	set(value):
		preview_animation = value
		if is_inside_tree():
			play(value)
@export_enum("front_left", "back_right") var preview_direction := "front_left"
@export_enum("male", "female") var preview_character := "male"
@export var authored_attack_library: AnimationLibrary:
	set(value):
		authored_attack_library = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_authored_attack_library()
@export var center_character_in_viewport := true
@export var show_ui := true
@export_range(0.01, 4.0, 0.01) var character_display_scale := 0.24
@export var weapon_texture: Texture2D
@export_enum("None", "Sword", "Short Sword", "Bow") var editor_preview_weapon: String = "Sword":
	set(value):
		editor_preview_weapon = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_editor_preview_weapon()
@export var flip_weapon_face_on_back := false
@export var weapon_grip_position := Vector2(626, 1000)
@export var offhand_weapon_texture: Texture2D
@export var offhand_weapon_grip_position := ARROW_GRIP_POSITION:
	set(value):
		offhand_weapon_grip_position = value
		_refresh_editor_weapon()
@export_range(0.01, 2.0, 0.01) var offhand_weapon_display_scale := 0.55:
	set(value):
		offhand_weapon_display_scale = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var offhand_weapon_rotation_offset_degrees := 90.0:
	set(value):
		offhand_weapon_rotation_offset_degrees = value
		_refresh_editor_weapon()
@export_range(0.0, 1.0, 0.01) var bow_string_pull_amount: float = 0.0:
	set(value):
		bow_string_pull_amount = clampf(value, 0.0, 1.0)
		if is_node_ready():
			_update_bow_string()
@export_range(0.01, 2.0, 0.01) var weapon_display_scale: float = 0.55:
	set(value):
		weapon_display_scale = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var weapon_rotation_degrees: float = 70.0:
	set(value):
		weapon_rotation_degrees = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var front_weapon_rotation_degrees: float = -50.0:
	set(value):
		front_weapon_rotation_degrees = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var male_front_weapon_rotation_offset_degrees: float = 0.0:
	set(value):
		male_front_weapon_rotation_offset_degrees = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var male_back_weapon_rotation_offset_degrees: float = 0.0:
	set(value):
		male_back_weapon_rotation_offset_degrees = value
		_refresh_editor_weapon()
@export_range(-180.0, 180.0, 1.0) var female_back_weapon_rotation_offset_degrees: float = 0.0:
	set(value):
		female_back_weapon_rotation_offset_degrees = value
		_refresh_editor_weapon()
@export var front_weapon_screen_offset := Vector2(10, -10):
	set(value):
		front_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var male_front_weapon_screen_offset := Vector2(-10, 5):
	set(value):
		male_front_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var female_front_weapon_screen_offset := Vector2.ZERO:
	set(value):
		female_front_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var back_weapon_screen_offset := Vector2(10, -10):
	set(value):
		back_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var male_back_weapon_screen_offset := Vector2(-3, -8):
	set(value):
		male_back_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var female_back_weapon_screen_offset := Vector2(-3, -3):
	set(value):
		female_back_weapon_screen_offset = value
		_refresh_editor_weapon()
@export var shield_texture: Texture2D
@export var shield_grip_position := Vector2(615, 664)
@export_range(0.01, 2.0, 0.01) var shield_display_scale := 0.55
@export var back_shield_screen_offset := Vector2(0, -14)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
@onready var idle_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/IdleButton") as Button
@onready var walk_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/WalkButton") as Button
@onready var attack_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/AttackButton") as Button
@onready var animation_status: Label = get_node_or_null("UI/RightPanel/Margin/VBox/AnimationStatus") as Label
@onready var sword_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/SwordButton") as Button
@onready var short_sword_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/ShortSwordButton") as Button
@onready var bow_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/BowButton") as Button
@onready var weapon_status: Label = get_node_or_null("UI/RightPanel/Margin/VBox/WeaponStatus") as Label
@onready var direction_status: Label = get_node_or_null("UI/RightPanel/Margin/VBox/DirectionStatus") as Label
@onready var front_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/FrontButton") as Button
@onready var back_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/BackButton") as Button
@onready var right_weapon_pivot: Node2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot
@onready var right_weapon_sprite: Sprite2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot/WeaponSprite
@onready var left_weapon_pivot: Node2D = $Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket/WeaponPivot
@onready var left_weapon_sprite: Sprite2D = $Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket/WeaponPivot/WeaponSprite
@onready var bow_string: Line2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot/BowString
@onready var bow_upper_tip: Marker2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot/BowUpperTip
@onready var bow_string_rest: Marker2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot/BowStringRest
@onready var bow_lower_tip: Marker2D = $Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket/WeaponPivot/BowLowerTip
@onready var arrow_nock: Marker2D = $Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket/WeaponPivot/ArrowNock
@onready var shield_pivot: Node2D = $Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket/ShieldPivot
@onready var shield_sprite: Sprite2D = $Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket/ShieldPivot/ShieldSprite

var motion_step := 1
var visible_character_height := 0.0
var weapon_animation_profile: StringName = &"default"


func _ready() -> void:
	if ui:
		ui.visible = show_ui
	$Root.scale = Vector2.ONE * character_display_scale
	if Engine.is_editor_hint() or show_ui:
		_apply_editor_preview_weapon()
	_apply_authored_attack_library()
	set_direction(preview_direction)
	_build_animation_library()
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	if idle_button:
		idle_button.pressed.connect(_on_idle_pressed)
	if walk_button:
		walk_button.pressed.connect(_on_walk_pressed)
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)
	if sword_button:
		sword_button.pressed.connect(_on_sword_pressed)
	if short_sword_button:
		short_sword_button.pressed.connect(_on_short_sword_pressed)
	if bow_button:
		bow_button.pressed.connect(_on_bow_pressed)
	if front_button:
		front_button.pressed.connect(_on_front_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	play(preview_animation)


func _process(_delta: float) -> void:
	if bow_string and bow_string.visible:
		_update_bow_string()


func _apply_editor_preview_weapon() -> void:
	bow_string_pull_amount = 0.0
	match editor_preview_weapon:
		"Sword":
			weapon_texture = PREVIEW_SWORD_TEXTURE
			weapon_grip_position = DEFAULT_WEAPON_GRIP_POSITION
			offhand_weapon_texture = null
			weapon_animation_profile = &"default"
			flip_weapon_face_on_back = false
		"Short Sword":
			weapon_texture = PREVIEW_SHORT_SWORD_TEXTURE
			weapon_grip_position = DEFAULT_WEAPON_GRIP_POSITION
			offhand_weapon_texture = null
			weapon_animation_profile = &"default"
			flip_weapon_face_on_back = true
		"Bow":
			weapon_texture = PREVIEW_BOW_TEXTURE
			weapon_grip_position = BOW_WEAPON_GRIP_POSITION
			offhand_weapon_texture = PREVIEW_ARROW_TEXTURE
			offhand_weapon_grip_position = ARROW_GRIP_POSITION
			weapon_animation_profile = &"bow"
			flip_weapon_face_on_back = false
		_:
			weapon_texture = null
			weapon_grip_position = DEFAULT_WEAPON_GRIP_POSITION
			offhand_weapon_texture = null
			weapon_animation_profile = &"default"
			flip_weapon_face_on_back = false
	if is_node_ready():
		_update_weapon()
	_update_weapon_ui()


func _refresh_editor_weapon() -> void:
	if Engine.is_editor_hint() and is_node_ready():
		_update_weapon()


func _apply_authored_attack_library() -> void:
	if animation_player.has_animation_library(&"authored"):
		animation_player.remove_animation_library(&"authored")
	if authored_attack_library:
		animation_player.add_animation_library(&"authored", authored_attack_library)


func _update_weapon() -> void:
	var right_weapon_rotation: float = front_weapon_rotation_degrees
	if preview_direction == "back_right":
		right_weapon_rotation = weapon_rotation_degrees
		if preview_character == "male":
			right_weapon_rotation += male_back_weapon_rotation_offset_degrees
		elif preview_character == "female":
			right_weapon_rotation += female_back_weapon_rotation_offset_degrees
	elif preview_character == "male":
		right_weapon_rotation += male_front_weapon_rotation_offset_degrees
	_configure_weapon(
		right_weapon_pivot,
		right_weapon_sprite,
		weapon_texture,
		weapon_grip_position,
		weapon_display_scale,
		right_weapon_rotation
	)
	_configure_weapon(
		left_weapon_pivot,
		left_weapon_sprite,
		offhand_weapon_texture,
		offhand_weapon_grip_position,
		offhand_weapon_display_scale,
		right_weapon_rotation + offhand_weapon_rotation_offset_degrees
	)
	right_weapon_sprite.flip_h = preview_direction == "back_right" and flip_weapon_face_on_back
	right_weapon_pivot.position = Vector2.ZERO
	if preview_direction == "front_left":
		var front_offset: Vector2 = front_weapon_screen_offset
		if preview_character == "male":
			front_offset += male_front_weapon_screen_offset
		elif preview_character == "female":
			front_offset += female_front_weapon_screen_offset
		right_weapon_pivot.position = front_offset / character_display_scale
	elif preview_direction == "back_right":
		var back_offset: Vector2 = back_weapon_screen_offset
		if preview_character == "male":
			back_offset += male_back_weapon_screen_offset
		elif preview_character == "female":
			back_offset += female_back_weapon_screen_offset
		right_weapon_pivot.position = back_offset / character_display_scale
	var has_weapon: bool = weapon_texture != null
	# Part IDs are authored in screen space. HandR is the anatomical right hand
	# from the front, and the anatomical left hand when viewed from the back.
	right_weapon_pivot.visible = has_weapon
	left_weapon_pivot.visible = offhand_weapon_texture != null
	_update_bow_string()


func _update_bow_string() -> void:
	if not bow_string or not bow_upper_tip or not bow_string_rest or not bow_lower_tip:
		return
	var bow_equipped := weapon_animation_profile == &"bow" and weapon_texture != null
	bow_string.visible = bow_equipped
	if not bow_equipped:
		return
	var pull_position := bow_string_rest.position
	if arrow_nock and offhand_weapon_texture != null:
		var nock_in_bow_space := right_weapon_pivot.to_local(arrow_nock.global_position)
		pull_position = bow_string_rest.position.lerp(
			nock_in_bow_space,
			bow_string_pull_amount
		)
	bow_string.points = PackedVector2Array([
		bow_upper_tip.position,
		pull_position,
		bow_lower_tip.position,
	])


func _configure_weapon(
	pivot: Node2D,
	sprite: Sprite2D,
	texture: Texture2D,
	grip_position: Vector2,
	display_scale: float,
	rotation_degrees_value: float
) -> void:
	sprite.texture = texture
	sprite.position = -grip_position
	pivot.scale = Vector2.ONE * display_scale
	pivot.rotation_degrees = rotation_degrees_value


func equip_weapon(
	texture: Texture2D,
	should_flip_face_on_back: bool = false,
	grip_position: Vector2 = DEFAULT_WEAPON_GRIP_POSITION,
	offhand_texture: Texture2D = null,
	offhand_grip_position: Vector2 = ARROW_GRIP_POSITION,
	animation_profile: StringName = &"default"
) -> void:
	bow_string_pull_amount = 0.0
	weapon_texture = texture
	weapon_grip_position = grip_position
	offhand_weapon_texture = offhand_texture
	offhand_weapon_grip_position = offhand_grip_position
	weapon_animation_profile = animation_profile
	flip_weapon_face_on_back = should_flip_face_on_back
	_update_weapon()


func equip_shield(texture: Texture2D) -> void:
	shield_texture = texture
	_update_shield()


func unequip_shield() -> void:
	shield_texture = null
	_update_shield()


func _update_shield() -> void:
	shield_sprite.texture = shield_texture
	shield_sprite.position = -shield_grip_position
	shield_pivot.position = Vector2.ZERO
	if preview_direction == "back_right":
		shield_pivot.position = back_shield_screen_offset / character_display_scale
	shield_pivot.scale = Vector2.ONE * shield_display_scale
	shield_pivot.rotation_degrees = 0.0
	shield_pivot.visible = shield_texture != null


func set_direction(direction_name: StringName) -> void:
	var direction := String(direction_name)
	var character: String = preview_character
	if not CHARACTER_DIRECTORIES.has(character):
		push_warning("Unknown character type: %s" % character)
		return
	var character_directories: Dictionary = CHARACTER_DIRECTORIES[character]
	if not character_directories.has(direction):
		push_warning("Unknown character direction: %s" % direction)
		return
	_apply_character_equipment_settings(character)
	var active_animation: String = animation_player.current_animation if animation_player else ""
	if active_animation in [
		String(ATTACK_ANIMATION_PLAYER_NAME),
		String(BOW_ATTACK_ANIMATION_PLAYER_NAME),
	]:
		active_animation = "attack"
	preview_direction = direction
	var attack_paths := ATTACK_LIBRARY_PATHS.get(character, {}) as Dictionary
	var attack_library_path := String(attack_paths.get(direction, ""))
	if not attack_library_path.is_empty():
		authored_attack_library = load(attack_library_path) as AnimationLibrary
		_apply_authored_attack_library()
	var directory: String = character_directories[direction]
	for part_name: String in PART_NODE_PATHS:
		var node_path: NodePath = PART_NODE_PATHS[part_name]
		var sprite := get_node(NodePath(str(node_path) + "/Sprite2D")) as Sprite2D
		var texture_path := "%s/%s.png" % [directory, part_name]
		var texture := load(texture_path) as Texture2D
		if texture:
			sprite.texture = texture
		else:
			push_warning("Character part texture not found: %s" % texture_path)
	_apply_manifest_geometry("%s/rig_manifest.json" % directory)
	_update_weapon()
	_update_shield()
	_update_direction_ui(direction)
	if animation_player and animation_player.has_animation_library(&""):
		_build_animation_library()
		play(StringName(active_animation if not active_animation.is_empty() else preview_animation))


func _apply_character_equipment_settings(character: String) -> void:
	var settings := RIG_EQUIPMENT_SETTINGS.get(character, {}) as Dictionary
	if settings.is_empty():
		return
	if character == "male":
		front_weapon_rotation_degrees = float(settings.front_weapon_rotation_degrees)
		male_front_weapon_rotation_offset_degrees = float(
			settings.male_front_weapon_rotation_offset_degrees
		)
		male_back_weapon_rotation_offset_degrees = float(
			settings.male_back_weapon_rotation_offset_degrees
		)
		male_front_weapon_screen_offset = settings.male_front_weapon_screen_offset
		male_back_weapon_screen_offset = settings.male_back_weapon_screen_offset
	else:
		front_weapon_rotation_degrees = float(settings.front_weapon_rotation_degrees)
		female_front_weapon_screen_offset = settings.female_front_weapon_screen_offset
		female_back_weapon_rotation_offset_degrees = float(
			settings.female_back_weapon_rotation_offset_degrees
		)
		female_back_weapon_screen_offset = settings.female_back_weapon_screen_offset


func set_character(character_name: StringName) -> void:
	var character := String(character_name)
	if not CHARACTER_DIRECTORIES.has(character):
		push_warning("Unknown character type: %s" % character)
		return
	preview_character = character
	set_direction(preview_direction)


func get_center_to_foot_pixels() -> float:
	return visible_character_height * character_display_scale * 0.5


func _apply_manifest_geometry(manifest_path: String) -> void:
	if not FileAccess.file_exists(manifest_path):
		push_warning("Character rig manifest not found: %s" % manifest_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		push_warning("Character rig manifest is invalid: %s" % manifest_path)
		return
	var manifest := parsed as Dictionary
	motion_step = maxi(int(manifest.get("motion_step", 1)), 1)
	var bbox_value: Array = manifest.get("source_bbox", [])
	if bbox_value.size() == 4:
		visible_character_height = float(bbox_value[3]) - float(bbox_value[1])
	var pivots: Dictionary = {}
	for part_value in manifest.get("parts", []):
		var part := part_value as Dictionary
		var part_name := String(part.get("name", ""))
		var pivot_value := part.get("pivot", []) as Array
		if PART_NODE_PATHS.has(part_name) and pivot_value.size() == 2:
			pivots[part_name] = Vector2(float(pivot_value[0]), float(pivot_value[1]))
	for part_value in manifest.get("parts", []):
		var part := part_value as Dictionary
		var part_name := String(part.get("name", ""))
		if not PART_NODE_PATHS.has(part_name) or not pivots.has(part_name):
			continue
		var node_path: NodePath = PART_NODE_PATHS[part_name]
		var node := get_node(node_path) as Node2D
		var pivot: Vector2 = pivots[part_name]
		var parent_name: Variant = part.get("parent", null)
		var parent_pivot: Vector2 = Vector2.ZERO if parent_name == null else pivots[String(parent_name)]
		node.position = pivot - parent_pivot
		var sprite := node.get_node("Sprite2D") as Sprite2D
		sprite.position = -pivot
		var z_index_value: Variant = part.get("z_index", null)
		if z_index_value != null:
			sprite.z_index = int(z_index_value)
	var equipment_layers_value: Variant = manifest.get("equipment_layers", {})
	if equipment_layers_value is Dictionary:
		var equipment_layers := equipment_layers_value as Dictionary
		right_weapon_pivot.z_index = int(equipment_layers.get("right_weapon", right_weapon_pivot.z_index))
		left_weapon_pivot.z_index = int(equipment_layers.get("left_weapon", left_weapon_pivot.z_index))
		shield_pivot.z_index = int(equipment_layers.get("shield", shield_pivot.z_index))
	if pivots.has("hand_l"):
		$Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket.position = Vector2(motion_step, motion_step * 5)
	if pivots.has("hand_r"):
		$Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket.position = Vector2(-motion_step, motion_step * 5)
	if center_character_in_viewport:
		if bbox_value.size() == 4:
			var visible_center := Vector2(
				(float(bbox_value[0]) + float(bbox_value[2]) - 1.0) * 0.5,
				(float(bbox_value[1]) + float(bbox_value[3]) - 1.0) * 0.5
			)
			position = (
				get_viewport_rect().size * 0.5
				- visible_center * character_display_scale
			).round()


func play(animation_name: StringName) -> void:
	if not animation_player:
		return
	if animation_name != &"attack":
		bow_string_pull_amount = 0.0
	var player_animation_name: StringName = animation_name
	if animation_name == &"attack":
		player_animation_name = (
			BOW_ATTACK_ANIMATION_PLAYER_NAME
			if weapon_animation_profile == &"bow"
			else ATTACK_ANIMATION_PLAYER_NAME
		)
		if not animation_player.has_animation(player_animation_name):
			player_animation_name = ATTACK_ANIMATION_PLAYER_NAME
		_reset_pose_before_attack()
	if animation_player.has_animation(player_animation_name):
		animation_player.play(player_animation_name)
		_update_animation_ui(animation_name)


func _reset_pose_before_attack() -> void:
	if not animation_player.has_animation(&"idle"):
		return
	animation_player.play(&"idle")
	animation_player.seek(0.0, true)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name in [ATTACK_ANIMATION_PLAYER_NAME, BOW_ATTACK_ANIMATION_PLAYER_NAME]:
		bow_string_pull_amount = 0.0
		play(&"idle")


func _on_idle_pressed() -> void:
	play(&"idle")


func _on_walk_pressed() -> void:
	play(&"walk")


func _on_attack_pressed() -> void:
	play(&"attack")


func _on_sword_pressed() -> void:
	editor_preview_weapon = "Sword"
	_apply_editor_preview_weapon()


func _on_short_sword_pressed() -> void:
	editor_preview_weapon = "Short Sword"
	_apply_editor_preview_weapon()


func _on_bow_pressed() -> void:
	editor_preview_weapon = "Bow"
	_apply_editor_preview_weapon()


func _on_front_pressed() -> void:
	set_direction(&"front_left")


func _on_back_pressed() -> void:
	set_direction(&"back_right")


func _update_direction_ui(direction: String) -> void:
	if not front_button or not back_button or not direction_status:
		return
	front_button.disabled = direction == "front_left"
	back_button.disabled = direction == "back_right"
	direction_status.text = "方向: %s" % ("Front" if direction == "front_left" else "Back")


func _update_animation_ui(animation_name: StringName) -> void:
	if not idle_button or not walk_button or not animation_status:
		return
	idle_button.disabled = animation_name == &"idle"
	walk_button.disabled = animation_name == &"walk"
	if attack_button:
		attack_button.disabled = animation_name == &"attack"
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()


func _update_weapon_ui() -> void:
	if not sword_button or not short_sword_button or not bow_button or not weapon_status:
		return
	sword_button.disabled = editor_preview_weapon == "Sword"
	short_sword_button.disabled = editor_preview_weapon == "Short Sword"
	bow_button.disabled = editor_preview_weapon == "Bow"
	weapon_status.text = "Weapon: %s" % editor_preview_weapon


func _build_animation_library() -> void:
	if animation_player.has_animation_library(&""):
		animation_player.remove_animation_library(&"")
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", _make_idle())
	library.add_animation(&"walk", _make_walk())
	animation_player.add_animation_library(&"", library)


func _make_idle() -> Animation:
	var animation := _new_loop_animation()
	_add_position_track(animation, ^"Root/Waist", $Root/Waist.position, [0, 1, 0, -1, 0, 0])
	# Cancel the pelvis movement at each knee. This keeps the lower legs and feet
	# planted while the body above the knees performs the idle bounce.
	_add_position_track(animation, ^"Root/Waist/LegLUpper/LegLLower", $Root/Waist/LegLUpper/LegLLower.position, [0, -1, 0, 1, 0, 0])
	_add_position_track(animation, ^"Root/Waist/LegRUpper/LegRLower", $Root/Waist/LegRUpper/LegRLower.position, [0, -1, 0, 1, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/Head", [0, -1, 0, 1, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper/ArmLLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper/ArmLLower/HandL", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper/ArmRLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper/ArmRLower/HandR", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper/LegLLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper/LegLLower/FootL", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper/LegRLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper/LegRLower/FootR", [0, 0, 0, 0, 0, 0])
	return animation


func _make_walk() -> Animation:
	var animation := _new_loop_animation()
	_add_position_track(animation, ^"Root/Waist", $Root/Waist.position, [0, -1, 1, 0, -1, 1])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper", [-10, -5, 0, 10, 5, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper/ArmLLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper", [12, 6, 0, -12, -6, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper/ArmRLower", [0, 0, 0, 0, 0, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper", [14, 7, 0, -14, -7, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper/LegLLower", [-6, -3, 0, 7, 3, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegLUpper/LegLLower/FootL", [3, 1.5, 0, -3.5, -1.5, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper", [-12, -6, 0, 12, 6, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper/LegRLower", [7, 3, 0, -6, -3, 0])
	_add_rotation_track(animation, ^"Root/Waist/LegRUpper/LegRLower/FootR", [-3.5, -1.5, 0, 3, 1.5, 0])
	return animation


func _new_loop_animation() -> Animation:
	var animation := Animation.new()
	animation.length = float(FRAME_COUNT) / FPS
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation


func _add_position_track(animation: Animation, node_path: NodePath, rest: Vector2, y_offsets: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(str(node_path) + ":position"))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for index in FRAME_COUNT:
		animation.track_insert_key(track, float(index) / FPS, rest + Vector2(0, int(y_offsets[index]) * motion_step))


func _add_rotation_track(animation: Animation, node_path: NodePath, degrees: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(str(node_path) + ":rotation_degrees"))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for index in FRAME_COUNT:
		animation.track_insert_key(track, float(index) / FPS, float(degrees[index]))
