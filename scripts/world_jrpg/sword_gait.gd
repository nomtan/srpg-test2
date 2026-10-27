extends "res://scripts/world_jrpg/gait_cycle.gd"
## Sword-and-shield stance, walk and run for a humanoid_v1 Body, in place of the Body's idle and walk, whose hanging,
## swinging arms waved the sword stuck out of the fist about and flapped the shield at the hip.
## Stance (idle): half-turned with the shield shoulder leading, knees soft and the feet apart, left foot ahead; the shield
## carried before the chest and the sword low ahead on the right, tip toward the foe. It breathes: the chest rises and
## falls, the weight drifts between the feet and the sword tip sways a little.
## Walk and run keep GaitCycle's legs and pelvis, so the explorer's stride speeds still match, with the shoulders turned
## a little shield-first. The shield stays carried in front; the sword arm swings with the stride, the blade held low
## and forward in the walk and trailing back along the arm in the run.
## Both hands are placed by arm IK and turned so the weapons point where the style says (character space).

const ARMED_LIBRARY := "sword_gait"
const STANCE_CLIP := "sword_gait/idle"
const ARMED_WALK := "sword_gait/walk"
const ARMED_RUN := "sword_gait/run"
const STANCE_SAMPLES := 24
# Weapon holds: "wrist" offset from the shoulder in arm lengths, in the chest's (turning, leaning) frame, plus "swing"
# times the arm's swing (+1 fully forward, -1 back); "elbow" is the bend direction in the same frame. "aim" (plus
# "aim_swing" times the swing) is the blade's direction for the sword and the face's direction for the shield.
const WALK_SWORD := {"wrist": Vector3(-.2,-.84,.14), "swing": Vector3(0,.06,.26), "elbow": Vector3(-.6,-.2,-1),
	"aim": Vector3(-.65,-.5,.75), "aim_swing": Vector3(0,.15,.1)}
const WALK_SHIELD := {"wrist": Vector3(.04,-.8,.38), "swing": Vector3(0,.02,.06), "elbow": Vector3(1,-.5,-.2),
	"aim": Vector3(.65,0,1)}
const RUN_SWORD := {"wrist": Vector3(-.2,-.72,-.08), "swing": Vector3(0,.2,.42), "elbow": Vector3(-.5,-.2,-1),
	"aim": Vector3(-.3,-.45,-1), "aim_swing": Vector3(0,.25,.15)}
const RUN_SHIELD := {"wrist": Vector3(.02,-.66,.45), "swing": Vector3(0,.04,.08), "elbow": Vector3(1,-.6,-.2),
	"aim": Vector3(.55,-.1,1)}
const ARMED_WALK_STYLE := {"turn": -10.0, "sword": WALK_SWORD, "shield": WALK_SHIELD}
const ARMED_RUN_STYLE := {"turn": -8.0, "sword": RUN_SWORD, "shield": RUN_SHIELD}
# Stance. hip_yaw/chest_yaw: pelvis and shoulder turn (negative leads with the shield, left, side); head_yaw: the head's
# share of that turn, the rest counter-turned to face ahead; nod: head tipped down. drop: knee bend in leg lengths.
# lead/rear: left and right foot moved from the idle (leg lengths), toes turned by lead_turn/rear_turn.
# breath: chest lift in degrees; bob: hips' rise and fall with it; shift: weight drift sideways. The holds' "swing" is the
# sword tip's sway and the shield's rise with the breath.
const STANCE := {
	"length": 3.6, "hip_yaw": -22.0, "chest_yaw": -34.0, "head_yaw": 0.25, "nod": 5.0, "lean": 6.0, "drop": 0.07,
	"lead": Vector3(.06,0,.16), "rear": Vector3(-.08,0,-.14), "lead_turn": -14.0, "rear_turn": -48.0,
	"breath": 1.6, "bob": 0.006, "shift": 0.014,
	"sword": {"wrist": Vector3(-.26,-.72,.42), "swing": Vector3(0,.02,.03), "elbow": Vector3(-.8,-.3,-.6),
		"aim": Vector3(-.12,-.14,1), "aim_swing": Vector3(0,.04,0)},
	"shield": {"wrist": Vector3(-.04,-.72,.5), "swing": Vector3(0,.02,0), "elbow": Vector3(1,-.5,-.1),
		"aim": Vector3(.45,0,1)},
}

# The weapons' frames in their hand bones' frames: the sword grip (X across the edges, Y to the tip) and the shield
# grip (X across, Y up, Z out of the face).
var _sword_grip := Basis.IDENTITY
var _shield_grip := Basis.IDENTITY
# Shoulder to wrist in the idle pose.
var arm_length := 1.0


