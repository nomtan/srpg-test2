extends "res://scripts/world_jrpg/pixel_actor.gd"
## Keep one gameplay actor when switching visuals, including during battle.
const MODEL = preload("res://scenes/characters/tripo_roster/charcter001.tscn")
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const RunCycle = preload("res://scripts/world_jrpg/run_cycle.gd")
const GroundSit = preload("res://scripts/world_jrpg/ground_sit.gd")
const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
const WALK_CYCLE_SPEED := 4.5
const RUN_CYCLE_SPEED := 12.8 # Full sprint uses 1.25x, avoiding frantic torso bob at 2x.
# Still faster than a walk while slowing from a sprint: keep the run until then.
const RUN_EXIT_SPEED := 5.5
const GAIT_BLEND := 0.25
const SIT_SWITCH_BLEND := 0.6
## The attack clip just reached its contact moment (the arrow's release for the bow).
signal attack_impact(clip: String)
@export var model_scene: PackedScene = MODEL
# Exploration supplies actual horizontal speed; -1 keeps standalone/battle clips native.
var locomotion_speed := -1.0
var model: Node3D
var animation_player: AnimationPlayer
# Unarmed models walk and run with the procedural gait, sword and shield with its own stance and
# gait (SwordGait); other armed ones keep the Body's walk and its own run, or one built from that walk.
var idle_clip := "idle"
var walk_clip := "walk"
var run_clip := "run"
var use_3d := true
var sword_combat: RefCounted
var attacking := false
var guarding := false
# Unarmed models can sit on the ground: "" standing, "down" sitting down, "seated", "up" standing up.
# Equipment chosen for the current model (a SwordCombat loadout or "none"); "" keeps the character's own.
var weapon := ""
# Body part worn instead of the character's own (a CharacterDefinition body_id); "" keeps it.
var body := ""
# Face part worn instead of the character's own (a CharacterDefinition face_id); "" keeps it.
var face := ""
var _roster_layout := false
var can_sit := false
var posture := ""
# Which GroundSit pose ("knees" or "stretch") the current sit uses.
var sit_pose := "knees"
var _impact_clip := ""
var _impact_time := -1.0

func _ready() -> void:
	super._ready()
	set_model_scene(model_scene)

func set_model_scene(scene: PackedScene, roster_layout := false) -> void:
	if scene == null: return
	# A different character starts with its own equipment and Body.
	if scene != model_scene:
		weapon = ""
		body = ""
		face = ""
	_roster_layout = roster_layout
	attacking = false
	guarding = false
	sword_combat = null
	posture = ""
	var phase := -1.0
	if animation_player and animation_player.current_animation in [walk_clip, run_clip]:
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
	if not weapon.is_empty(): model.set_meta("loadout", weapon)
	# The roster scene assembles its Body/Face on _ready, so swap the Body / Face in a private copy
	# of its definition before it enters the tree (the shared .tres stays untouched).
	if (not body.is_empty() or not face.is_empty()) and model.get("definition") is CharacterDefinition:
		var definition := (model.get("definition") as CharacterDefinition).duplicate() as CharacterDefinition
		if not body.is_empty(): definition.body_id = body
		# face_offset / face_scale fit the character's own Face only; another Face sits at its normalized place.
		if not face.is_empty() and face != definition.face_id:
			definition.face_id = face
			definition.face_offset = Vector3.ZERO
			definition.face_scale = 1.0
		model.set("definition", definition)
	add_child(model)
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["idle", "walk", "run"]:
		if animation_player and animation_player.has_animation(clip):
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var equipment := SwordCombat.new()
	if equipment.install(model, animation_player):
		sword_combat = equipment
	# Weapon holds are tuned against the Body's walk and would fight the seated pose,
	# so only unarmed models take the procedural gait and sit.
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	idle_clip = "idle"
	walk_clip = "walk"
	if sword_combat and not sword_combat.idle_clip.is_empty():
		idle_clip = sword_combat.idle_clip
		walk_clip = sword_combat.walk_clip
		run_clip = sword_combat.run_clip
	elif sword_combat == null and GaitCycle.install(animation_player, skeleton):
		walk_clip = GaitCycle.WALK
		run_clip = GaitCycle.RUN
	else:
		_add_run_cycle()
	can_sit = sword_combat == null and GroundSit.install(animation_player, skeleton)
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	set_3d_enabled(use_3d)
	if phase >= 0.0 and animation_player and animation_player.current_animation in [walk_clip, run_clip]:
		animation_player.seek(phase * animation_player.current_animation_length, true)

## Re-equips the current model with a SwordCombat loadout, or "none" for bare hands.
func set_weapon(loadout: String) -> void:
	weapon = loadout
	set_model_scene(model_scene, _roster_layout)

## Rebuilds the current character on another Body (a CharacterDefinition body_id).
func set_body(body_id: String) -> void:
	body = body_id
	set_model_scene(model_scene, _roster_layout)

## The Body the current model wears ("" for a model without a CharacterDefinition).
func current_body() -> String:
	var definition = model.get("definition") if model else null
	return definition.body_id if definition is CharacterDefinition else ""

