extends RefCounted
## Builds a run cycle from a Body's walk clip, for Bodies that ship without one.
## Key timing stays proportional to the walk, so a normalized walk phase is the same
## stride position in the run and the two clips crossfade without swapping legs.

const LENGTH := 0.7
# Swing gains around the walk's average pose (thigh, upper arm).
const THIGH_GAIN := 2.1
const ARM_GAIN := 1.8
# Knee gain is measured from the straightest walk key, so it only deepens the bend.
const KNEE_GAIN := 2.4
const HIPS_LEAN := deg_to_rad(5.0)
const CHEST_LEAN := deg_to_rad(10.0)
const HEAD_LIFT := deg_to_rad(-9.0)
const ELBOW_BEND := deg_to_rad(75.0)
# Fraction of leg length; the hips only rise (never sink), so planted feet stay above the ground.
const BOUNCE := 0.05
const BONES := {
	hips = "mixamorig_Hips", chest = "mixamorig_Spine2", head = "head",
	thigh_l = "mixamorig_LeftUpLeg", thigh_r = "mixamorig_RightUpLeg",
	knee_l = "mixamorig_LeftLeg", knee_r = "mixamorig_RightLeg",
	foot_l = "mixamorig_LeftFoot",
	arm_l = "mixamorig_LeftArm", arm_r = "mixamorig_RightArm",
	forearm_l = "mixamorig_LeftForeArm", forearm_r = "mixamorig_RightForeArm",
}

# One run per source walk; Bodies that share a walk clip share its run.
static var _cache: Dictionary = {}

static func build(walk: Animation, skeleton: Skeleton3D, path: NodePath) -> Animation:
	if _cache.has(walk): return _cache[walk]
	for bone: String in BONES.values():
		if skeleton.find_bone(bone) < 0: return null
	var run := Animation.new()
	run.length = LENGTH
	run.loop_mode = Animation.LOOP_LINEAR
	var stretch := LENGTH / walk.length
	var gains := {BONES.thigh_l: THIGH_GAIN, BONES.thigh_r: THIGH_GAIN, BONES.arm_l: ARM_GAIN, BONES.arm_r: ARM_GAIN}
	var leans := {
		BONES.chest: Quaternion(Vector3.RIGHT, CHEST_LEAN),
		BONES.head: Quaternion(Vector3.RIGHT, HEAD_LIFT),
		BONES.forearm_l: _elbow(walk, skeleton, path, BONES.arm_l),
		BONES.forearm_r: _elbow(walk, skeleton, path, BONES.arm_r),
	}
	for track in walk.get_track_count():
		var bone := str(walk.track_get_path(track).get_concatenated_subnames())
		var type := walk.track_get_type(track)
		if (type == Animation.TYPE_ROTATION_3D and bone in leans) or bone == BONES.hips:
			continue # Rebuilt below with the lean and bounce applied.
		var copy := run.add_track(type)
		run.track_set_path(copy, walk.track_get_path(track))
		run.track_set_interpolation_type(copy, walk.track_get_interpolation_type(track))
		var pivot := Quaternion.IDENTITY
		var gain := 1.0
		if type == Animation.TYPE_ROTATION_3D and (bone in gains or bone in [BONES.knee_l, BONES.knee_r]):
			pivot = _average(walk, track) if bone in gains else _straightest(walk, track, skeleton.get_bone_rest(skeleton.find_bone(bone)).basis.get_rotation_quaternion())
			gain = gains.get(bone, KNEE_GAIN)
		for key in walk.track_get_key_count(track):
			var value: Variant = walk.track_get_key_value(track, key)
			if gain != 1.0: value = pivot * _scaled(pivot.inverse() * value, gain)
			run.track_insert_key(copy, walk.track_get_key_time(track, key) * stretch, value)
	for bone: String in leans:
		_add_leaned(run, walk, skeleton, path, bone, leans[bone], stretch)
	_add_hips(run, skeleton, path, _crossing_phase(walk, path))
	_cache[walk] = run
	return run

