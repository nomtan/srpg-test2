extends Node2D

@onready var male_front_rig: PixelCharacterRig = $MaleFrontRig
@onready var male_back_rig: PixelCharacterRig = $MaleBackRig
@onready var female_front_rig: PixelCharacterRig = $FemaleFrontRig
@onready var female_back_rig: PixelCharacterRig = $FemaleBackRig
@onready var idle_button: Button = $UI/RightPanel/Margin/VBox/IdleButton
@onready var walk_button: Button = $UI/RightPanel/Margin/VBox/WalkButton
@onready var animation_status: Label = $UI/RightPanel/Margin/VBox/AnimationStatus


func _ready() -> void:
	idle_button.pressed.connect(_on_idle_pressed)
	walk_button.pressed.connect(_on_walk_pressed)
	_play_all(&"idle")


func _on_idle_pressed() -> void:
	_play_all(&"idle")


func _on_walk_pressed() -> void:
	_play_all(&"walk")


func _play_all(animation_name: StringName) -> void:
	male_front_rig.play(animation_name)
	male_back_rig.play(animation_name)
	female_front_rig.play(animation_name)
	female_back_rig.play(animation_name)
	idle_button.disabled = animation_name == &"idle"
	walk_button.disabled = animation_name == &"walk"
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()
