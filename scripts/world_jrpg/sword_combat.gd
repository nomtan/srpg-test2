extends RefCounted
## Sword equipment and authored full-body clips for the Tripo rigs (Rigify or Mixamo names).
## The imported character and sword resources are never modified.
const SWORD = preload("res://assets/weapons/onehand_sword/001/001.glb")
const SlashFx = preload("res://scripts/world_jrpg/sword_slash_fx.gd")
const SLASH := "sword/slash"
const OVERHEAD := "sword/overhead"
# The source stands tip-down along +Y: tip at y=0, guard near y=0.75, pommel near y=0.98.
const GRIP := Vector3(0.0, 0.855, 0.0)
const SWORD_SCALE := 0.6
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
const OVERHEAD_KEYS := [
	{"t": 0.0},
	{"t": 0.03, "yaw": -12.0, "pitch": 8.0, "hip_yaw": -6.0, "hip": Vector3(0,-.14,-.02),
		"arm": [Vector3(-.5,-.3,.5), Vector3(-.1,-.2,.9)], "blade": Vector3(-.3,-.2,1)},
	{"t": 0.08, "yaw": -14.0, "pitch": -16.0, "hip_yaw": -8.0, "hip": Vector3(0,.02,-.04), "back": Vector3(0,0,-.04),
		"arm": [Vector3(-.3,.95,-.05), Vector3(.1,.8,-.55)], "blade": Vector3(0,.15,-1),
		"off": [Vector3(.3,.95,.05), Vector3(-.15,.8,-.45)]},
	{"t": 0.11, "yaw": -10.0, "pitch": -22.0, "hip_yaw": -6.0, "hip": Vector3(0,.05,-.02), "back": Vector3(0,.04,-.06), "step": Vector3(0,.06,.04),
		"arm": [Vector3(-.3,.95,-.15), Vector3(.12,.7,-.7)], "blade": Vector3(0,-.25,-1),
		"off": [Vector3(.3,.95,-.1), Vector3(-.15,.7,-.65)]},
	{"t": 0.13, "yaw": -6.0, "pitch": -8.0, "hip_yaw": -3.0, "hip": Vector3(-.01,-.02,.06), "step": Vector3(-.02,.04,.18), "back": Vector3(0,0,-.08),
		"arm": [Vector3(-.3,.95,.2), Vector3(.12,.85,.3)], "blade": Vector3(0,.95,-.3),
		"off": [Vector3(.3,.95,.2), Vector3(-.15,.85,.3)]},
	{"t": 0.15, "yaw": -2.0, "pitch": 4.0, "hip_yaw": 0.0, "hip": Vector3(-.02,-.08,.14), "step": Vector3(-.04,.02,.32), "back": Vector3(0,0,-.12),
		"arm": [Vector3(-.3,.55,.8), Vector3(.12,.45,1)], "blade": Vector3(0,1,.35),
		"off": [Vector3(.3,.5,.8), Vector3(-.15,.45,1)]},
	{"t": 0.18, "yaw": 6.0, "pitch": 24.0, "hip_yaw": 4.0, "hip": Vector3(-.03,-.26,.24), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.35,1), Vector3(.1,-.45,1)], "blade": Vector3(0,-.9,.55),
		"off": [Vector3(.25,-.35,1), Vector3(-.12,-.45,1)]},
	{"t": 0.31, "yaw": 8.0, "pitch": 22.0, "hip_yaw": 5.0, "hip": Vector3(-.03,-.25,.23), "step": Vector3(-.06,0,.46), "back": Vector3(0,0,-.2),
		"arm": [Vector3(-.25,-.4,1), Vector3(.1,-.5,1)], "blade": Vector3(.05,-.95,.5),
		"off": [Vector3(.25,-.4,1), Vector3(-.12,-.5,1)]},
	{"t": 0.45, "yaw": 5.0, "pitch": 8.0, "hip_yaw": 3.0, "hip": Vector3(-.02,-.11,.11), "step": Vector3(-.03,0,.22), "back": Vector3(0,0,-.1),
		"arm": [Vector3(-.55,-.6,.3), Vector3(-.1,-.6,.55)], "blade": Vector3(.12,-.1,1)},
	{"t": 0.63},
]
# Blade trail window and impact moment (seconds) for each clip, used by the slash effect.
const FX := {SLASH: {"trail": Vector2(0.06, 0.26), "impact": 0.13}, OVERHEAD: {"trail": Vector2(0.10, 0.23), "impact": 0.18}}

var skeleton: Skeleton3D
var socket: BoneAttachment3D
var grip: Node3D
var rig: Dictionary
var legs: Dictionary
var leg_length := 1.0
var _idle: Dictionary = {}
var _idle_global: Dictionary = {}

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
	_attach_sword()
	var fx := SlashFx.new()
	fx.name = "SwordSlashFx"
	fx.setup(grip, player, FX)
	model.add_child(fx)
	var library := AnimationLibrary.new()
	var path := player.get_node(player.root_node).get_path_to(skeleton)
	library.add_animation("slash", _make_attack(path, false))
	library.add_animation("overhead", _make_attack(path, true))
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

func _make_attack(path: NodePath, overhead: bool) -> Animation:
	var animation := Animation.new()
	animation.resource_name = "上段斬り" if overhead else "横薙ぎ"
	var keys: Array = OVERHEAD_KEYS if overhead else SLASH_KEYS
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
	var spine := _global(pose, skeleton.find_bone(rig["spine"]))
	spine.basis = Basis.from_euler(Vector3(deg_to_rad(key.pitch), deg_to_rad(key.yaw), 0)) * spine.basis
	_set_global(pose, rig["spine"], spine)
	# Counter-rotate the head so the eyes stay on the target while the body turns.
	var head := _global(pose, skeleton.find_bone(rig["head"]))
	head.basis = Basis(Vector3.UP, deg_to_rad(-(key.yaw + hip_yaw) * .7)) * head.basis
	_set_global(pose, rig["head"], head)
	_aim_arm(pose, "R", key.arm[0], key.arm[1])
	var off: Array = key.get("off", [Vector3(.65,-.55,.25), Vector3(-.2,.3,.8)])
	_aim_arm(pose, "L", off[0], off[1])
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
