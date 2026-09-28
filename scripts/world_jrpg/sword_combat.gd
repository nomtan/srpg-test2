extends RefCounted
## Hand equipment and authored full-body clips for the Tripo rigs (Rigify or Mixamo names).
## The imported character and equipment resources are never modified.
const SWORD = preload("res://assets/weapons/onehand_sword/001/model.glb")
const SHIELD = preload("res://assets/weapons/shield/001/model.glb")
const STAFF = preload("res://assets/weapons/staff/001/model.glb")
const GREATSWORD = preload("res://assets/weapons/gread_sword/001/model.glb")
const SlashFx = preload("res://scripts/world_jrpg/sword_slash_fx.gd")
const TwoHandGrip = preload("res://scripts/world_jrpg/greatsword_grip.gd")
const SLASH := "sword/slash"
const OVERHEAD := "sword/overhead"
const GUARD := "sword/guard"
const GS_SWEEP := "greatsword/sweep"
const GS_SMASH := "greatsword/smash"
const GS_GUARD := "greatsword/guard"
# Equipment per character; anyone not listed carries the one-handed sword and shield.
const LOADOUTS := {"charcter001": "greatsword", "charcter003": "staff"}
# The sword stands tip-down along +Y; its handle is just above the guard.
const GRIP := Vector3(0.0, 0.9, 0.0)
const SWORD_SCALE := 0.6
const STAFF_SCALE := 1.1
const STAFF_GRIP := Vector3(0, 0.22, 0)
const SHIELD_SCALE := 0.62 * 1.3 * 1.2 * 0.78
const SHIELD_GRIP := Vector3(0.0, 0.56, 0.0)
const SHIELD_WRIST_CLEARANCE := 0.08
# Idle shield face: out to the left side and turned a little forward, standing nearly upright.
const SHIELD_FACE := Vector3(1.0, 0.0, 0.55)
const READY_BLADE := Vector3(-0.55, 0.24, 1.0)
# Rig-neutral roles mapped to each supported skeleton's bone names.
const RIGS := [
	{"spine": "spine", "head": "head", "upper_arm.R": "upper_arm.R", "forearm.R": "forearm.R", "hand.R": "hand.R",
		"upper_arm.L": "upper_arm.L", "forearm.L": "forearm.L", "hand.L": "hand.L", "palm": 0.02},
	{"spine": "mixamorig_Spine", "head": "head", "upper_arm.R": "mixamorig_RightArm", "forearm.R": "mixamorig_RightForeArm",
		"hand.R": "mixamorig_RightHand", "upper_arm.L": "mixamorig_LeftArm", "forearm.L": "mixamorig_LeftForeArm",
		"hand.L": "mixamorig_LeftHand", "palm": 0.04},
]
# Optional lower body; without it the clips still play as upper-body swings.
const LEGS := [
	{"hips": "spine", "thigh.R": "thigh.R", "shin.R": "shin.R", "foot.R": "foot.R",
		"thigh.L": "thigh.L", "shin.L": "shin.L", "foot.L": "foot.L"},
	{"hips": "mixamorig_Hips", "thigh.R": "mixamorig_RightUpLeg", "shin.R": "mixamorig_RightLeg", "foot.R": "mixamorig_RightFoot",
		"thigh.L": "mixamorig_LeftUpLeg", "shin.L": "mixamorig_LeftLeg", "foot.L": "mixamorig_LeftFoot"},
]
# Character space: +Z forward, -X is the sword (right) side. Angles in degrees, offsets in leg lengths.
# yaw/pitch: torso twist and lean. hip_yaw/hip: pelvis turn and shift. step/back: right/left foot plant.
# arm/off: right/left upper-arm and forearm directions. blade: sword direction. Keys without blade are idle.
const SLASH_KEYS := [
	{"t": 0.0},
	{"t": 0.04, "yaw": -38.0, "pitch": -5.0, "hip_yaw": -22.0, "hip": Vector3(.02,-.12,-.04), "back": Vector3(0,0,-.06),
		"arm": [Vector3(-.85,.45,-.25), Vector3(-.4,.8,-.45)], "blade": Vector3(-.6,.7,-.7),
		"off": [Vector3(.35,-.35,.9), Vector3(.1,.1,1)]},
	{"t": 0.07, "yaw": -50.0, "pitch": -3.0, "hip_yaw": -28.0, "hip": Vector3(.03,-.16,-.05), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.8,.55,-.35), Vector3(-.3,.85,-.6)], "blade": Vector3(-.45,.75,-.85),
		"off": [Vector3(.3,-.3,1), Vector3(.05,.15,1)]},
	{"t": 0.10, "yaw": -18.0, "pitch": 5.0, "hip_yaw": -8.0, "hip": Vector3(-.02,-.2,.12), "step": Vector3(-.08,0,.32), "back": Vector3(0,0,-.16),
		"arm": [Vector3(-.75,.25,.6), Vector3(-.4,.25,1)], "blade": Vector3(-.8,.4,.6),
		"off": [Vector3(.6,-.4,.4), Vector3(.3,-.2,.7)]},
	{"t": 0.13, "yaw": 30.0, "pitch": 12.0, "hip_yaw": 12.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"arm": [Vector3(-.1,-.15,1), Vector3(.6,-.1,.8)], "blade": Vector3(.9,-.25,.5),
		"off": [Vector3(.9,-.35,-.3), Vector3(.5,-.4,-.6)]},
	{"t": 0.18, "yaw": 55.0, "pitch": 14.0, "hip_yaw": 20.0, "hip": Vector3(-.03,-.28,.26), "step": Vector3(-.1,0,.55), "back": Vector3(0,0,-.22),
		"arm": [Vector3(.35,-.3,.85), Vector3(1,-.25,.05)], "blade": Vector3(.75,-.5,-.45),
		"off": [Vector3(.8,-.45,-.45), Vector3(.35,-.6,-.7)]},
	{"t": 0.30, "yaw": 48.0, "pitch": 11.0, "hip_yaw": 18.0, "hip": Vector3(-.03,-.26,.25), "step": Vector3(-.1,0,.55), "back": Vector3(0,0,-.22),
		"arm": [Vector3(.2,-.5,.75), Vector3(.8,-.45,.2)], "blade": Vector3(.6,-.6,-.3),
		"off": [Vector3(.8,-.5,-.35), Vector3(.35,-.65,-.6)]},
	{"t": 0.42, "yaw": 22.0, "pitch": 5.0, "hip_yaw": 8.0, "hip": Vector3(-.02,-.12,.12), "step": Vector3(-.05,0,.27), "back": Vector3(0,0,-.11),
		"arm": [Vector3(-.25,-.6,.65), Vector3(.3,-.4,.8)], "blade": Vector3(.35,.05,1)},
	{"t": 0.60},
]
# The overhead cut is one-handed: the off hand lifts partway with the windup, then drops back to the side.
const OVERHEAD_OFF := [Vector3(.3,-.95,.05), Vector3(.2,-.85,.35)]
const OVERHEAD_KEYS := [
	{"t": 0.0},
	{"t": 0.03, "yaw": -12.0, "pitch": 8.0, "hip_yaw": -6.0, "hip": Vector3(0,-.14,-.02),
		"arm": [Vector3(-.5,-.3,.5), Vector3(-.1,-.2,.9)], "blade": Vector3(-.3,-.2,1), "off": OVERHEAD_OFF},
	{"t": 0.08, "yaw": -14.0, "pitch": -16.0, "hip_yaw": -8.0, "hip": Vector3(0,.02,-.04), "back": Vector3(0,0,-.04),
		"arm": [Vector3(-.3,.95,-.05), Vector3(.1,.8,-.55)], "blade": Vector3(0,.15,-1),
		"off": [Vector3(.5,.1,.3), Vector3(.25,.6,.45)]},
	{"t": 0.11, "yaw": -10.0, "pitch": -22.0, "hip_yaw": -6.0, "hip": Vector3(0,.05,-.02), "back": Vector3(0,.04,-.06), "step": Vector3(0,.06,.04),
		"arm": [Vector3(-.3,.95,-.15), Vector3(.12,.7,-.7)], "blade": Vector3(0,-.25,-1),
		"off": [Vector3(.5,.25,.2), Vector3(.2,.75,.35)]},
	{"t": 0.13, "yaw": -6.0, "pitch": -8.0, "hip_yaw": -3.0, "hip": Vector3(-.01,-.02,.06), "step": Vector3(-.02,.04,.18), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.3,.95,.2), Vector3(.12,.85,.3)], "blade": Vector3(0,.95,-.3),
		"off": [Vector3(.5,.05,.4), Vector3(.25,.4,.6)]},
	{"t": 0.15, "yaw": -2.0, "pitch": 4.0, "hip_yaw": 0.0, "hip": Vector3(-.02,-.08,.14), "step": Vector3(-.04,.02,.32), "back": Vector3(0,0,-.12),
		"arm": [Vector3(-.3,.55,.8), Vector3(.12,.45,1)], "blade": Vector3(0,1,.35),
		"off": [Vector3(.45,-.35,.45), Vector3(.25,-.15,.8)]},
	{"t": 0.18, "yaw": 6.0, "pitch": 24.0, "hip_yaw": 4.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.35,1), Vector3(.1,-.45,1)], "blade": Vector3(0,-.9,.55),
		"off": [Vector3(.35,-.9,-.15), Vector3(.25,-.85,-.05)]},
	{"t": 0.31, "yaw": 8.0, "pitch": 22.0, "hip_yaw": 5.0, "hip": Vector3(-.03,-.25,.23), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.4,1), Vector3(.1,-.5,1)], "blade": Vector3(.05,-.95,.5),
		"off": [Vector3(.35,-.9,-.15), Vector3(.25,-.85,-.05)]},
	{"t": 0.45, "yaw": 5.0, "pitch": 8.0, "hip_yaw": 3.0, "hip": Vector3(-.02,-.11,.11), "step": Vector3(-.03,0,.22), "back": Vector3(0,0,-.1),
		"arm": [Vector3(-.55,-.6,.3), Vector3(-.1,-.6,.55)], "blade": Vector3(.12,-.1,1), "off": OVERHEAD_OFF},
	{"t": 0.63},
]
# Guard: left side forward, knees bent, shield raised square in front of the chest, sword held back low.
const GUARD_KEYS := [
	{"t": 0.0},
	{"t": 0.12, "yaw": -22.0, "pitch": 8.0, "hip_yaw": -12.0, "hip": Vector3(0,-.1,-.02), "step": Vector3(0,0,-.1), "back": Vector3(0,0,.12),
		"arm": [Vector3(-.55,-.75,-.25), Vector3(-.35,-.3,.9)], "blade": Vector3(-.35,.45,1),
		"off": [Vector3(.45,-.6,.65), Vector3(-.6,.2,.8)], "shield": Vector3(.15,.05,1)},
]
# Blade trail window and impact moment (seconds) for each clip, used by the slash effect.
const FX := {SLASH: {"trail": Vector2(0.06, 0.26), "impact": 0.13}, OVERHEAD: {"trail": Vector2(0.10, 0.23), "impact": 0.18}}

