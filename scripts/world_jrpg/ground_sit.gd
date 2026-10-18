extends "res://scripts/world_jrpg/humanoid_pose.gd"
## Sitting on the ground for an unarmed humanoid_v1 Body: sit down, a breathing seated loop and
## stand up, built from the Body's idle in their own library so the imported clips stay untouched.
## Two seated poses: both knees up with the forearms resting on them, and the same with the left leg
## stretched out along the ground, its hand on the thigh.

const LIBRARY := "rest"
const SIT_DOWN := "rest/sit_down"
const SEATED := "rest/seated"
const STAND_UP := "rest/stand_up"
const STRETCH_DOWN := "rest/stretch_down"
const STRETCHED := "rest/stretched"
const STRETCH_UP := "rest/stretch_up"
## Sit-down, seated loop and stand-up clips per pose.
const POSES := {
	"knees": [SIT_DOWN, SEATED, STAND_UP],
	"stretch": [STRETCH_DOWN, STRETCHED, STRETCH_UP],
}
const SIT_LENGTH := 1.0
const SEATED_LENGTH := 3.2
# Sampled densely so the leg IK keeps the feet on the ground between keys.
const SAMPLES := 16
# Lengths are in leg lengths (hips to ankle).
# drop: hips sink. back: hips shift backward. reach: feet slide forward. stretch: 0 left knee up like the
# right, 1 left leg straight along the ground. lean: pelvis tips back (degrees). chest: spine bends forward.
# arms: 0 idle arms, 1 forearms on the knees (the hand on the thigh for a stretched leg). nod: head tips down.
const SIT_KEYS := [
	{"t": 0.0, "drop": 0.0, "back": 0.0, "reach": 0.0, "stretch": 0.0, "lean": 0.0, "chest": 0.0, "arms": 0.0, "nod": 0.0},
	{"t": 0.4, "drop": 0.5, "back": 0.12, "reach": 0.05, "stretch": 0.0, "lean": 0.0, "chest": 28.0, "arms": 0.35, "nod": 6.0},
	{"t": 0.72, "drop": 0.9, "back": 0.16, "reach": 0.4, "stretch": 0.0, "lean": -14.0, "chest": 16.0, "arms": 0.8, "nod": 4.0},
	{"t": 1.0, "drop": 0.93, "back": 0.16, "reach": 0.6, "stretch": 0.0, "lean": -22.0, "chest": 14.0, "arms": 1.0, "nod": 0.0},
]
# SIT_KEYS, the left leg sliding out straight once the hips are down.
const STRETCH_KEYS := [
	{"t": 0.0, "drop": 0.0, "back": 0.0, "reach": 0.0, "stretch": 0.0, "lean": 0.0, "chest": 0.0, "arms": 0.0, "nod": 0.0},
	{"t": 0.4, "drop": 0.5, "back": 0.12, "reach": 0.05, "stretch": 0.0, "lean": 0.0, "chest": 28.0, "arms": 0.35, "nod": 6.0},
	{"t": 0.72, "drop": 0.9, "back": 0.16, "reach": 0.4, "stretch": 0.4, "lean": -14.0, "chest": 16.0, "arms": 0.8, "nod": 4.0},
	{"t": 1.0, "drop": 0.93, "back": 0.16, "reach": 0.6, "stretch": 1.0, "lean": -22.0, "chest": 14.0, "arms": 1.0, "nod": 0.0},
]
# Seated breath: a slight chest rise and fall over the final sitting pose.
const BREATH := 2.0
# A stretched leg's hand rests this far from the hip toward the knee, the knee itself being out of reach.
const THIGH_REST := 0.45

## Adds the "rest" library to the player. False when the Body lacks the bones or an idle clip.
static func install(player: AnimationPlayer, target: Skeleton3D) -> bool:
	if player != null and player.has_animation_library(LIBRARY): return true
	var builder := new()
	if not builder.setup(player, target): return false
	var library := AnimationLibrary.new()
	for pose: String in POSES:
		var keys: Array = SIT_KEYS if pose == "knees" else STRETCH_KEYS
		var clips: Array = POSES[pose].map(func(clip: String) -> String: return clip.get_file())
		library.add_animation(clips[0], builder._make_clip(keys, SIT_LENGTH, false))
		library.add_animation(clips[1], builder._make_seated(keys))
		library.add_animation(clips[2], builder._make_clip(keys, SIT_LENGTH, true))
	player.add_animation_library(LIBRARY, library)
	return true


## Sit-down (or, reversed, stand-up) clip sampled from the keys with the IK solved per sample.
func _make_clip(keys: Array, length: float, reverse: bool) -> Animation:
	var times: Array[float] = []
	for step in SAMPLES + 1:
		times.append(float(step) / SAMPLES)
	var poses: Array[Dictionary] = []
	for time in times:
		poses.append(_pose(_key_at(keys, 1.0 - time if reverse else time)))
	return _bake(times.map(func(time: float) -> float: return time * length), poses, length, Animation.LOOP_NONE)


