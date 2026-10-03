extends "res://scripts/character/tripo_roster_character.gd"
## Sample actor for a generated GLB with a limited animation set.
@export var generated_model: PackedScene
@export var default_animation := "walk"

func prepare_visual() -> void:
	if _assembled or generated_model == null:
		return
	var visual := generated_model.instantiate() as Node3D
	CharacterAssembler._apply_toon(visual)
	$Model.add_child(visual)
	_assembled = true

func play_animation(clip: String) -> bool:
	if animation_player == null:
		return false
	var selected := clip if animation_player.has_animation(clip) else default_animation
	if not animation_player.has_animation(selected):
		return false
	animation_player.get_animation(selected).loop_mode = Animation.LOOP_LINEAR
	animation_player.play(selected, 0.15)
	return true