# Greatsword, held in both hands. The source stands tip-down along +Y with the handle between the guard and pommel.
const GS_SCALE := 1.0
const GS_GRIP := Vector3(0.0, 0.825, 0.0) # Right hand, just below the guard.
const GS_HAND_SPACING := 0.065 # Left hand sits this far toward the pommel.
const GS_FX_INNER := Vector3(0, 0.2, 0)
const GS_FX_OUTER := Vector3(0, 1.05, 0)
# Elbow bend directions for the two-handed arm IK (character space).
const GS_POLES := {"R": Vector3(-.7,-1,-.3), "L": Vector3(.7,-1,-.3)}
# Greatsword keys use the shared body keys, plus "grip": the right hand's handle point, offset from the
# shoulder midpoint in arm lengths (character space), and "blade": the sword direction. Both hands follow by IK.
# Ready stance: hands in front of the belly, tip raised forward. Clips start and end here.
const GS_READY := {"grip": Vector3(0,-.48,.52), "blade": Vector3(-.25,.45,.85)}
# Horizontal sweep: wind back to the right, swing across the front and follow through to the left.
const GS_SWEEP_KEYS := [
	{"t": 0.0, "grip": GS_READY.grip, "blade": GS_READY.blade},
	{"t": 0.18, "yaw": -42.0, "pitch": -4.0, "hip_yaw": -20.0, "hip": Vector3(.02,-.14,-.04), "back": Vector3(0,0,-.06),
		"grip": Vector3(-.4,-.5,.12), "blade": Vector3(-.75,.3,-.6)},
	{"t": 0.25, "yaw": -48.0, "pitch": -2.0, "hip_yaw": -24.0, "hip": Vector3(.03,-.17,-.05), "back": Vector3(0,0,-.08),
		"grip": Vector3(-.42,-.52,.08), "blade": Vector3(-.65,.25,-.72)},
	{"t": 0.30, "yaw": -12.0, "pitch": 6.0, "hip_yaw": -5.0, "hip": Vector3(-.02,-.2,.12), "step": Vector3(-.08,0,.3), "back": Vector3(0,0,-.16),
		"grip": Vector3(-.12,-.5,.6), "blade": Vector3(-.85,.05,.55)},
	{"t": 0.34, "yaw": 25.0, "pitch": 12.0, "hip_yaw": 12.0, "hip": Vector3(-.03,-.26,.22), "step": Vector3(-.1,0,.5), "back": Vector3(0,0,-.22),
		"grip": Vector3(.16,-.38,.48), "blade": Vector3(.45,-.05,.9)},
	{"t": 0.39, "yaw": 50.0, "pitch": 14.0, "hip_yaw": 20.0, "hip": Vector3(-.03,-.28,.24), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"grip": Vector3(.35,-.44,.08), "blade": Vector3(.85,-.1,-.5)},
	{"t": 0.54, "yaw": 45.0, "pitch": 11.0, "hip_yaw": 18.0, "hip": Vector3(-.03,-.26,.23), "step": Vector3(-.1,0,.52), "back": Vector3(0,0,-.22),
		"grip": Vector3(.32,-.49,.1), "blade": Vector3(.8,-.25,-.45)},
	{"t": 0.80, "grip": GS_READY.grip, "blade": GS_READY.blade},
]
# Heavy downward cut: raise the blade beside the head (the big head leaves no room overhead), then drive it down with a lunge.
const GS_SMASH_KEYS := [
	{"t": 0.0, "grip": GS_READY.grip, "blade": GS_READY.blade},
	{"t": 0.22, "yaw": -20.0, "pitch": -12.0, "hip_yaw": -10.0, "hip": Vector3(0,-.04,-.03), "back": Vector3(0,0,-.04),
		"grip": Vector3(-.35,.05,.25), "blade": Vector3(-.5,.75,-.45)},
	{"t": 0.30, "yaw": -22.0, "pitch": -15.0, "hip_yaw": -11.0, "hip": Vector3(0,-.02,-.04), "back": Vector3(0,.03,-.06), "step": Vector3(0,.05,.04),
		"grip": Vector3(-.35,.1,.2), "blade": Vector3(-.45,.7,-.55)},
	{"t": 0.35, "yaw": -8.0, "pitch": 2.0, "hip_yaw": -4.0, "hip": Vector3(-.02,-.1,.14), "step": Vector3(-.04,.02,.3), "back": Vector3(0,0,-.12),
		"grip": Vector3(-.1,-.05,.75), "blade": Vector3(-.1,.6,.8)},
	{"t": 0.39, "yaw": 4.0, "pitch": 24.0, "hip_yaw": 3.0, "hip": Vector3(-.03,-.28,.24), "step": Vector3(-.06,0,.48), "back": Vector3(0,0,-.22),
		"grip": Vector3(.01,-.43,.58), "blade": Vector3(-.05,-.6,.8)},
	{"t": 0.56, "yaw": 5.0, "pitch": 22.0, "hip_yaw": 4.0, "hip": Vector3(-.03,-.26,.23), "step": Vector3(-.06,0,.48), "back": Vector3(0,0,-.22),
		"grip": Vector3(.01,-.46,.56), "blade": Vector3(-.03,-.65,.76)},
	{"t": 0.85, "grip": GS_READY.grip, "blade": GS_READY.blade},
]
# Guard: turn the left shoulder back, crouch and hold the blade across the front, tip up to the right.
const GS_GUARD_KEYS := [
	{"t": 0.0, "grip": GS_READY.grip, "blade": GS_READY.blade},
	{"t": 0.14, "yaw": 15.0, "pitch": 6.0, "hip_yaw": 8.0, "hip": Vector3(0,-.12,-.02), "step": Vector3(0,0,.06), "back": Vector3(0,0,-.1),
		"grip": Vector3(.21,-.24,.54), "blade": Vector3(-.6,.75,.2)},
]
const GS_FX := {GS_SWEEP: {"trail": Vector2(0.24, 0.44), "impact": 0.34}, GS_SMASH: {"trail": Vector2(0.31, 0.45), "impact": 0.39}}