## Adds the "sword_gait" library (idle, walk, run) to the player and returns the stance's first pose as local bone
## transforms, for the attack clips to start and end in; {} when the Body lacks the bones or an idle.
static func install_armed(player: AnimationPlayer, target: Skeleton3D, sword_grip: Basis, shield_grip: Basis) -> Dictionary:
	var builder := new()
	if not builder.setup(player, target): return {}
	builder._sword_grip = sword_grip
	builder._shield_grip = shield_grip
	var chain: Array = ARM_CHAINS.R
	var points: Array = chain.map(func(bone: String) -> Vector3: return (builder._idle_global[bone] as Transform3D).origin)
	builder.arm_length = (points[1] - points[0]).length() + (points[2] - points[1]).length()
	var library := AnimationLibrary.new()
	library.add_animation("idle", builder._make_stance())
	library.add_animation("walk", builder._make_cycle(WALK_STYLE.merged(ARMED_WALK_STYLE, true)))
	library.add_animation("run", builder._make_cycle(RUN_STYLE.merged(ARMED_RUN_STYLE, true)))
	if player.has_animation_library(ARMED_LIBRARY): player.remove_animation_library(ARMED_LIBRARY)
	player.add_animation_library(ARMED_LIBRARY, library)
	return builder._stance(0.0)


func _make_stance() -> Animation:
	var times: Array[float] = []
	var poses: Array[Dictionary] = []
	for step in STANCE_SAMPLES + 1:
		var phase := float(step) / STANCE_SAMPLES
		times.append(phase * STANCE.length)
		poses.append(_stance(fposmod(phase, 1.0)))
	return _bake(times, poses, STANCE.length, Animation.LOOP_LINEAR)


func _stance(phase: float) -> Dictionary:
	var pose := _idle.duplicate()
	var breath := sin(TAU * phase)
	# The weight drifts and the tip sways out of step with the breath, so the loop doesn't read as one pulse.
	var shift := sin(TAU * phase + 1.3)
	var drift := sin(TAU * phase + 2.4)
	var hips: Transform3D = _idle_global[HIPS]
	hips.origin += Vector3(STANCE.shift * shift, -STANCE.drop + STANCE.bob * breath, 0) * leg_length
	hips.basis = _turn(STANCE.lean * 0.4, STANCE.hip_yaw, 0.0) * hips.basis
	_set_global(pose, HIPS, hips)
	for index in SPINE.size():
		var share := float(index + 1) / SPINE.size()
		_orient(pose, SPINE[index], _turn(STANCE.lean * (0.4 + 0.6 * share) - STANCE.breath * breath * share,
			lerpf(STANCE.hip_yaw, STANCE.chest_yaw, share), 0.0))
	_orient(pose, NECK, _turn(STANCE.lean * 0.5, STANCE.chest_yaw * 0.6, 0.0))
	_orient(pose, HEAD, _turn(STANCE.nod, STANCE.chest_yaw * STANCE.head_yaw, 0.0))
	for side: String in LEG_CHAINS:
		var chain: Array = LEG_CHAINS[side]
		var turn := deg_to_rad(STANCE.lead_turn if side == "L" else STANCE.rear_turn)
		var step: Vector3 = STANCE.lead if side == "L" else STANCE.rear
		var outward := 1.0 if side == "L" else -1.0
		var ankle: Vector3 = (_idle_global[chain[2]] as Transform3D).origin + step * leg_length
		_two_bone(pose, chain, ankle, Basis(Vector3.UP, turn) * Vector3(0.2 * outward, 0.0, 1.0))
		_orient(pose, chain[2], Basis(Vector3.UP, turn))
	var chest := _turn(STANCE.lean, STANCE.chest_yaw, 0.0)
	_hold(pose, "R", chest, STANCE.sword, drift)
	_hold(pose, "L", chest, STANCE.shield, breath)
	return pose


## The gait's arm swing, with the weapon held instead of a free arm.
func _swing_arm(pose: Dictionary, style: Dictionary, side: String, swing: float, chest: Basis) -> void:
	_hold(pose, side, chest, style.sword if side == "R" else style.shield, swing)


## Puts one hand where the hold says by arm IK and turns it so its weapon points along the hold's aim.
func _hold(pose: Dictionary, side: String, chest: Basis, hold: Dictionary, swing: float) -> void:
	var chain: Array = ARM_CHAINS[side]
	var shoulder := _global(pose, skeleton.find_bone(chain[0])).origin
	var wrist: Vector3 = shoulder + chest * (hold.wrist + hold.get("swing", Vector3.ZERO) * swing) * arm_length
	var elbow := _two_bone(pose, chain, wrist, chest * (hold.elbow as Vector3))
	var aim: Vector3 = (hold.aim + hold.get("aim_swing", Vector3.ZERO) * swing).normalized()
	var hand := _global(pose, skeleton.find_bone(chain[2]))
	if side == "R":
		# The fingers carry on along the forearm, turned square to the blade (as SwordCombat._hold).
		var fingers := wrist - elbow
		fingers = (fingers - aim * aim.dot(fingers)).normalized()
		hand.basis = Basis(fingers, aim, fingers.cross(aim)) * _sword_grip.inverse()
	else:
		# The shield stands upright, its face along the aim.
		var up := (Vector3.UP - aim * aim.dot(Vector3.UP)).normalized()
		hand.basis = Basis(up.cross(aim), up, aim) * _shield_grip.inverse()
	_set_global(pose, chain[2], hand)
