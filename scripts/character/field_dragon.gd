extends Node3D
## A dragon placed by hand in a field scene (assets/characters/enemy/dragon/model.glb, built by
## tools/asset_gen/character_pipeline/build_dragon.py). It crouches, breathes and looks about on
## "idle" and every few seconds rears up to roar ("roar") or to beat its wings ("flap"). Once the
## world has built its terrain it turns toward face_toward and settles onto the ground under its
## feet. The visual faces +Z.

## Seconds between displays, picked at random in this range.
const ROAR_EVERY := Vector2(7.0, 12.0)
## Displays it breaks off its idle for, one picked at random each time.
const DISPLAYS := ["roar", "flap"]
## Foot centres in model units (+Z forward, +X the dragon's left): front left, front right, hind
## left, hind right; scaled by $Model.scale. Sampled so the dragon leans with the ground.
const FEET := [Vector3(0.068, 0, 0.277), Vector3(-0.085, 0, 0.332), Vector3(0.119, 0, -0.015), Vector3(-0.08, 0, 0.11)]
## Each foot is also sampled this far (model units) ahead, behind and to the sides, covering the toes.
const FOOT_REACH := 0.045
## Steepest lean it takes from the ground under its feet (12 degrees).
const MAX_LEAN := 0.2094

@export var model_scene: PackedScene
@export var display_name := "レッドドラゴン"
## World XZ it turns to face once placed (e.g. the explorer's spawn); zero keeps the scene rotation.
@export var face_toward := Vector2.ZERO

var animation_player: AnimationPlayer
var _until_roar := 0.0


func _ready() -> void:
	if model_scene and $Model.get_child_count() == 0:
		$Model.add_child(model_scene.instantiate())
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player:
		if animation_player.has_animation("idle"):
			animation_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		animation_player.animation_finished.connect(func(clip: StringName) -> void:
			if String(clip) in DISPLAYS: animation_player.play("idle", 0.4))
		animation_player.play("idle")
	$NameLabel.text = display_name
	_until_roar = randf_range(ROAR_EVERY.x, ROAR_EVERY.y)
	# The world builds its terrain in its own _ready, after its children's.
	_settle.call_deferred()


func _settle() -> void:
	if face_toward != Vector2.ZERO:
		rotation.y = atan2(face_toward.x - position.x, face_toward.y - position.z)
	var world := get_parent()
	if world == null or not world.has_method("get_gameplay_height"):
		return
	# Lean with the plane through the four feet.
	var scale_by: float = $Model.scale.x
	var yaw := Basis(Vector3.UP, rotation.y)
	var feet: Array[Vector3] = []
	for foot: Vector3 in FEET:
		var at := position + yaw * (foot * scale_by)
		feet.append(Vector3(at.x, world.get_gameplay_height(at.x, at.z), at.z))
	# The stance is staggered, so the feet give only the tilt; the heading stays as turned above.
	var up := ((feet[0] + feet[1]) - (feet[2] + feet[3])).cross((feet[0] + feet[2]) - (feet[1] + feet[3])).normalized()
	# A big body stays near upright on steep ground; the sinking below takes up the rest.
	var lean := up.angle_to(Vector3.UP)
	if lean > MAX_LEAN: up = Vector3.UP.slerp(up, MAX_LEAN / lean)
	var heading := yaw.z
	var forward := (heading - up * heading.dot(up)).normalized()
	var tilted := Basis(up.cross(forward), up, forward)
	# Then sink until no sample under a foot is left below it: every foot touches or presses into
	# the ground, none hangs in the air (a lean moves each foot's height by its own offset).
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3(FOOT_REACH, 0, 0), Vector3(-FOOT_REACH, 0, 0),
		Vector3(0, 0, FOOT_REACH), Vector3(0, 0, -FOOT_REACH)]
	var lowest := INF
	for foot: Vector3 in FEET:
		for offset in offsets:
			var local := tilted * ((foot + offset) * scale_by)
			var at := position + local
			lowest = minf(lowest, world.get_gameplay_height(at.x, at.z) - local.y)
	position.y = lowest
	basis = tilted


func _process(delta: float) -> void:
	if animation_player == null or animation_player.current_animation != "idle":
		return
	_until_roar -= delta
	if _until_roar > 0.0:
		return
	var shows: Array = DISPLAYS.filter(func(clip: String) -> bool: return animation_player.has_animation(clip))
	if not shows.is_empty():
		animation_player.play(shows.pick_random(), 0.4)
	_until_roar = randf_range(ROAR_EVERY.x, ROAR_EVERY.y)