## Rotation that bends the elbow so the forearm swings forward, in skeleton space.
static func _elbow(walk: Animation, skeleton: Skeleton3D, path: NodePath, upper_arm: String) -> Quaternion:
	var bone := skeleton.find_bone(upper_arm)
	var shoulder := skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).basis.get_rotation_quaternion()
	var track := walk.find_track(NodePath("%s:%s" % [path, upper_arm]), Animation.TYPE_ROTATION_3D)
	var local := _average(walk, track) if track >= 0 else skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	var direction := (shoulder * local) * Vector3.UP
	return Quaternion(direction.cross(Vector3.BACK).normalized(), ELBOW_BEND)

## Copies a rotation track (or the bone's rest when the walk leaves it still), turned by a
## skeleton-space rotation applied in the parent's rest frame.
static func _add_leaned(run: Animation, walk: Animation, skeleton: Skeleton3D, path: NodePath, bone: String, lean: Quaternion, stretch: float) -> void:
	var index := skeleton.find_bone(bone)
	var parent := skeleton.get_bone_parent(index)
	var frame := skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var local_lean := frame.inverse() * lean * frame
	var node_path := NodePath("%s:%s" % [path, bone])
	var source := walk.find_track(node_path, Animation.TYPE_ROTATION_3D)
	var track := run.add_track(Animation.TYPE_ROTATION_3D)
	run.track_set_path(track, node_path)
	if source < 0:
		run.track_insert_key(track, 0.0, local_lean * skeleton.get_bone_rest(index).basis.get_rotation_quaternion())
		return
	for key in walk.track_get_key_count(source):
		run.track_insert_key(track, walk.track_get_key_time(source, key) * stretch, local_lean * walk.track_get_key_value(source, key))

## Forward lean and a two-beat bounce, lowest as the legs pass each other (mid-stance).
static func _add_hips(run: Animation, skeleton: Skeleton3D, path: NodePath, low_phase: float) -> void:
	var hips := skeleton.find_bone(BONES.hips)
	var node_path := NodePath("%s:%s" % [path, BONES.hips])
	var rest := skeleton.get_bone_rest(hips)
	var rotation := run.add_track(Animation.TYPE_ROTATION_3D)
	run.track_set_path(rotation, node_path)
	run.track_insert_key(rotation, 0.0, Quaternion(Vector3.RIGHT, HIPS_LEAN) * rest.basis.get_rotation_quaternion())
	var leg := rest.origin.y - skeleton.get_bone_global_rest(skeleton.find_bone(BONES.foot_l)).origin.y
	var position := run.add_track(Animation.TYPE_POSITION_3D)
	run.track_set_path(position, node_path)
	for step in 16:
		var phase := step / 16.0
		var rise := 0.5 * (1.0 - cos(TAU * 2.0 * (phase - low_phase)))
		run.track_insert_key(position, phase * LENGTH, rest.origin + Vector3.UP * rise * BOUNCE * leg)

## Normalized walk time where the left thigh passes its average swing.
static func _crossing_phase(walk: Animation, path: NodePath) -> float:
	var track := walk.find_track(NodePath("%s:%s" % [path, BONES.thigh_l]), Animation.TYPE_ROTATION_3D)
	if track < 0: return 0.0
	var average := _average(walk, track)
	var best := 0
	for key in walk.track_get_key_count(track):
		if (average.inverse() * walk.track_get_key_value(track, key)).get_angle() < (average.inverse() * walk.track_get_key_value(track, best)).get_angle():
			best = key
	return walk.track_get_key_time(track, best) / walk.length

static func _average(walk: Animation, track: int) -> Quaternion:
	var first: Quaternion = walk.track_get_key_value(track, 0)
	var sum := Quaternion(0, 0, 0, 0)
	for key in walk.track_get_key_count(track):
		var value: Quaternion = walk.track_get_key_value(track, key)
		sum += value if value.dot(first) >= 0.0 else -value
	return sum.normalized()

static func _straightest(walk: Animation, track: int, rest: Quaternion) -> Quaternion:
	var best: Quaternion = walk.track_get_key_value(track, 0)
	for key in walk.track_get_key_count(track):
		var value: Quaternion = walk.track_get_key_value(track, key)
		if (rest.inverse() * value).get_angle() < (rest.inverse() * best).get_angle():
			best = value
	return best

static func _scaled(delta: Quaternion, gain: float) -> Quaternion:
	if delta.w < 0.0: delta = -delta
	var axis := Vector3(delta.x, delta.y, delta.z)
	if axis.length_squared() < 1e-10: return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), delta.get_angle() * gain)
