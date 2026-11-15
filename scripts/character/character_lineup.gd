extends Node3D
## A row of characters placed by hand in a field scene for side-by-side comparison, each wearing the
## same SwordCombat loadout (sheathed by default) and standing on "idle" with its name label. The row
## runs along the node's local X, centred on it, the characters facing local +Z. Once the world has
## built its terrain the row turns toward face_toward and each character settles onto the ground
## under its own feet. A child of open_field_world.gd: clear_radius keeps trees out of the row.

const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")

@export var characters: Array[PackedScene] = []
## Metres between neighbours along the row.
@export var spacing := 1.6
## SwordCombat loadout worn by everyone ("" keeps each character's own).
@export var loadout := "sword_shield"
## Wear the weapon sheathed (SwordCombat.SHEATHABLE loadouts only).
@export var sheathed := true
## World XZ the row turns to face once placed (e.g. the explorer's spawn); zero keeps the scene rotation.
@export var face_toward := Vector2.ZERO
## Radius (m) of the clearing the field world keeps free of trees and bushes around the row.
@export var clear_radius := 7.0

var models: Array[Node3D] = []
# The installed equipment, kept alive with its model.
var _equipment: Array[RefCounted] = []


func _ready() -> void:
	for index in characters.size():
		if characters[index] == null: continue
		var model := characters[index].instantiate() as Node3D
		if not loadout.is_empty(): model.set_meta("loadout", loadout)
		if sheathed: model.set_meta("sheathed", true)
		model.position.x = (index - (characters.size() - 1) * 0.5) * spacing
		add_child(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var equipment := SwordCombat.new()
		if equipment.install(model, player):
			_equipment.append(equipment)
		if player and player.has_animation("idle"):
			player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			player.play("idle")
			# Out of step, so the row does not breathe in unison.
			player.seek(player.current_animation_length * randf(), true)
		models.append(model)
	# The world builds its terrain in its own _ready, after its children's.
	_settle.call_deferred()


func _settle() -> void:
	if face_toward != Vector2.ZERO:
		rotation.y = atan2(face_toward.x - position.x, face_toward.y - position.z)
	var world := get_parent()
	if world == null or not world.has_method("get_gameplay_height"):
		return
	for model in models:
		var at := global_transform * Vector3(model.position.x, 0.0, model.position.z)
		model.global_position.y = world.get_gameplay_height(at.x, at.z)
