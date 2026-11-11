extends Node3D
## A whole-character model with its own skeleton and clips (tools/asset_gen/character_pipeline/
## build_rigged_character.py), outside the Body + Face standard. It offers the roster actor's
## surface (character_id, display_name, dialogue, animation_player, play_animation) so the
## explorer and the roster can use it like a tripo_roster character. Unarmed: the skeleton is not
## humanoid_v1, so no weapon loadout fits it and it moves with the clips baked into its model.

@export var character_id := ""
@export var display_name := ""
@export var dialogue: PackedStringArray = ["……。"]

var animation_player: AnimationPlayer


func _ready() -> void:
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
