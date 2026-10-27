extends "res://scripts/world_jrpg/humanoid_pose.gd"
## Procedural walk and run cycles for an unarmed humanoid_v1 Body, in place of the imported walk
## (arms held stiffly out) and the run stretched from it (arms flung sideways).
## Built the way a person moves: the stance foot is planted and travels back under the hips at an even
## speed, rolling heel to toe; the swing foot clears the ground and reaches forward; the pelvis bobs,
## sways over the stance foot, turns with the swinging leg and dips on its side; the shoulders turn
## against the pelvis and each arm swings with the opposite leg; the head stays level and forward.
## Both clips start at the left heel strike, so a normalized phase is the same stride position in either
## and the explorer crossfades between them without swapping legs.

const LIBRARY := "gait"
const WALK := "gait/walk"
const RUN := "gait/run"
const SAMPLES := 32
# Lengths are in leg lengths (hips to ankle), angles in degrees.
# length: cycle seconds. duty: share of the cycle each foot is on the ground. reach/back: foot ahead of and
# behind the hips at heel strike and toe-off. lift: swing foot clearance, peaking earlier as lift_skew drops.
# width: share of the idle stance width kept, so the feet fall nearer the line of travel.
# heel_strike/toe_off: toes raised at contact and heel raised at push-off. drop/bob: hips sink and their
# two-beat bob (walk: highest over the stance foot; run: lowest there, highest in flight). sway: hips over the
# stance foot. pelvis_yaw/pelvis_roll: pelvis turn with the swinging leg and dip on its side. chest_yaw:
# shoulders' counter-turn. lean: forward lean of the torso. arm_out: arms' spread from the sides. The arm angles
# are measured from the leaning, turning chest, not from the vertical.
# arm_swing/arm_offset: upper-arm swing and its forward bias. elbow/elbow_swing: elbow bend and extra bend on the
# forward swing. cross: the forward hand's drift toward the body's midline. run: flight instead of double support.
const WALK_STYLE := {
	"length": 0.9, "duty": 0.6, "reach": 0.36, "back": 0.38, "lift": 0.16, "lift_skew": 0.85, "width": 0.5,
	"heel_strike": 12.0, "toe_off": 26.0, "drop": 0.08, "bob": 0.025, "sway": 0.025,
	"pelvis_yaw": 6.0, "pelvis_roll": 4.0, "chest_yaw": 7.0, "lean": 3.0,
	"arm_out": 14.0, "arm_swing": 27.0, "arm_offset": 4.0, "elbow": 14.0, "elbow_swing": 16.0, "cross": 0.05,
	"run": false,
}
const RUN_STYLE := {
	"length": 0.62, "duty": 0.36, "reach": 0.22, "back": 0.52, "lift": 0.5, "lift_skew": 0.6, "width": 0.35,
	"heel_strike": 5.0, "toe_off": 35.0, "drop": 0.13, "bob": 0.04, "sway": 0.01,
	"pelvis_yaw": 7.0, "pelvis_roll": 3.0, "chest_yaw": 11.0, "lean": 22.0,
	"arm_out": 8.0, "arm_swing": 32.0, "arm_offset": -4.0, "elbow": 90.0, "elbow_swing": 0.0, "cross": 0.35,
	"run": true,
}
const HAND_TIPS := {"L": "mixamorig_LeftHandMiddle1", "R": "mixamorig_RightHandMiddle1"}
# Toes stay flat on the ground while the heel rises, then follow the foot over this share of the swing.
const TOE_RELEASE := 0.2


## Adds the "gait" library (walk and run) to the player. False when the Body lacks the bones or an idle.
static func install(player: AnimationPlayer, target: Skeleton3D) -> bool:
	if player != null and player.has_animation_library(LIBRARY): return true
	var builder := new()
	if not builder.setup(player, target): return false
	var library := AnimationLibrary.new()
	library.add_animation("walk", builder._make_cycle(WALK_STYLE))
	library.add_animation("run", builder._make_cycle(RUN_STYLE))
	player.add_animation_library(LIBRARY, library)
	return true


func _make_cycle(style: Dictionary) -> Animation:
	var times: Array[float] = []
	var poses: Array[Dictionary] = []
	# The last sample repeats the first, closing the loop.
	for step in SAMPLES + 1:
		var phase := float(step) / SAMPLES
		times.append(phase * style.length)
		poses.append(_pose(style, fposmod(phase, 1.0)))
	return _bake(times, poses, style.length, Animation.LOOP_LINEAR)


