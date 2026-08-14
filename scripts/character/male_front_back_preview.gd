extends Node2D

@onready var front_rig: PixelCharacterRig = $FrontRig
@onready var back_rig: PixelCharacterRig = $BackRig
@onready var idle_button: Button = $UI/RightPanel/Margin/VBox/IdleButton
@onready var walk_button: Button = $UI/RightPanel/Margin/VBox/WalkButton
@onready var animation_status: Label = $UI/RightPanel/Margin/VBox/AnimationStatus


func _ready() -> void:
	idle_button.pressed.connect(_on_idle_pressed)
	walk_button.pressed.connect(_on_walk_pressed)
	_play_both(&"idle")


func _on_idle_pressed() -> void:
	_play_both(&"idle")


func _on_walk_pressed() -> void:
	_play_both(&"walk")


func _play_both(animation_name: StringName) -> void:
	front_rig.play(animation_name)
	back_rig.play(animation_name)
	idle_button.disabled = animation_name == &"idle"
	walk_button.disabled = animation_name == &"walk"
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()
