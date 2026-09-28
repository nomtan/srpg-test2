extends SkeletonModifier3D
## Two-handed greatsword hold applied after the animation every frame.
## Outside the greatsword clips (idle, walk, run, hit) the arms are raised into the ready stance;
## the greatsword clips start and end in that stance, so the override fades out as they begin.
## In every clip the left hand is solved onto the handle below the right hand.
const FADE := 0.12

var combat: RefCounted
var player: AnimationPlayer
var clip_prefix := ""
var ready_weight := 1.0

func setup(equipment: RefCounted, animation_player: AnimationPlayer, prefix: String) -> void:
	combat = equipment
	player = animation_player
	clip_prefix = prefix

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or combat == null or player == null: return
	# assigned_animation keeps the held guard pose after its clip has finished.
	var target := 1.0
	if String(player.assigned_animation).begins_with(clip_prefix):
		target = clampf(1.0 - player.current_animation_position / FADE, 0.0, 1.0) if player.is_playing() else 0.0
	ready_weight = target if target < ready_weight else move_toward(ready_weight, target, delta / FADE)
	combat.apply_grip(skeleton, ready_weight)
