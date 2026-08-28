extends Node2D

const SWORD_TEXTURE := preload("res://assets/weapons/sword/base.png")
const SHORT_SWORD_TEXTURE := preload("res://assets/weapons/short_sword/base.png")
const BOW_TEXTURE := preload("res://assets/weapons/bow/base.png")
const ARROW_TEXTURE := preload("res://assets/weapons/allow/base.png")
const SHIELD_TEXTURE := preload("res://assets/weapons/shield/base.png")
const DEFAULT_WEAPON_GRIP_POSITION := Vector2(626, 1000)
const BOW_WEAPON_GRIP_POSITION := Vector2(562, 620)
const ARROW_GRIP_POSITION := Vector2(626, 190)

@onready var male_front_rig: PixelCharacterRig = $MaleFrontRig
@onready var male_back_rig: PixelCharacterRig = $MaleBackRig
@onready var female_front_rig: PixelCharacterRig = $FemaleFrontRig
@onready var female_back_rig: PixelCharacterRig = $FemaleBackRig
@onready var idle_button: Button = $UI/RightPanel/Margin/VBox/IdleButton
@onready var walk_button: Button = $UI/RightPanel/Margin/VBox/WalkButton
@onready var attack_button: Button = $UI/RightPanel/Margin/VBox/AttackButton
@onready var animation_status: Label = $UI/RightPanel/Margin/VBox/AnimationStatus
@onready var sword_button: Button = $UI/RightPanel/Margin/VBox/SwordButton
@onready var short_sword_button: Button = $UI/RightPanel/Margin/VBox/ShortSwordButton
@onready var bow_button: Button = $UI/RightPanel/Margin/VBox/BowButton
@onready var weapon_status: Label = $UI/RightPanel/Margin/VBox/WeaponStatus
@onready var shield_toggle: CheckButton = $UI/RightPanel/Margin/VBox/ShieldToggle
@onready var shield_status: Label = $UI/RightPanel/Margin/VBox/ShieldStatus


func _ready() -> void:
	idle_button.pressed.connect(_on_idle_pressed)
	walk_button.pressed.connect(_on_walk_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	sword_button.pressed.connect(_on_sword_pressed)
	short_sword_button.pressed.connect(_on_short_sword_pressed)
	bow_button.pressed.connect(_on_bow_pressed)
	shield_toggle.toggled.connect(_on_shield_toggled)
	male_front_rig.animation_player.animation_finished.connect(_on_preview_animation_finished)
	_play_all(&"idle")
	_equip_all(SWORD_TEXTURE, &"sword")
	_equip_shield_all(true)


func _on_idle_pressed() -> void:
	_play_all(&"idle")


func _on_walk_pressed() -> void:
	_play_all(&"walk")


func _on_attack_pressed() -> void:
	_play_all(&"attack")


func _on_preview_animation_finished(animation_name: StringName) -> void:
	if animation_name in [&"authored/attack", &"authored/bow_attack"]:
		_play_all(&"idle")


func _on_sword_pressed() -> void:
	_equip_all(SWORD_TEXTURE, &"sword")


func _on_short_sword_pressed() -> void:
	_equip_all(SHORT_SWORD_TEXTURE, &"short_sword")


func _on_bow_pressed() -> void:
	shield_toggle.set_pressed_no_signal(false)
	_equip_shield_all(false)
	_equip_all(BOW_TEXTURE, &"bow")


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
	var grip_position := (
		BOW_WEAPON_GRIP_POSITION
		if weapon_name == &"bow"
		else DEFAULT_WEAPON_GRIP_POSITION
	)
	var is_bow := weapon_name == &"bow"
	shield_toggle.disabled = is_bow
	var offhand_texture: Texture2D = ARROW_TEXTURE if is_bow else null
	var weapon_profile: StringName = &"bow" if is_bow else &"default"
	male_front_rig.equip_weapon(
		texture, flip_face_on_back, grip_position, offhand_texture, ARROW_GRIP_POSITION, weapon_profile
	)
	male_back_rig.equip_weapon(
		texture, flip_face_on_back, grip_position, offhand_texture, ARROW_GRIP_POSITION, weapon_profile
	)
	female_front_rig.equip_weapon(
		texture, flip_face_on_back, grip_position, offhand_texture, ARROW_GRIP_POSITION, weapon_profile
	)
	female_back_rig.equip_weapon(
		texture, flip_face_on_back, grip_position, offhand_texture, ARROW_GRIP_POSITION, weapon_profile
	)
	sword_button.disabled = weapon_name == &"sword"
	short_sword_button.disabled = weapon_name == &"short_sword"
	bow_button.disabled = weapon_name == &"bow"
	weapon_status.text = "Weapon: %s" % str(weapon_name).replace("_", " ").capitalize()


func _play_all(animation_name: StringName) -> void:
	male_front_rig.play(animation_name)
	male_back_rig.play(animation_name)
	female_front_rig.play(animation_name)
	female_back_rig.play(animation_name)
	idle_button.disabled = animation_name == &"idle"
	walk_button.disabled = animation_name == &"walk"
	attack_button.disabled = animation_name == &"attack"
	animation_status.text = "再生中: %s" % str(animation_name).capitalize()