var skeleton: Skeleton3D
var socket: BoneAttachment3D
var grip: Node3D
var rig: Dictionary
var legs: Dictionary
var leg_length := 1.0
var _idle: Dictionary = {}
var _idle_global: Dictionary = {}
var has_shield := false
var two_handed := false
# Clips for the equipped weapon; the guard clip is empty when the loadout cannot guard.
var slash_clip := SLASH
var overhead_clip := OVERHEAD
var guard_clip := ""
# Skeleton-space shield orientation in the idle pose; the guard pose rotates the hand from it.
var _shield_rest := Basis.IDENTITY
# Right arm length to the palm; greatsword grip offsets are measured in it.
var arm_reach := 1.0
# Per hand: maps (fingers, blade) back to the hand bone's local axes for the two-handed grip.
var _hand_frame: Dictionary = {}

func install(model: Node3D, player: AnimationPlayer) -> bool:
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or player == null or not player.has_animation("idle"):
		return false
	rig = {}
	for candidate: Dictionary in RIGS:
		if candidate.keys().all(func(role: String) -> bool: return role == "palm" or skeleton.find_bone(candidate[role]) >= 0):
			rig = candidate
			break
	if rig.is_empty(): return false
	legs = {}
	for candidate: Dictionary in LEGS:
		if candidate.values().all(func(bone: String) -> bool: return skeleton.find_bone(bone) >= 0):
			legs = candidate
			break
	player.play("idle", 0)
	player.advance(0)
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		_idle[bone] = skeleton.get_bone_pose(index)
		_idle_global[bone] = skeleton.get_bone_global_pose(index)
	if not legs.is_empty():
		leg_length = maxf((_idle_global[legs.hips] as Transform3D).origin.y - (_idle_global[legs["foot.R"]] as Transform3D).origin.y, 0.01)
	var path := player.get_node(player.root_node).get_path_to(skeleton)
	var fx := SlashFx.new()
	fx.name = "SwordSlashFx"
	var library := AnimationLibrary.new()
	match LOADOUTS.get(model.get("character_id"), "sword_shield"):
		"greatsword":
			_attach_greatsword()
			fx.setup(grip, player, GS_FX, GS_FX_INNER, GS_FX_OUTER)
			library.add_animation("sweep", _make_clip(path, "大剣・横薙ぎ", GS_SWEEP_KEYS))
			library.add_animation("smash", _make_clip(path, "大剣・振り下ろし", GS_SMASH_KEYS))
			library.add_animation("guard", _make_clip(path, "大剣・防御", GS_GUARD_KEYS))
			player.add_animation_library("greatsword", library)
			slash_clip = GS_SWEEP
			overhead_clip = GS_SMASH
			guard_clip = GS_GUARD
			# Keeps both hands on the handle during every clip and holds the ready stance outside the greatsword clips.
			var holder: SkeletonModifier3D = TwoHandGrip.new()
			holder.name = "GreatswordTwoHandGrip"
			holder.setup(self, player, "greatsword/")
			skeleton.add_child(holder)
			model.add_child(fx)
			return true
		"staff":
			_attach_staff()
		_:
			_attach_sword()
			_attach_shield()
			has_shield = true
			guard_clip = GUARD
	fx.setup(grip, player, FX)
	model.add_child(fx)
	library.add_animation("slash", _make_clip(path, "横薙ぎ", SLASH_KEYS))
	library.add_animation("overhead", _make_clip(path, "上段斬り", OVERHEAD_KEYS))
	if has_shield:
		library.add_animation("guard", _make_clip(path, "防御", GUARD_KEYS))
	player.add_animation_library("sword", library)
	return true

