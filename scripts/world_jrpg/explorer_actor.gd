extends "res://scripts/world_jrpg/pixel_actor.gd"
## Keep one gameplay actor when switching visuals, including during battle.
const MODEL = preload("res://scenes/characters/tripo_roster/charcter001.tscn")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const RunCycle = preload("res://scripts/world_jrpg/run_cycle.gd")
const WALK_CYCLE_SPEED := 4.5
const RUN_CYCLE_SPEED := 12.8 # Full sprint uses 1.25x, avoiding frantic torso bob at 2x.
# Still faster than a walk while slowing from a sprint: keep the run until then.
const RUN_EXIT_SPEED := 5.5
const GAIT_BLEND := 0.25
@export var model_scene: PackedScene = MODEL
# Exploration supplies actual horizontal speed; -1 keeps standalone/battle clips native.
var locomotion_speed := -1.0
var model: Node3D
var animation_player: AnimationPlayer
# The Body's own run, or one built from its walk.
var run_clip := "run"
var use_3d := true
var sword_combat: RefCounted
var attacking := false
var guarding := false

func _ready() -> void:
	super._ready()
	set_model_scene(model_scene)

func set_model_scene(scene: PackedScene, roster_layout := false) -> void:
	if scene == null: return
	attacking = false
	guarding = false
	sword_combat = null
	var phase := -1.0
	if animation_player and animation_player.current_animation in ["walk", run_clip]:
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
	_add_run_cycle()
	var equipment := SwordCombat.new()
	if equipment.install(model, animation_player):
		sword_combat = equipment
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	set_3d_enabled(use_3d)
	if phase >= 0.0 and animation_player and animation_player.current_animation in ["walk", run_clip]:
		animation_player.seek(phase * animation_player.current_animation_length, true)

func _add_run_cycle() -> void:
	run_clip = "run"
	if animation_player == null or animation_player.has_animation("run") or not animation_player.has_animation("walk"): return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null: return
	var path := animation_player.get_node(animation_player.root_node).get_path_to(skeleton)
	var run := RunCycle.build(animation_player.get_animation("walk"), skeleton, path)
	if run == null: return
	# A library of its own leaves the Body's imported clips untouched.
	var library := AnimationLibrary.new()
	library.add_animation("run", run)
	animation_player.add_animation_library("gait", library)
	run_clip = "gait/run"

func set_3d_enabled(enabled: bool) -> void:
	if not enabled:
		cancel_attack()
		guarding = false
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
	if attacking or guarding: return
	# The source character faces +X; turn its visual without rotating gameplay axes.
	if not world_facing.is_zero_approx():
		model.rotation.y = -atan2(world_facing.z, world_facing.x)
	var gaits := ["walk", run_clip]
	# Easing out of a sprint keeps the run until the speed is back near a walk.
	var run := walking and (running or locomotion_speed > RUN_EXIT_SPEED)
	var clip := run_clip if run else ("walk" if walking else "idle")
	# Models with only a walk cycle also support sprinting at the existing cadence.
	if clip == run_clip and not animation_player.has_animation(run_clip):
		clip = "walk"
	var resting_walk := clip == "idle" and not animation_player.has_animation("idle") and animation_player.has_animation("walk")
	if resting_walk:
		clip = "walk"
	animation_player.speed_scale = 1.0
	if walking and locomotion_speed >= 0.0:
		var walk_scale := locomotion_speed / WALK_CYCLE_SPEED
		if clip == run_clip:
			# Never step slower than the walk did, so speeding up only quickens the cadence.
			var walk_length := animation_player.get_animation("walk").length
			animation_player.speed_scale = maxf(locomotion_speed / RUN_CYCLE_SPEED, minf(walk_scale, 1.0) * animation_player.get_animation(clip).length / walk_length)
		elif run:
			animation_player.speed_scale = locomotion_speed / RUN_CYCLE_SPEED
		else:
			animation_player.speed_scale = minf(walk_scale, 1.0)
	if resting_walk:
		animation_player.speed_scale = 0.0
	if animation_player.current_animation != clip or not animation_player.is_playing():
		var previous := animation_player.current_animation
		var phase := -1.0
		if previous in gaits and clip in gaits:
			phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)
		animation_player.play(clip, GAIT_BLEND if phase >= 0.0 else 0.12)
		# Keep the same supporting leg when Shift changes the gait, and resume
		# the paused cycle when switching back from 2D instead of restarting it.
		if phase >= 0.0:
			animation_player.seek(phase * animation_player.get_animation(clip).length, true)

func attack(overhead := false) -> bool:
	if attacking or guarding or not use_3d or sword_combat == null: return false
	_update_model()
	attacking = true
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	# Dual wielders alternate right and left hands on the horizontal slash.
	animation_player.play(sword_combat.overhead_clip if overhead else sword_combat.next_slash_clip(), 0.07)
	return true

## Guard (shield or greatsword) while held; the guard clip ends on the held pose until released.
func set_guard(enabled: bool) -> void:
	if enabled == guarding: return
	if enabled and (attacking or not use_3d or sword_combat == null or sword_combat.guard_clip.is_empty()): return
	guarding = enabled
	if not enabled:
		_update_model()
		return
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	animation_player.play(sword_combat.guard_clip, 0.06)

func cancel_attack() -> void:
	if not attacking: return
	attacking = false
	_update_model()

func _on_animation_finished(clip: StringName) -> void:
	if sword_combat and sword_combat.is_attack_clip(clip):
		attacking = false
		_update_model()
