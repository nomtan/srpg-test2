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
## The same builder makes the other loadouts' stances and gaits (DAGGER, GREATSWORD; see install_loadout): a hold per hand
## ("R"/"L") that grips a blade, or a free arm ("free") that hangs in the stance and swings with the stride.

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

# Dual daggers: a low, forward-leaning crouch, both blades held up in front, the right one ahead and the left one back
# by the chest, tips toward the foe; it breathes quicker and bobs a little. The walk carries them low and forward,
# the run trails them back along the arms (as the sword's run).
const DAGGER := {
	"library": "dagger_gait",
	"stance": {
		"length": 2.6, "hip_yaw": -16.0, "chest_yaw": -24.0, "head_yaw": 0.3, "nod": 4.0, "lean": 12.0, "drop": 0.1,
		"lead": Vector3(.07,0,.15), "rear": Vector3(-.09,0,-.12), "lead_turn": -10.0, "rear_turn": -38.0,
		"breath": 1.4, "bob": 0.009, "shift": 0.016,
		"R": {"wrist": Vector3(-.12,-.6,.55), "swing": Vector3(0,.02,.03), "elbow": Vector3(-.9,-.4,-.3),
			"aim": Vector3(-.12,.3,1), "aim_swing": Vector3(0,.05,0)},
		"L": {"wrist": Vector3(.14,-.52,.36), "swing": Vector3(0,.02,0), "elbow": Vector3(.9,-.4,-.3),
			"aim": Vector3(.3,.6,.75)},
	},
	"walk": {"turn": -6.0,
		"R": {"wrist": Vector3(-.2,-.82,.18), "swing": Vector3(0,.06,.24), "elbow": Vector3(-.6,-.2,-1),
			"aim": Vector3(-.3,-.35,.85), "aim_swing": Vector3(0,.15,.1)},
		"L": {"wrist": Vector3(.2,-.82,.18), "swing": Vector3(0,.06,.24), "elbow": Vector3(.6,-.2,-1),
			"aim": Vector3(.3,-.35,.85), "aim_swing": Vector3(0,.15,.1)}},
	"run": {"turn": -4.0,
		"R": {"wrist": Vector3(-.2,-.72,-.08), "swing": Vector3(0,.2,.42), "elbow": Vector3(-.5,-.2,-1),
			"aim": Vector3(-.3,-.45,-1), "aim_swing": Vector3(0,.25,.15)},
		"L": {"wrist": Vector3(.2,-.72,-.08), "swing": Vector3(0,.2,.42), "elbow": Vector3(.5,-.2,-1),
			"aim": Vector3(.3,-.45,-1), "aim_swing": Vector3(0,.25,.15)}},
}
# Greatsword and greataxe: the weapon laid on the right shoulder, the hand raised beside the head with the elbow out
# (as SwordCombat.GS_READY). The stance is half-turned and sunk under the weight, the free left arm bent a little,
# breathing slow and deep; the walk and run keep it shouldered while the left arm swings with the stride.
const GREAT_CARRY := {"wrist": Vector3(-.12,.02,.2), "swing": Vector3(0,.015,0), "elbow": Vector3(-1,-.25,.15),
	"aim": Vector3(.45,.3,-.85), "aim_swing": Vector3(0,.02,0)}
const GREATSWORD := {
	"library": "greatsword_gait",
	"stance": {
		"length": 4.0, "hip_yaw": -28.0, "chest_yaw": -24.0, "head_yaw": 0.2, "nod": 3.0, "lean": 7.0, "drop": 0.1,
		"lead": Vector3(.08,0,.15), "rear": Vector3(-.1,0,-.14), "lead_turn": -18.0, "rear_turn": -50.0,
		"breath": 2.0, "bob": 0.008, "shift": 0.012,
		"R": GREAT_CARRY,
		"L": {"free": true, "arm_out": 14.0, "arm_offset": 8.0, "elbow": 30.0},
	},
	"walk": {"turn": -12.0, "R": GREAT_CARRY, "L": {"free": true}},
	"run": {"turn": -10.0, "R": GREAT_CARRY, "L": {"free": true}},
}

# The weapons' frames in their hand bones' frames: the sword grip (X across the edges, Y to the tip) and the shield
# grip (X across, Y up, Z out of the face).
var _sword_grip := Basis.IDENTITY
var _shield_grip := Basis.IDENTITY
# install_loadout: per hand ("R"/"L"), maps the hand turned to (fingers, blade, their cross) back to the bone's local
# axes; a hand without one holds the shield (sword and shield) or swings free.
var _blade_frames: Dictionary = {}
var _stance_spec: Dictionary = STANCE
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


## Adds a loadout's stance and gait library (spec: DAGGER or GREATSWORD) and returns the stance's first pose as local
## bone transforms; {} when the Body lacks the bones or an idle. grips: per hand ("R"/"L"), the weapon's frame in its
## hand bone's frame (Y toward the tip). The clips are "<library>/idle", "/walk" and "/run".
static func install_loadout(player: AnimationPlayer, target: Skeleton3D, spec: Dictionary, grips: Dictionary) -> Dictionary:
	var builder := new()
	if not builder.setup(player, target): return {}
	for side: String in grips:
		# Fingers as close to the bone's own finger axis (local Y) as the blade allows.
		var blade := (grips[side] as Basis).y.normalized()
		var fingers := (Vector3.UP - blade * blade.dot(Vector3.UP)).normalized()
		builder._blade_frames[side] = Basis(fingers, blade, fingers.cross(blade)).inverse()
	builder._stance_spec = spec.stance
	var chain: Array = ARM_CHAINS.R
	var points: Array = chain.map(func(bone: String) -> Vector3: return (builder._idle_global[bone] as Transform3D).origin)
	builder.arm_length = (points[1] - points[0]).length() + (points[2] - points[1]).length()
	var library := AnimationLibrary.new()
	library.add_animation("idle", builder._make_stance())
	library.add_animation("walk", builder._make_cycle(WALK_STYLE.merged(spec.walk, true)))
	library.add_animation("run", builder._make_cycle(RUN_STYLE.merged(spec.run, true)))
	if player.has_animation_library(spec.library): player.remove_animation_library(spec.library)
	player.add_animation_library(spec.library, library)
	return builder._stance(0.0)