func _attach_sword() -> void:
	socket = BoneAttachment3D.new()
	socket.name = "SwordHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "SwordGrip"
	# The hand bone begins at the wrist; move the grip to the palm center along it.
	grip.position = Vector3(0, rig["palm"], 0)
	var hand: Transform3D = _idle_global[rig["hand.R"]]
	grip.basis = hand.basis.inverse() * Basis(Quaternion(Vector3.UP, READY_BLADE.normalized()))
	socket.add_child(grip)
	var sword := SWORD.instantiate() as Node3D
	sword.name = "EquippedSword"
	# Flip the tip-down source blade to +Y about X (keeps the guard along X) and put its handle at the origin.
	sword.basis = Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * SWORD_SCALE)
	sword.position = -(sword.basis * GRIP)
	grip.add_child(sword)

func _attach_staff() -> void:
	socket = BoneAttachment3D.new()
	socket.name = "StaffHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "StaffGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	var hand: Transform3D = _idle_global[rig["hand.R"]]
	grip.basis = hand.basis.inverse()
	socket.add_child(grip)
	var staff := STAFF.instantiate() as Node3D
	staff.name = "EquippedStaff"
	staff.scale = Vector3.ONE * STAFF_SCALE
	staff.position = -STAFF_GRIP * STAFF_SCALE
	grip.add_child(staff)