func _pose(style: Dictionary, phase: float) -> Dictionary:
	var pose := _idle.duplicate()
	var duty: float = style.duty
	# Left foot right under the hips (mid-stance); the right foot is half a cycle behind.
	var stance_mid := duty * 0.5
	var bob := cos(2.0 * TAU * (phase - stance_mid))
	if style.run: bob = -bob
	var over_left := cos(TAU * (phase - stance_mid))
	# Pelvis: the swinging leg's hip leads (left forward at the left heel strike), the swing side dips.
	var pelvis_yaw: float = -style.pelvis_yaw * cos(TAU * phase)
	var pelvis_roll: float = style.pelvis_roll * over_left
	# "turn" (optional): a steady shoulder turn on top of the counter-turn, as SwordGait carries the shield side forward.
	var chest_yaw: float = style.chest_yaw * cos(TAU * phase) + style.get("turn", 0.0)
	var hips: Transform3D = _idle_global[HIPS]
	hips.origin += Vector3(style.sway * over_left, -style.drop + style.bob * bob, 0) * leg_length
	hips.basis = _turn(style.lean * 0.4, pelvis_yaw, pelvis_roll) * hips.basis
	_set_global(pose, HIPS, hips)
	# The spine unwinds from the pelvis turn into the shoulders' counter-turn and takes the rest of the lean.
	for index in SPINE.size():
		var share := float(index + 1) / SPINE.size()
		_orient(pose, SPINE[index], _turn(style.lean * (0.4 + 0.6 * share), lerpf(pelvis_yaw, chest_yaw, share), pelvis_roll * (1.0 - share)))
	_orient(pose, NECK, _turn(style.lean * 0.5, chest_yaw * 0.5, 0.0))
	# The head stays level and faces the way of travel.
	_orient(pose, HEAD, Basis.IDENTITY)
	for side: String in LEG_CHAINS:
		_place_leg(pose, style, side, fposmod(phase + (0.0 if side == "L" else 0.5), 1.0))
	for side: String in ARM_CHAINS:
		# Each arm swings forward with the opposite leg.
		_swing_arm(pose, style, side, cos(TAU * phase) * (1.0 if side == "R" else -1.0), _turn(style.lean, chest_yaw, 0.0))
	return pose


## One leg at its own phase p (0 = heel strike).
func _place_leg(pose: Dictionary, style: Dictionary, side: String, p: float) -> void:
	var chain: Array = LEG_CHAINS[side]
	var foot_idle: Transform3D = _idle_global[chain[2]]
	var toe_idle: Transform3D = _idle_global[TOES[side]]
	var duty: float = style.duty
	var travel := 0.0
	var lift := 0.0
	# Positive pitch raises the heel (pivoting on the ball), negative raises the toes (pivoting on the heel).
	var pitch := 0.0
	var toe_flat := 0.0
	if p < duty:
		# Planted: moves back at an even speed while the body passes over it.
		var s := p / duty
		travel = lerpf(style.reach, -style.back, s)
		pitch = -style.heel_strike * (1.0 - smoothstep(0.0, 0.2, s)) + style.toe_off * smoothstep(0.55, 1.0, s)
		toe_flat = 1.0
	else:
		var s := (p - duty) / (1.0 - duty)
		travel = lerpf(-style.back, style.reach, 0.5 - 0.5 * cos(PI * s))
		lift = style.lift * sin(PI * pow(s, style.lift_skew))
		pitch = style.toe_off * (1.0 - smoothstep(0.0, 0.45, s)) - style.heel_strike * smoothstep(0.6, 1.0, s)
		toe_flat = 1.0 - smoothstep(0.0, TOE_RELEASE, s)
	var narrow: float = (_idle_global[HIPS].origin.x - foot_idle.origin.x) * (1.0 - style.width)
	var shift := Vector3(narrow, lift * leg_length, travel * leg_length)
	var ankle := foot_idle.origin + shift
	var rotation := Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var pivot := toe_idle.origin + shift if pitch > 0.0 else Vector3(ankle.x, ankle.y - foot_idle.origin.y, ankle.z - 0.25 * (toe_idle.origin.z - foot_idle.origin.z))
	ankle = pivot + rotation * (ankle - pivot)
	var outward := 1.0 if side == "L" else -1.0
	# Knees track over the toes, which point a little outward.
	_two_bone(pose, chain, ankle, Vector3(0.15 * outward, 0.0, 1.0))
	_orient(pose, chain[2], rotation)
	_orient(pose, TOES[side], Basis(Vector3.RIGHT, deg_to_rad(pitch * (1.0 - toe_flat) if pitch > 0.0 else pitch)))


## One arm; swing is +1 fully forward and -1 fully back.
func _swing_arm(pose: Dictionary, style: Dictionary, side: String, swing: float, chest: Basis) -> void:
	var chain: Array = ARM_CHAINS[side]
	var outward := 1.0 if side == "L" else -1.0
	var spread := deg_to_rad(style.arm_out)
	var hang := Vector3(outward * sin(spread), -cos(spread), 0.0)
	var forward := maxf(swing, 0.0)
	var upper_angle: float = style.arm_offset + style.arm_swing * swing
	var elbow: float = style.elbow + style.elbow_swing * forward
	# Turning about -X swings a hanging arm forward.
	var upper := chest * Basis(Vector3.RIGHT, -deg_to_rad(upper_angle)) * hang
	var fore := chest * (Basis(Vector3.RIGHT, -deg_to_rad(upper_angle + elbow)) * hang + Vector3(-outward * style.cross * forward, 0, 0))
	# A straight wrist, the hand in line with the forearm. humanoid_v1 is left/right symmetric, so both
	# arms aim the same way and come out as mirror images.
	var directions: Array[Vector3] = [upper, fore, fore]
	var bones: Array = chain + [HAND_TIPS[side]]
	for index in directions.size():
		_aim(pose, bones[index], bones[index + 1], directions[index])


## Lean (forward pitch), yaw and roll in degrees as a skeleton-space rotation.
static func _turn(lean: float, yaw: float, roll: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.BACK, deg_to_rad(roll)) * Basis(Vector3.RIGHT, deg_to_rad(lean))