func _make_seated(keys: Array) -> Animation:
	var seated: Dictionary = keys[-1]
	var times: Array[float] = []
	var poses: Array[Dictionary] = []
	for step in 9:
		var phase := float(step) / 8.0
		var key := seated.duplicate()
		var rise := 0.5 * (1.0 - cos(TAU * phase))
		key.chest = seated.chest - BREATH * rise
		key.lean = seated.lean - BREATH * 0.5 * rise
		times.append(phase * SEATED_LENGTH)
		poses.append(_pose(key))
	return _bake(times, poses, SEATED_LENGTH, Animation.LOOP_LINEAR)


## Keys blended with smoothstep easing at a normalized time.
func _key_at(keys: Array, time: float) -> Dictionary:
	var t := time * (keys[-1].t as float)
	for index in range(1, keys.size()):
		var a: Dictionary = keys[index - 1]
		var b: Dictionary = keys[index]
		if t <= b.t or index == keys.size() - 1:
			var w := smoothstep(0.0, 1.0, clampf((t - a.t) / maxf(b.t - a.t, 0.0001), 0.0, 1.0))
			var key := {}
			for field: String in a:
				key[field] = lerpf(a[field], b[field], w)
			return key
	return keys[-1]


func _pose(key: Dictionary) -> Dictionary:
	var pose := _idle.duplicate()
	# Pelvis: sink, shift back and tip back.
	var hips: Transform3D = _idle_global[HIPS]
	hips.origin += Vector3(0, -key.drop, -key.back) * leg_length
	hips.basis = Basis(Vector3.RIGHT, deg_to_rad(key.lean)) * hips.basis
	_set_global(pose, HIPS, hips)
	# The spine leans forward over the pelvis; the chest takes the rest of the bend.
	for spec in [[SPINE[0], 0.4], [SPINE[2], 0.6]]:
		var spine := _global(pose, skeleton.find_bone(spec[0]))
		spine.basis = Basis(Vector3.RIGHT, deg_to_rad(key.chest * spec[1])) * spine.basis
		_set_global(pose, spec[0], spine)
	# Head stays level with the idle's, tipped by nod.
	var head := _global(pose, skeleton.find_bone(HEAD))
	head.basis = Basis(Vector3.RIGHT, deg_to_rad(key.nod)) * (_idle_global[HEAD] as Transform3D).basis
	_set_global(pose, HEAD, head)
	# Feet stay flat on the ground and slide forward; knees rise forward and a little outward.
	# A stretched left leg lies straight out along the ground instead, kneecap and toes up.
	var knees := {}
	var hips_joints := {}
	for side: String in LEG_CHAINS:
		var chain: Array = LEG_CHAINS[side]
		var foot: Vector3 = (_idle_global[chain[2]] as Transform3D).origin + Vector3(0, 0, key.reach) * leg_length
		var outward := 1.0 if side == "L" else -1.0
		var stretch: float = key.stretch if side == "L" else 0.0
		var hip := _global(pose, skeleton.find_bone(chain[0])).origin
		hips_joints[side] = hip
		foot.z = lerpf(foot.z, hip.z + 1.2 * leg_length, stretch)
		foot.x += 0.06 * outward * leg_length * stretch
		knees[side] = _two_bone(pose, chain, foot, Vector3(0.25 * outward, 0.6, 1.0).lerp(Vector3(0.15 * outward, 1.0, 0.0), stretch))
		# A planted foot stays flat; a stretched one follows its shin.
		var planted := _global(pose, skeleton.find_bone(chain[2]))
		var flat := (_idle_global[chain[2]] as Transform3D).basis
		planted.basis = Basis(planted.basis.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), 1.0 - stretch)).scaled(flat.get_scale())
		_set_global(pose, chain[2], planted)
	# Wrists over the knees, elbows out to the sides, blended in from the idle arms.
	var weight: float = key.arms
	if weight > 0.0:
		var armed := pose.duplicate()
		for side: String in ARM_CHAINS:
			var outward := 1.0 if side == "L" else -1.0
			var wrist: Vector3 = knees[side] + Vector3(-0.02 * outward, 0.06, 0.03) * leg_length
			if side == "L" and key.stretch > 0.0:
				var thigh: Vector3 = (hips_joints.L as Vector3).lerp(knees.L, THIGH_REST) + Vector3(0, 0.1, 0) * leg_length
				wrist = wrist.lerp(thigh, key.stretch)
			_two_bone(armed, ARM_CHAINS[side], wrist, Vector3(outward, -0.6, -0.2))
		for side: String in ARM_CHAINS:
			for bone: String in ARM_CHAINS[side]:
				var a: Transform3D = pose[bone]
				var b: Transform3D = armed[bone]
				pose[bone] = Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), weight)).scaled(a.basis.get_scale()), a.origin)
	return pose