func _attach_greatsword() -> void:
	two_handed = true
	var upper: Transform3D = _idle_global[rig["upper_arm.R"]]
	var forearm: Transform3D = _idle_global[rig["forearm.R"]]
	var wrist: Transform3D = _idle_global[rig["hand.R"]]
	arm_reach = (forearm.origin - upper.origin).length() + (wrist.origin - forearm.origin).length() + rig["palm"]
	# Each hand holds the handle across its palm: fingers perpendicular to the blade, thumb toward the tip.
	# The thumb side comes from the idle hand (mirrored for the left), so each rig keeps its natural roll.
	for side in ["R", "L"]:
		var hand: Basis = (_idle_global[rig["hand." + side]] as Transform3D).basis.orthonormalized()
		var thumb := READY_BLADE * (Vector3(-1, 1, 1) if side == "L" else Vector3.ONE)
		thumb = (thumb - hand.y * hand.y.dot(thumb)).normalized()
		var local_thumb := hand.inverse() * thumb
		_hand_frame[side] = Basis(Vector3.UP, local_thumb, Vector3.UP.cross(local_thumb)).inverse()
	socket = BoneAttachment3D.new()
	socket.name = "GreatswordHandSocket"
	socket.bone_name = rig["hand.R"]
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "GreatswordGrip"
	grip.position = Vector3(0, rig["palm"], 0)
	# Blade along the thumb axis, edges along the fingers.
	grip.basis = (_hand_frame["R"] as Basis).inverse()
	socket.add_child(grip)
	var sword := GREATSWORD.instantiate() as Node3D
	sword.name = "EquippedGreatsword"
	# Same flip as the one-handed sword: tip up along +Y, handle at the grip.
	sword.basis = Basis(Vector3.RIGHT, PI).scaled(Vector3.ONE * GS_SCALE)
	sword.position = -(sword.basis * GS_GRIP)
	grip.add_child(sword)

