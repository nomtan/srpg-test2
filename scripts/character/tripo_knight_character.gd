extends Node3D
## Stationary NPC; the rig also includes walk/run for animation editing and reuse.
var animation_player: AnimationPlayer

func _ready() -> void:
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	play_animation("idle")

func play_animation(clip: String) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, 0.15)
	return true