## Rebuilds the current character with another Face (a CharacterDefinition face_id).
func set_face(face_id: String) -> void:
	face = face_id
	set_model_scene(model_scene, _roster_layout)

## The Face the current model wears ("" for a model without a CharacterDefinition).
func current_face() -> String:
	var definition = model.get("definition") if model else null
	return definition.face_id if definition is CharacterDefinition else ""

## The equipment the current model carries ("none" when unarmed).
func current_weapon() -> String:
	return sword_combat.loadout if sword_combat else "none"

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
		posture = ""
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
	_check_impact()

func _check_impact() -> void:
	if not attacking or sword_combat == null or animation_player == null: return
	var clip := String(animation_player.current_animation)
	var time := animation_player.current_animation_position
	if clip != _impact_clip or time < _impact_time:
		_impact_clip = clip
		_impact_time = -1.0
	var impact: float = sword_combat.impact_time(clip)
	if impact >= 0.0 and _impact_time < impact and time >= impact:
		attack_impact.emit(clip)
	_impact_time = time

func _update_model() -> void:
	if not model or not animation_player: return
	if attacking or guarding or posture != "": return
	# The source character faces +X; turn its visual without rotating gameplay axes.
	if not world_facing.is_zero_approx():
		model.rotation.y = -atan2(world_facing.z, world_facing.x)
	var gaits := [walk_clip, run_clip]
	# Easing out of a sprint keeps the run until the speed is back near a walk.
	var run := walking and (running or locomotion_speed > RUN_EXIT_SPEED)
	var clip := run_clip if run else (walk_clip if walking else idle_clip)
	# Models with only a walk cycle also support sprinting at the existing cadence.
	if clip == run_clip and not animation_player.has_animation(run_clip):
		clip = walk_clip
	var resting_walk := clip == idle_clip and not animation_player.has_animation(idle_clip) and animation_player.has_animation(walk_clip)
	if resting_walk:
		clip = walk_clip
	animation_player.speed_scale = 1.0
	if walking and locomotion_speed >= 0.0:
		var walk_scale := locomotion_speed / WALK_CYCLE_SPEED
		if clip == run_clip:
			# Never step slower than the walk did, so speeding up only quickens the cadence.
			var walk_length := animation_player.get_animation(walk_clip).length
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
	_impact_clip = ""
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	# Dual wielders alternate right and left hands on the horizontal slash.
	animation_player.play(sword_combat.overhead_clip if overhead else sword_combat.next_slash_clip(), 0.07)
	return true

## The equipped weapon's skill (sword and shield only); false when there is none or the actor is busy.
func skill() -> bool:
	if attacking or guarding or not use_3d or sword_combat == null or sword_combat.skill_clip.is_empty(): return false
	_update_model()
	attacking = true
	_impact_clip = ""
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	animation_player.play(sword_combat.skill_clip, 0.07)
	return true

## Freezes the running attack clip (and its slash arcs) for `seconds` as a hit-stop, then resumes normal speed.
func hold_attack(seconds: float) -> void:
	if not attacking or animation_player == null: return
	var clip := animation_player.current_animation
	animation_player.speed_scale = 0.0
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if attacking and animation_player.current_animation == clip: animation_player.speed_scale = 1.0)

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

## Sits down in pose (a GroundSit.POSES key), or stands back up when seated in any pose. A toggle
## mid-way reverses from the same pose.
func toggle_sit(pose := "knees") -> bool:
	if not can_sit or not use_3d or attacking or guarding: return false
	var sitting := posture in ["", "up"]
	# Reversing a stand-up keeps the pose it is rising from.
	if posture == "": sit_pose = pose
	var resume := 0.0
	if posture in ["down", "up"]:
		resume = animation_player.current_animation_length - animation_player.current_animation_position
	posture = "down" if sitting else "up"
	walking = false
	running = false
	animation_player.speed_scale = 1.0
	var clips: Array = GroundSit.POSES[sit_pose]
	animation_player.play(clips[0] if sitting else clips[2], 0.15 if resume == 0.0 else 0.0)
	if resume > 0.0: animation_player.seek(resume, true)
	return true

## While seated, eases straight into the next GroundSit pose without standing up.
func switch_sit_pose() -> bool:
	if posture != "seated": return false
	var poses: Array = GroundSit.POSES.keys()
	sit_pose = poses[(poses.find(sit_pose) + 1) % poses.size()]
	animation_player.play(GroundSit.POSES[sit_pose][1], SIT_SWITCH_BLEND)
	return true

## Drops straight back to standing (battle start, model switch).
func stand_now() -> void:
	if posture == "": return
	posture = ""
	_update_model()

func cancel_attack() -> void:
	if not attacking: return
	attacking = false
	_update_model()

func _on_animation_finished(clip: StringName) -> void:
	var clips: Array = GroundSit.POSES[sit_pose]
	if clip == StringName(clips[0]) and posture == "down":
		posture = "seated"
		animation_player.play(clips[1], 0.2)
		return
	if clip == StringName(clips[2]) and posture == "up":
		posture = ""
		_update_model()
		return
	if sword_combat and sword_combat.is_attack_clip(clip):
		attacking = false
		_update_model()