func _attach_shield() -> void:
	var shield_socket := BoneAttachment3D.new()
	shield_socket.name = "ShieldLeftWristSocket"
	shield_socket.bone_name = rig["hand.L"]
	skeleton.add_child(shield_socket)
	var shield_grip := Node3D.new()
	shield_grip.name = "ShieldGrip"
	var forearm: Transform3D = _idle_global[rig["forearm.L"]]
	var hand: Transform3D = _idle_global[rig["hand.L"]]
	# The hand bone starts at the wrist. Keep the shield mostly upright, leaning only slightly with the hanging forearm.
	var up := (Vector3.UP * 2.0 + (forearm.origin - hand.origin).normalized()).normalized()
	var face := (SHIELD_FACE - up * up.dot(SHIELD_FACE)).normalized()
	_shield_rest = Basis(up.cross(face), up, face)
	shield_grip.basis = hand.basis.inverse() * _shield_rest
	shield_socket.add_child(shield_grip)
	var shield := SHIELD.instantiate() as Node3D
	shield.name = "EquippedShield"
	shield.scale = Vector3.ONE * SHIELD_SCALE
	shield.position = Vector3(0, 0, SHIELD_WRIST_CLEARANCE) - SHIELD_GRIP * SHIELD_SCALE
	shield_grip.add_child(shield)

func _make_clip(path: NodePath, title: String, keys: Array) -> Animation:
	var animation := Animation.new()
	animation.resource_name = title
	animation.length = keys[-1].t
	animation.loop_mode = Animation.LOOP_NONE
	var tracks: Dictionary = {}
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, NodePath(str(path) + ":" + bone))
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, NodePath(str(path) + ":" + bone))
		tracks[bone] = [rotation_track, position_track]
	for key: Dictionary in keys:
		var pose := _pose(key)
		for bone: String in tracks:
			var transform: Transform3D = pose[bone]
			animation.rotation_track_insert_key(tracks[bone][0], key.t, transform.basis.get_rotation_quaternion())
			animation.position_track_insert_key(tracks[bone][1], key.t, transform.origin)
	return animation

