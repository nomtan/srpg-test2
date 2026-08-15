extends Node2D

const SWORD_TEXTURE := preload("res://assets/weapons/sword/base.png")
const SHORT_SWORD_TEXTURE := preload("res://assets/weapons/short_sword/base.png")
const SHIELD_TEXTURE := preload("res://assets/weapons/shield/base.png")

@onready var male_front_rig: PixelCharacterRig = $MaleFrontRig
@onready var male_back_rig: PixelCharacterRig = $MaleBackRig
@onready var female_front_rig: PixelCharacterRig = $FemaleFrontRig
@onready var female_back_rig: PixelCharacterRig = $FemaleBackRig
@onready var idle_button: Button = $UI/RightPanel/Margin/VBox/IdleButton
@onready var walk_button: Button = $UI/RightPanel/Margin/VBox/WalkButton
@onready var animation_status: Label = $UI/RightPanel/Margin/VBox/AnimationStatus
@onready var sword_button: Button = $UI/RightPanel/Margin/VBox/SwordButton
@onready var short_sword_button: Button = $UI/RightPanel/Margin/VBox/ShortSwordButton
@onready var weapon_status: Label = $UI/RightPanel/Margin/VBox/WeaponStatus
@onready var shield_toggle: CheckButton = $UI/RightPanel/Margin/VBox/ShieldToggle
@onready var shield_status: Label = $UI/RightPanel/Margin/VBox/ShieldStatus


func _ready() -> void:
	idle_button.pressed.connect(_on_idle_pressed)
	walk_button.pressed.connect(_on_walk_pressed)
	sword_button.pressed.connect(_on_sword_pressed)
	short_sword_button.pressed.connect(_on_short_sword_pressed)
	shield_toggle.toggled.connect(_on_shield_toggled)
	_play_all(&"idle")
	_equip_all(SWORD_TEXTURE, &"sword")
	_equip_shield_all(true)


func _on_idle_pressed() -> void:
	_play_all(&"idle")


func _on_walk_pressed() -> void:
	_play_all(&"walk")


func _on_sword_pressed() -> void:
	_equip_all(SWORD_TEXTURE, &"sword")


func _on_short_sword_pressed() -> void:
	_equip_all(SHORT_SWORD_TEXTURE, &"short_sword")


func _on_shield_toggled(enabled: bool) -> void:
	_equip_shield_all(enabled)


func _equip_shield_all(enabled: bool) -> void:
	if enabled:
		male_front_rig.equip_shield(SHIELD_TEXTURE)
		male_back_rig.equip_shield(SHIELD_TEXTURE)
		female_front_rig.equip_shield(SHIELD_TEXTURE)
		female_back_rig.equip_shield(SHIELD_TEXTURE)
	else:
		male_front_rig.unequip_shield()
		male_back_rig.unequip_shield()
		female_front_rig.unequip_shield()
		female_back_rig.unequip_shield()
	shield_status.text = "Shield: %s" % ("Equipped" if enabled else "None")


func _equip_all(texture: Texture2D, weapon_name: StringName) -> void:
	var flip_face_on_back: bool = weapon_name == &"short_sword"
	male_front_rig.equip_weapon(texture, flip_face_on_back)
	male_back_rig.equip_weapon(texture, flip_face_on_back)
	female_front_rig.equip_weapon(texture, flip_face_on_back)
	female_back_rig.equip_weapon(texture, flip_face_on_back)
	sword_button.disabled = weapon_name == &"sword"
	short_sword_button.disabled = weapon_name == &"short_sword"
	weapon_status.text = "Weapon: %s" % str(weapon_name).replace("_", " ").capitalize()


func _play_all(animation_name: StringName) -> void:
	male_front_rig.play(animation_name)
	male_back_rig.play(animation_name)
	female_front_rig.play(animation_name)
	female_back_rig.play(animation_name)
	idle_button.disabled = animation_name == &"idle"
	walk_button.disabled = animation_name == &"walk"
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()
