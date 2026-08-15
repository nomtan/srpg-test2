@tool
extends Node2D
class_name PixelCharacterRig

## Runtime/editor animation setup for the reusable character cutout rig.
## Body proportions are never scaled; animation is limited to integer position
## keys and stepped joint rotations.

const FRAME_COUNT := 6
const FPS := 6.0
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

@export_enum("idle", "walk") var preview_animation := "idle":
	set(value):
		preview_animation = value
		if is_inside_tree():
			play(value)
@export_enum("front_left", "back_right") var preview_direction := "front_left"
@export_enum("male", "female") var preview_character := "male"
@export var center_character_in_viewport := true
@export var show_ui := true
@export_range(0.01, 4.0, 0.01) var character_display_scale := 0.3

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var ui: CanvasLayer = get_node_or_null("UI") as CanvasLayer
@onready var idle_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/IdleButton") as Button
@onready var walk_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/WalkButton") as Button
@onready var animation_status: Label = get_node_or_null("UI/RightPanel/Margin/VBox/AnimationStatus") as Label
@onready var direction_status: Label = get_node_or_null("UI/RightPanel/Margin/VBox/DirectionStatus") as Label
@onready var front_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/FrontButton") as Button
@onready var back_button: Button = get_node_or_null("UI/RightPanel/Margin/VBox/BackButton") as Button

var motion_step := 1


func _ready() -> void:
	if ui:
		ui.visible = show_ui
	$Root.scale = Vector2.ONE * character_display_scale
	set_direction(preview_direction)
	_build_animation_library()
	if idle_button:
		idle_button.pressed.connect(_on_idle_pressed)
	if walk_button:
		walk_button.pressed.connect(_on_walk_pressed)
	if front_button:
		front_button.pressed.connect(_on_front_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	play(preview_animation)


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
	var active_animation: String = animation_player.current_animation if animation_player else ""
	preview_direction = direction
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
	_update_direction_ui(direction)
	if animation_player and animation_player.has_animation_library(&""):
		_build_animation_library()
		play(StringName(active_animation if not active_animation.is_empty() else preview_animation))


func set_character(character_name: StringName) -> void:
	var character := String(character_name)
	if not CHARACTER_DIRECTORIES.has(character):
		push_warning("Unknown character type: %s" % character)
		return
	preview_character = character
	set_direction(preview_direction)


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
	if pivots.has("hand_l"):
		$Root/Waist/Torso/ArmLUpper/ArmLLower/HandL/WeaponSocket.position = Vector2(motion_step, motion_step * 5)
	if pivots.has("hand_r"):
		$Root/Waist/Torso/ArmRUpper/ArmRLower/HandR/WeaponSocket.position = Vector2(-motion_step, motion_step * 5)
	if center_character_in_viewport:
		var bbox_value: Array = manifest.get("source_bbox", [])
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
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
		_update_animation_ui(animation_name)


func _on_idle_pressed() -> void:
	play(&"idle")


func _on_walk_pressed() -> void:
	play(&"walk")


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
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()


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
	_add_rotation_track(animation, ^"Root/Waist/Torso/Head", [0, -1, 0, 1, 0, 0])
	return animation


func _make_walk() -> Animation:
	var animation := _new_loop_animation()
	_add_position_track(animation, ^"Root/Waist", $Root/Waist.position, [0, -1, 1, 0, -1, 1])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmLUpper", [-10, -5, 0, 10, 5, 0])
	_add_rotation_track(animation, ^"Root/Waist/Torso/ArmRUpper", [12, 6, 0, -12, -6, 0])
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