func _pose(key: Dictionary) -> Dictionary:
	var pose := _idle.duplicate()
	if not key.has("blade"): return pose
	var hip_yaw: float = key.get("hip_yaw", 0.0)
	if not legs.is_empty():
		# Drop and shift the pelvis (in leg lengths), then keep the feet planted with leg IK.
		var hips: Transform3D = _idle_global[legs.hips]
		hips.origin += (key.get("hip", Vector3.ZERO) as Vector3) * leg_length
		hips.basis = Basis(Vector3.UP, deg_to_rad(hip_yaw)) * hips.basis
		_set_global(pose, legs.hips, hips)
		for side in ["R", "L"]:
			var step: Vector3 = key.get("step" if side == "R" else "back", Vector3.ZERO)
			_plant_leg(pose, side, (_idle_global[legs["foot." + side]] as Transform3D).origin + step * leg_length)
	else:
		hip_yaw = 0.0
	# Twist in character space so the result does not depend on each rig's local bone axes.
	var yaw: float = key.get("yaw", 0.0)
	var spine := _global(pose, skeleton.find_bone(rig["spine"]))
	spine.basis = Basis.from_euler(Vector3(deg_to_rad(key.get("pitch", 0.0)), deg_to_rad(yaw), 0)) * spine.basis
	_set_global(pose, rig["spine"], spine)
	# Counter-rotate the head so the eyes stay on the target while the body turns.
	var head := _global(pose, skeleton.find_bone(rig["head"]))
	head.basis = Basis(Vector3.UP, deg_to_rad(-(yaw + hip_yaw) * .7)) * head.basis
	_set_global(pose, rig["head"], head)
	if key.has("grip"):
		_grip_arms(pose, key.grip, key.blade)
		return pose
	_aim_arm(pose, "R", key.arm[0], key.arm[1])
	var off: Array = key.get("off", [Vector3(.65,-.55,.25), Vector3(-.2,.3,.8)])
	_aim_arm(pose, "L", off[0], off[1])
	if key.has("shield"):
		# Turn the off hand so the attached shield faces the given direction, upright.
		var shield_face: Vector3 = (key.shield as Vector3).normalized()
		var shield_up := (Vector3.UP - shield_face * shield_face.y).normalized()
		var off_hand := _global(pose, skeleton.find_bone(rig["hand.L"]))
		var idle_off_hand: Transform3D = _idle_global[rig["hand.L"]]
		off_hand.basis = Basis(shield_up.cross(shield_face), shield_up, shield_face) * _shield_rest.inverse() * idle_off_hand.basis
		_set_global(pose, rig["hand.L"], off_hand)
	var hand: Transform3D = _global(pose, skeleton.find_bone(rig["hand.R"]))
	var idle_hand: Transform3D = _idle_global[rig["hand.R"]]
	hand.basis = Basis(Quaternion(READY_BLADE.normalized(), (key.blade as Vector3).normalized())) * idle_hand.basis
	_set_global(pose, rig["hand.R"], hand)
	return pose

