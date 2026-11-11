extends Node3D
## A whole-character model with its own skeleton and clips (tools/asset_gen/character_pipeline/
## build_rigged_character.py), outside the Body + Face standard. It offers the roster actor's
## surface (character_id, display_name, dialogue, animation_player, play_animation) so the
## explorer and the roster can use it like a tripo_roster character. Its bones carry humanoid_v1
## names, so SwordCombat equips it (the loadout comes from SwordCombat.LOADOUTS, sword and shield by
## default) and the shared procedural stance, gait and attack clips drive it.
## Drawn with the model's own imported materials, so the scene's lights and time of day shade it.

const ForearmTwist := preload("res://scripts/character/forearm_twist.gd")

@export var character_id := ""
@export var display_name := ""
@export var dialogue: PackedStringArray = ["……。"]

var animation_player: AnimationPlayer


func _ready() -> void:
	# Deferred: the explorer equips the model right after adding it, and the twist must come after the
	# equipment's own skeleton modifiers.
	_add_forearm_twist.call_deferred()
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null: return
	var rig := animation_player.get_parent()
	var looping: Array = rig.get_meta("extras", {}).get("looping_clips", ["idle", "walk", "run"]) if rig else []
	for clip: String in looping:
		if animation_player.has_animation(clip):
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	play_animation("idle")


func play_animation(clip: String) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, 0.15)
	return true



func _add_forearm_twist() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.has_node("ForearmTwist"): return
	var twist: SkeletonModifier3D = ForearmTwist.new()
	twist.name = "ForearmTwist"
	skeleton.add_child(twist)
	if not twist.has_twist_bones(): twist.queue_free()