func _make_stance() -> Animation:
	var times: Array[float] = []
	var poses: Array[Dictionary] = []
	for step in STANCE_SAMPLES + 1:
		var phase := float(step) / STANCE_SAMPLES
		times.append(phase * _stance_spec.length)
		poses.append(_stance(fposmod(phase, 1.0)))
	return _bake(times, poses, _stance_spec.length, Animation.LOOP_LINEAR)


func _stance(phase: float) -> Dictionary:
	var spec := _stance_spec
	var pose := _idle.duplicate()
	var breath := sin(TAU * phase)
	# The weight drifts and the tip sways out of step with the breath, so the loop doesn't read as one pulse.
	var shift := sin(TAU * phase + 1.3)
	var drift := sin(TAU * phase + 2.4)
	var hips: Transform3D = _idle_global[HIPS]
	hips.origin += Vector3(spec.shift * shift, -spec.drop + spec.bob * breath, 0) * leg_length
	hips.basis = _turn(spec.lean * 0.4, spec.hip_yaw, 0.0) * hips.basis
	_set_global(pose, HIPS, hips)
	for index in SPINE.size():
		var share := float(index + 1) / SPINE.size()
		_orient(pose, SPINE[index], _turn(spec.lean * (0.4 + 0.6 * share) - spec.breath * breath * share,
			lerpf(spec.hip_yaw, spec.chest_yaw, share), 0.0))
	_orient(pose, NECK, _turn(spec.lean * 0.5, spec.chest_yaw * 0.6, 0.0))
	_orient(pose, HEAD, _turn(spec.nod, spec.chest_yaw * spec.head_yaw, 0.0))
	for side: String in LEG_CHAINS:
		var chain: Array = LEG_CHAINS[side]
		var turn := deg_to_rad(spec.lead_turn if side == "L" else spec.rear_turn)
		var step: Vector3 = spec.lead if side == "L" else spec.rear
		var outward := 1.0 if side == "L" else -1.0
		var ankle: Vector3 = (_idle_global[chain[2]] as Transform3D).origin + step * leg_length
		_two_bone(pose, chain, ankle, Basis(Vector3.UP, turn) * Vector3(0.2 * outward, 0.0, 1.0))
		_orient(pose, chain[2], Basis(Vector3.UP, turn))
	var chest := _turn(spec.lean, spec.chest_yaw, 0.0)
	_hold(pose, "R", chest, _side_hold(spec, "R"), drift)
	_hold(pose, "L", chest, _side_hold(spec, "L"), breath)
	return pose


## The gait's arm swing, with the weapon held instead of a free arm.
func _swing_arm(pose: Dictionary, style: Dictionary, side: String, swing: float, chest: Basis) -> void:
	var hold := _side_hold(style, side)
	if hold.get("free", false):
		# A free arm swings as in the bare-handed gait; the hold may override the style's arm angles.
		super._swing_arm(pose, style.merged(hold, true), side, swing, chest)
		return
	_hold(pose, side, chest, hold, swing)


## A style's hold for one hand: "R"/"L", or the sword and shield's "sword"/"shield"; a free arm without either.
static func _side_hold(style: Dictionary, side: String) -> Dictionary:
	return style.get(side, style.get("sword" if side == "R" else "shield", {"free": true}))


## Puts one hand where the hold says by arm IK and turns it so its weapon points along the hold's aim.
## A free hold hangs the arm as the walk does at the middle of its swing.
func _hold(pose: Dictionary, side: String, chest: Basis, hold: Dictionary, swing: float) -> void:
	if hold.get("free", false):
		super._swing_arm(pose, WALK_STYLE.merged(hold, true), side, 0.0, chest)
		return
	var chain: Array = ARM_CHAINS[side]
	var shoulder := _global(pose, skeleton.find_bone(chain[0])).origin
	var wrist: Vector3 = shoulder + chest * (hold.wrist + hold.get("swing", Vector3.ZERO) * swing) * arm_length
	var elbow := _two_bone(pose, chain, wrist, chest * (hold.elbow as Vector3))
	var aim: Vector3 = (hold.aim + hold.get("aim_swing", Vector3.ZERO) * swing).normalized()
	var hand := _global(pose, skeleton.find_bone(chain[2]))
	if _blade_frames.has(side):
		# Fingers along the forearm, square to the blade, as for the sword.
		var fingers := wrist - elbow
		fingers = (fingers - aim * aim.dot(fingers)).normalized()
		hand.basis = Basis(fingers, aim, fingers.cross(aim)) * (_blade_frames[side] as Basis)
	elif side == "R":
		# The fingers carry on along the forearm, turned square to the blade (as SwordCombat._hold).
		var fingers := wrist - elbow
		fingers = (fingers - aim * aim.dot(fingers)).normalized()
		hand.basis = Basis(fingers, aim, fingers.cross(aim)) * _sword_grip.inverse()
	else:
		# The shield stands upright, its face along the aim.
		var up := (Vector3.UP - aim * aim.dot(Vector3.UP)).normalized()
		hand.basis = Basis(up.cross(aim), up, aim) * _shield_grip.inverse()
	_set_global(pose, chain[2], hand)