## Two-bone IK with the knee bending toward character forward.
func _plant_leg(pose: Dictionary, side: String, target: Vector3) -> void:
	var names: Array = [legs["thigh." + side], legs["shin." + side], legs["foot." + side]]
	var rest: Array = names.map(func(bone: String) -> Transform3D: return _idle_global[bone])
	var thigh := _global(pose, skeleton.find_bone(names[0]))
	var a: float = (rest[1].origin - rest[0].origin).length()
	var b: float = (rest[2].origin - rest[1].origin).length()
	var reach := target - thigh.origin
	var d := clampf(reach.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var direction := reach.normalized()
	var pole := (Vector3.BACK - direction * direction.z).normalized()
	var bend := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var knee := thigh.origin + (direction * bend + pole * sqrt(1.0 - bend * bend)) * a
	var foot := thigh.origin + direction * d
	for index in 2:
		var joint := _global(pose, skeleton.find_bone(names[index]))
		var from: Vector3 = (rest[index + 1].origin - rest[index].origin).normalized()
		var to := (knee - joint.origin) if index == 0 else (foot - joint.origin)
		joint.basis = Basis(Quaternion(from, to.normalized())) * rest[index].basis
		_set_global(pose, names[index], joint)
	# Feet stay flat on the ground regardless of how the legs bend.
	var planted := _global(pose, skeleton.find_bone(names[2]))
	planted.basis = rest[2].basis
	_set_global(pose, names[2], planted)

## Live two-handed hold, run by the skeleton modifier after the animation each frame.
## ready_weight blends the arms into the ready stance; the left hand always follows the right hand's handle.
func apply_grip(target: Skeleton3D, ready_weight: float) -> void:
	var pose: Dictionary = {}
	for index in target.get_bone_count():
		pose[target.get_bone_name(index)] = target.get_bone_pose(index)
	var arms: Array = ["upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "forearm.L", "hand.L"].map(func(role: String) -> String: return rig[role])
	if ready_weight > 0.0:
		var animated: Array = arms.map(func(bone: String) -> Transform3D: return pose[bone])
		_grip_arms(pose, GS_READY.grip, GS_READY.blade)
		for index in arms.size():
			pose[arms[index]] = (animated[index] as Transform3D).interpolate_with(pose[arms[index]], ready_weight)
	var hand := _global(pose, skeleton.find_bone(rig["hand.R"]))
	var blade := (hand.basis * (_hand_frame["R"] as Basis).inverse().y).normalized()
	_hold(pose, "L", hand * Vector3(0, rig["palm"], 0) - blade * GS_HAND_SPACING * GS_SCALE, blade)
	for bone: String in arms:
		target.set_bone_pose(target.find_bone(bone), pose[bone])

## Both hands on the handle: the right at the grip point (offset from the shoulders in arm lengths), the left below it.
func _grip_arms(pose: Dictionary, offset: Vector3, blade: Vector3) -> void:
	var shoulders := (_global(pose, skeleton.find_bone(rig["upper_arm.R"])).origin + _global(pose, skeleton.find_bone(rig["upper_arm.L"])).origin) * 0.5
	var point := shoulders + offset * arm_reach
	blade = blade.normalized()
	_hold(pose, "R", point, blade)
	_hold(pose, "L", point - blade * GS_HAND_SPACING * GS_SCALE, blade)

## Put the palm center of one hand on a handle point, fingers wrapping across the blade axis.
func _hold(pose: Dictionary, side: String, point: Vector3, blade: Vector3) -> void:
	var shoulder := _global(pose, skeleton.find_bone(rig["upper_arm." + side])).origin
	# The fingers continue the arm's line toward the handle, turned square to the blade.
	var fingers := point - shoulder
	fingers = (fingers - blade * blade.dot(fingers)).normalized()
	var hand_basis := Basis(fingers, blade, fingers.cross(blade)) * (_hand_frame[side] as Basis)
	_reach(pose, side, point - fingers * rig["palm"])
	var hand := _global(pose, skeleton.find_bone(rig["hand." + side]))
	hand.basis = hand_basis
	_set_global(pose, rig["hand." + side], hand)

## Two-bone arm IK to a wrist position, the elbow bending toward the side's pole.
func _reach(pose: Dictionary, side: String, wrist: Vector3) -> void:
	var names: Array = [rig["upper_arm." + side], rig["forearm." + side], rig["hand." + side]]
	var rest: Array = names.map(func(bone: String) -> Transform3D: return _idle_global[bone])
	var upper := _global(pose, skeleton.find_bone(names[0]))
	var a: float = (rest[1].origin - rest[0].origin).length()
	var b: float = (rest[2].origin - rest[1].origin).length()
	var reach := wrist - upper.origin
	var d := clampf(reach.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var direction := reach.normalized()
	var hint: Vector3 = GS_POLES[side]
	var pole := (hint - direction * direction.dot(hint)).normalized()
	var bend := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := upper.origin + (direction * bend + pole * sqrt(1.0 - bend * bend)) * a
	var joints := [elbow, upper.origin + direction * d]
	for index in 2:
		var joint := _global(pose, skeleton.find_bone(names[index]))
		var from: Vector3 = (rest[index + 1].origin - rest[index].origin).normalized()
		joint.basis = Basis(Quaternion(from, (joints[index] - joint.origin).normalized())) * rest[index].basis
		_set_global(pose, names[index], joint)

func _aim_arm(pose: Dictionary, side: String, upper: Vector3, fore: Vector3) -> void:
	for spec in [["upper_arm." + side, upper], ["forearm." + side, fore], ["hand." + side, fore]]:
		var bone: String = rig[spec[0]]
		var transform := _global(pose, skeleton.find_bone(bone))
		var reference: Transform3D = _idle_global[bone]
		transform.basis = Basis(Quaternion(reference.basis.y.normalized(), (spec[1] as Vector3).normalized())) * reference.basis
		_set_global(pose, bone, transform)

func _set_global(pose: Dictionary, bone: String, transform: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(skeleton.find_bone(bone))
	pose[bone] = _global(pose, parent).affine_inverse() * transform

func _global(pose: Dictionary, index: int) -> Transform3D:
	if index < 0: return Transform3D.IDENTITY
	return _global(pose, skeleton.get_bone_parent(index)) * (pose[skeleton.get_bone_name(index)] as Transform3D)
