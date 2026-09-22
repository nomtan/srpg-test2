extends "res://scripts/world_jrpg/pixel_actor.gd"
## Keep one gameplay actor when switching visuals, including during battle.
const MODEL = preload("res://assets/world_jrpg/explorer_base_1.glb")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const WALK_CYCLE_SPEED := 4.5
const RUN_CYCLE_SPEED := 12.8 # Full sprint uses 1.25x, avoiding frantic torso bob at 2x.
@export var model_scene: PackedScene = MODEL
# Exploration supplies actual horizontal speed; -1 keeps standalone/battle clips native.
var locomotion_speed := -1.0
var model: Node3D
var animation_player: AnimationPlayer
var use_3d := true
var sword_combat: RefCounted
var attacking := false

func _ready() -> void:
	super._ready()
	set_model_scene(model_scene)

func set_model_scene(scene: PackedScene, roster_layout := false) -> void:
	if scene == null: return
	attacking = false
	sword_combat = null
	var phase := -1.0
	if animation_player and animation_player.current_animation in ["walk", "run"]:
		phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)
	var previous := model
	if previous:
		remove_child(previous)
		previous.queue_free()
	model_scene = scene
	model = scene.instantiate()
	model.name = "CharacterModel"
	if roster_layout:
		# NPC visuals face +Z; the exploration controller expects +X.
		var visual := model.get_node("Model") as Node3D
		visual.rotation.y = PI / 2.0
		var label := model.get_node_or_null("NameLabel") as Label3D
		if label: label.hide()
	add_child(model)
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["idle", "walk", "run"]:
		if animation_player and animation_player.has_animation(clip):
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var equipment := SwordCombat.new()
	if equipment.install(model, animation_player):
		sword_combat = equipment
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	set_3d_enabled(use_3d)
	if phase >= 0.0 and animation_player and animation_player.current_animation in ["walk", "run"]:
		animation_player.seek(phase * animation_player.current_animation_length, true)

func set_3d_enabled(enabled: bool) -> void:
	if not enabled: cancel_attack()
	use_3d = enabled
	if not model: return
	model.visible = enabled
	sprite.visible = not enabled
	if enabled:
		_update_model()
	elif animation_player:
		animation_player.pause()

func _process(delta: float) -> void:
	super._process(delta)
	if use_3d: _update_model()

func _update_model() -> void:
	if not model or not animation_player: return
	if attacking: return
	# The source character faces +X; turn its visual without rotating gameplay axes.
	if not world_facing.is_zero_approx():
		model.rotation.y = -atan2(world_facing.z, world_facing.x)
	var clip := "run" if walking and running else ("walk" if walking else "idle")
	# Models with only a walk cycle also support sprinting at the existing cadence.
	if clip == "run" and not animation_player.has_animation("run"):
		clip = "walk"
	animation_player.speed_scale = 1.0
	if walking and locomotion_speed >= 0.0:
		animation_player.speed_scale = locomotion_speed / (RUN_CYCLE_SPEED if running else WALK_CYCLE_SPEED)
	if animation_player.current_animation != clip or not animation_player.is_playing():
		var previous := animation_player.current_animation
		var phase := -1.0
		if previous in ["walk", "run"] and clip in ["walk", "run"]:
			phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)
		animation_player.play(clip, 0.12)
		# Keep the same supporting leg when Shift changes the gait, and resume
		# the paused cycle when switching back from 2D instead of restarting it.
		if phase >= 0.0:
			animation_player.seek(phase * animation_player.get_animation(clip).length, true)

func attack(overhead := false) -> bool:
	if attacking or not use_3d or sword_combat == null: return false
	_update_model()
	attacking = true
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	animation_player.play(SwordCombat.OVERHEAD if overhead else SwordCombat.SLASH, 0.07)
	return true

func cancel_attack() -> void:
	if not attacking: return
	attacking = false
	_update_model()

func _on_animation_finished(clip: StringName) -> void:
	if clip in [SwordCombat.SLASH, SwordCombat.OVERHEAD]:
		attacking = false
		_update_model()
