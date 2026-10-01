extends SkeletonModifier3D
## Weapon ready stance applied after the animation every frame (greatsword, dual daggers and bow).
## Outside the weapon's clips (idle, walk, run, hit) the weapon arm holds the loadout's ready stance;
## the override fades out as those clips begin and back in once they end.
## Standing idle adds the stance's half crouch; the walk cycle is left as animated.
## The left hand is solved onto the handle below the right hand wherever the clip swings two-handed.
const FADE := 0.12
const CROUCH_FADE := 0.2

var combat: RefCounted
var player: AnimationPlayer
var clip_prefix := ""
var ready_weight := 1.0
var two_hand_weight := 0.0
var idle_weight := 1.0

func setup(equipment: RefCounted, animation_player: AnimationPlayer, prefix: String) -> void:
	combat = equipment
	player = animation_player
	clip_prefix = prefix

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or combat == null or player == null: return
	# assigned_animation keeps the held guard pose after its clip has finished.
	var clip := String(player.assigned_animation)
	var target := 1.0
	if clip.begins_with(clip_prefix):
		var time := player.current_animation_position if player.is_playing() else player.get_animation(clip).length
		target = clampf(1.0 - time / FADE, 0.0, 1.0) if player.is_playing() else 0.0
		two_hand_weight = combat.two_hand_weight(clip, time)
	else:
		# Let go of the handle smoothly when a clip is interrupted mid-swing or the guard is released.
		two_hand_weight = move_toward(two_hand_weight, 0.0, delta / FADE)
		# Crouch only while standing; the greatsword clips carry their own crouch at start and end.
		idle_weight = move_toward(idle_weight, 1.0 if clip == "idle" else 0.0, delta / CROUCH_FADE)
	ready_weight = target if target < ready_weight else move_toward(ready_weight, target, delta / FADE)
	combat.apply_grip(skeleton, ready_weight, two_hand_weight, ready_weight * idle_weight)
