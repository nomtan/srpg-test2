extends "res://scripts/world_jrpg/pixel_actor.gd"
## Keep one gameplay actor when switching visuals, including during battle.
const MODEL = preload("res://assets/world_jrpg/explorer_base_1.glb")
var model: Node3D
var animation_player: AnimationPlayer
var use_3d := true

func _ready() -> void:
	super._ready()
	model = MODEL.instantiate()
	model.name = "Base1Model"
	add_child(model)
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["idle", "walk", "run"]:
		if animation_player and animation_player.has_animation(clip):
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	set_3d_enabled(use_3d)

func set_3d_enabled(enabled: bool) -> void:
	use_3d = enabled
	if not model: return
	model.visible = enabled
	sprite.visible = not enabled
	if enabled:
		_update_model()
	else:
		animation_player.pause()

func _process(delta: float) -> void:
	super._process(delta)
	if use_3d: _update_model()

func _update_model() -> void:
	if not model or not animation_player: return
	# The source character faces +X; turn its visual without rotating gameplay axes.
	if not world_facing.is_zero_approx():
		model.rotation.y = -atan2(world_facing.z, world_facing.x)
	var clip := "run" if walking and running else ("walk" if walking else "idle")
	if animation_player.current_animation != clip or not animation_player.is_playing():
		animation_player.play(clip, 0.12)
