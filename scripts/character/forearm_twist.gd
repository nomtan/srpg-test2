extends SkeletonModifier3D
## Keeps the wrists of a whole-character rig (build_rigged_character.py) from bending and wringing under
## SwordCombat's shared clips, which turn the hand bone freely. Runs after the animation and the other modifiers:
## 1. The sword hand: the shared clips turn the hand only to point the blade, so the hand often bends far
##    off the forearm. With the blade's direction kept exactly, the hand is turned about the blade to the
##    one roll that leaves it closest to the forearm's line (only the edges roll, the sword still points as
##    the clip says). Where the blade runs nearly along the forearm the wrist stops at MAX_BEND and the blade
##    gives way instead. In the armed stance, walk and run (GAIT_CLIPS) the hand instead keeps one wrist
##    angle, the stance's set straight and cocked up a little, so the sword rides with the arm's swing.
## 2. Each hand's turn about the forearm is spread over the forearm's twist bones: each twist bone turns by
##    its share of the hand's twist, so the wrist does not wring when a grip turns the hand.

const SIDES := ["Left", "Right"]
# Twist bone suffix: share of the hand's twist.
const SHARES := {"ForeArmTwist1": 1.0 / 3.0, "ForeArmTwist2": 2.0 / 3.0}
# SwordCombat's sword grip under the right hand's bone (the blade along its +Y, in the hand bone's frame).
const SWORD_GRIP := "SwordHandSocket/SwordGrip"
# The furthest the sword hand bends off the forearm's line; past it the blade turns with the hand instead.
const MAX_BEND := deg_to_rad(40.0)
# Armed stance, walk and run (SwordGait): the sword hand holds the stance's wrist through them, straight on the
# forearm and cocked GAIT_COCK toward the blade, so the sword moves with the arm's swing instead of turning on
# its own; GAIT_BLEND seconds to and from the attack clips.
const GAIT_CLIPS := ["sword_gait/idle", "sword_gait/walk", "sword_gait/run"]
const GAIT_COCK := deg_to_rad(10.0)
const GAIT_BLEND := 0.15
# Where the swing would point the tip lower or higher than GAIT_PITCH (radians above level, skeleton space), as at
# the back and front of the run's arm swing (into the ground, up past the face), the wrist cocks or drops as far as
# it must, within GAIT_COCK_RANGE.
const GAIT_PITCH := Vector2(deg_to_rad(-15.0), deg_to_rad(45.0))
const GAIT_COCK_RANGE := Vector2(deg_to_rad(-30.0), deg_to_rad(40.0))
const GAIT_COCK_STEP := deg_to_rad(2.5)
# The bone whose frame holds the gait's blade direction.
const CHEST := "mixamorig_Spine2"
# The stance's blade, held in the walk and run, crosses in front of the hips (the stance's shoulders are turned
# further, shield first): moving, it turns this far outward (about the chest's up; negative is the sword side),
# over GAIT_MOVE_BLEND seconds.
const GAIT_MOVE_YAW := deg_to_rad(-25.0)
const GAIT_MOVE_BLEND := 0.25
# Clips whose blade may hang far below the arm (the overhead's follow-through, whose shared keys drop the tip well
# under the forearm's line): the blade is lifted to within LOOSE_LIFT of that line and the grip loosens, the sword
# turning in the fist by up to LOOSE_PIVOT so the hand bends only LOOSE_BEND; LOOSE_BLEND seconds in and out.
const LOOSE_CLIPS := ["sword/overhead"]
const LOOSE_LIFT := deg_to_rad(0.0)
const LOOSE_PIVOT := deg_to_rad(45.0)
const LOOSE_BEND := deg_to_rad(10.0)
const LOOSE_BLEND := 0.1

var _chains: Array = []
var _grip: Node3D
var _grip_rest := Basis.IDENTITY
var _loose_weight := 0.0
var _sword_hand := -1
var _player: AnimationPlayer
var _gait_source: Animation
var _gait_aim := Vector3.ZERO
var _gait_weight := 0.0
var _move_weight := 0.0


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	_sword_hand = skeleton.find_bone("mixamorig_RightHand")
	for side: String in SIDES:
		var hand := skeleton.find_bone("mixamorig_%sHand" % side)
		if hand < 0: continue
		var twists: Array = []
		for suffix: String in SHARES:
			var bone := skeleton.find_bone("mixamorig_%s%s" % [side, suffix])
			if bone >= 0: twists.append([bone, SHARES[suffix]])
		if not twists.is_empty(): _chains.append([hand, twists])


## True when the skeleton has twist bones to drive.
func has_twist_bones() -> bool:
	return not _chains.is_empty()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	_straighten_sword_hand(skeleton)
	for chain: Array in _chains:
		var hand: int = chain[0]
		# The hand's turn about its own axis (local +Y, along the arm): the twist of a swing-twist split.
		var turn := skeleton.get_bone_rest(hand).basis.get_rotation_quaternion().inverse() * skeleton.get_bone_pose_rotation(hand)
		var angle := wrapf(2.0 * atan2(turn.y, turn.w), -PI, PI)
		for twist: Array in chain[1]:
			var rest := skeleton.get_bone_rest(twist[0])
			skeleton.set_bone_pose_rotation(twist[0], rest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, angle * twist[1]))
			skeleton.set_bone_pose_position(twist[0], rest.origin)


## Rolls the sword hand about the blade so it lines up with the forearm as far as the grip allows (see above).
## Works in the forearm's frame: the forearm runs toward the hand's position, the hand's pose is its turn.
func _straighten_sword_hand(skeleton: Skeleton3D) -> void:
	if _sword_hand < 0: return
	var grip := skeleton.get_node_or_null(SWORD_GRIP) as Node3D
	if grip == null or not grip.is_visible_in_tree(): return
	if grip != _grip:
		_grip = grip
		_grip_rest = grip.basis
	var blade_local := _grip_rest.y.normalized()
	var forearm := skeleton.get_bone_pose_position(_sword_hand).normalized()
	var turned: Variant = _rolled(skeleton.get_bone_pose_rotation(_sword_hand), blade_local, forearm)
	if turned == null: return
	# Where the blade runs almost along the forearm no roll is enough: the wrist stops at MAX_BEND and the blade gives.
	if _bend(turned, forearm) > MAX_BEND:
		turned = _bent(turned, forearm, MAX_BEND, blade_local)
	# The overhead's follow-through: the blade lifted toward the arm's line and the grip loosened (see LOOSE_CLIPS).
	var loose: bool = _player != null and _player.assigned_animation in LOOSE_CLIPS
	_loose_weight = move_toward(_loose_weight, 1.0 if loose else 0.0, get_process_delta_time() / LOOSE_BLEND)
	var pivot := Basis.IDENTITY
	if _loose_weight > 0.0:
		var arm := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_sword_hand)).basis.orthonormalized()
		var held: Array = _loosened(turned, blade_local, forearm, (arm.inverse() * Vector3.UP).normalized())
		if not held.is_empty():
			turned = (turned as Quaternion).slerp(held[0], _loose_weight)
			pivot = Basis(held[1] as Vector3, (held[2] as float) * _loose_weight)
	grip.basis = pivot * _grip_rest
	# Standing and moving, the hand keeps the stance's wrist (see GAIT_CLIPS), blended in and out with the clips.
	var gait: Variant = _gait_hand(skeleton, blade_local, forearm)
	var moving: bool = _player != null and _player.assigned_animation in GAIT_CLIPS and gait != null
	_gait_weight = move_toward(_gait_weight, 1.0 if moving else 0.0, get_process_delta_time() / GAIT_BLEND)
	if gait != null and _gait_weight > 0.0:
		turned = (turned as Quaternion).slerp(gait, _gait_weight)
	skeleton.set_bone_pose_rotation(_sword_hand, turned)


## The loose grip for a rolled hand (see _rolled): [hand turn, pivot axis, pivot angle] with the pivot in the hand's
## frame (turning the grip's blade toward the fingers' axis); [] when the blade runs along the forearm. A blade that
## points below the forearm (up: skeleton up in the forearm's frame) is lifted to within LOOSE_LIFT of its line;
## then the sword turns in the fist (up to LOOSE_PIVOT) so the hand bends only LOOSE_BEND off the forearm.
static func _loosened(turned: Quaternion, blade_local: Vector3, forearm: Vector3, up: Vector3) -> Array:
	var blade := turned * blade_local
	# The plane of the forearm and the blade as posed; angles in it are signed, toward the posed blade positive,
	# so the lifted blade may reach the forearm's line.
	var n := forearm.cross(blade)
	if n.length() < 0.01: return []
	n = n.normalized()
	var angle := blade.angle_to(forearm)
	var below := clampf((forearm.dot(up) - blade.dot(up)) / 0.15, 0.0, 1.0)
	if angle > LOOSE_LIFT: angle = lerpf(angle, LOOSE_LIFT, below)
	var grip := Vector3.UP.angle_to(blade_local)
	var held := clampf(angle + LOOSE_BEND, grip - LOOSE_PIVOT, grip)
	var finger := forearm.rotated(n, -minf(held - angle, MAX_BEND))
	blade = finger.rotated(n, held)
	var axis := blade_local.cross(Vector3.UP).normalized()
	var blade_held := blade_local.rotated(axis, grip - held)
	var finger_local := (Vector3.UP - blade_held * blade_held.dot(Vector3.UP)).normalized()
	var toward := (finger - blade * blade.dot(finger)).normalized()
	var from := Basis(blade_held, finger_local, blade_held.cross(finger_local))
	var to := Basis(blade, toward, blade.cross(toward))
	return [(to * from.inverse()).get_rotation_quaternion(), axis, grip - held]


## The hand turned about its blade (kept as posed) to the roll that leaves it closest to the forearm; null when
## the blade runs along the forearm.
static func _rolled(pose: Quaternion, blade_local: Vector3, forearm: Vector3) -> Variant:
	var finger_local := (Vector3.UP - blade_local * blade_local.dot(Vector3.UP)).normalized()
	var blade := pose * blade_local
	var toward := forearm - blade * blade.dot(forearm)
	if toward.length() < 0.05: return null
	toward = toward.normalized()
	var from := Basis(blade_local, finger_local, blade_local.cross(finger_local))
	var to := Basis(blade, toward, blade.cross(toward))
	return (to * from.inverse()).get_rotation_quaternion()


## How far a rolled hand (see _rolled) bends off the forearm, positive away from its blade.
static func _bend(turned: Quaternion, forearm: Vector3) -> float:
	return (turned * Vector3.UP).angle_to(forearm)


## A rolled hand swung in the plane of the forearm and its blade to bend by angle off the forearm (negative:
## toward the blade side, raising the blade).
static func _bent(turned: Quaternion, forearm: Vector3, angle: float, blade_local: Vector3) -> Quaternion:
	# Turning about the plane's normal n carries the forearm's line toward the blade.
	var n := forearm.cross(turned * blade_local).normalized()
	var finger := turned * Vector3.UP
	var now := atan2(n.dot(forearm.cross(finger)), forearm.dot(finger))
	return Quaternion(n, -angle - now) * turned


## The hand for the gait clips: straight on the forearm and cocked GAIT_COCK toward the blade (the same wrist
## every frame), turned about the forearm so the blade comes as close as it can to the stance's blade direction
## (skeleton space, from the stance clip's first pose), so the swinging arm never turns the tip into the body or
## the ground. In the stance itself that is the stance's own blade plane.
func _gait_hand(skeleton: Skeleton3D, blade_local: Vector3, forearm: Vector3) -> Variant:
	if _player == null: _player = _find_player(skeleton)
	if _player == null or not _player.has_animation(GAIT_CLIPS[0]): return null
	var stance := _player.get_animation(GAIT_CLIPS[0])
	var chest := skeleton.find_bone(CHEST)
	if stance != _gait_source:
		_gait_source = stance
		_gait_aim = _clip_basis(skeleton, stance, _sword_hand) * blade_local
		# Held in the chest's frame, so the blade turns with the shoulders (half-turned in the stance, nearly
		# square in the walk and run) instead of crossing the body.
		if chest >= 0: _gait_aim = _clip_basis(skeleton, stance, chest).inverse() * _gait_aim
	var arm := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_sword_hand)).basis.orthonormalized()
	# Walking and running, the blade turns GAIT_MOVE_YAW outward so it clears the hips.
	var moving := _player.assigned_animation in GAIT_CLIPS and _player.assigned_animation != GAIT_CLIPS[0]
	_move_weight = move_toward(_move_weight, 1.0 if moving else 0.0, get_process_delta_time() / GAIT_MOVE_BLEND)
	var aim_skeleton := _gait_aim.rotated(Vector3.UP, GAIT_MOVE_YAW * _move_weight)
	if chest >= 0: aim_skeleton = skeleton.get_bone_global_pose(chest).basis.orthonormalized() * aim_skeleton
	var aim := (arm.inverse() * aim_skeleton).normalized()
	var n := forearm.cross(aim)
	if n.length() < 0.05: return null
	n = n.normalized()
	# The grip's angle between the hand's finger axis and the blade.
	var grip := Vector3.UP.angle_to(blade_local)
	var cock := GAIT_COCK
	var pitch := asin(clampf((arm * forearm.rotated(n, cock + grip)).y, -1.0, 1.0))
	var step := GAIT_COCK_STEP if pitch < GAIT_PITCH.x else -GAIT_COCK_STEP if pitch > GAIT_PITCH.y else 0.0
	while step != 0.0 and cock + step >= GAIT_COCK_RANGE.x and cock + step <= GAIT_COCK_RANGE.y:
		cock += step
		pitch = asin(clampf((arm * forearm.rotated(n, cock + grip)).y, -1.0, 1.0))
		if pitch >= GAIT_PITCH.x and pitch <= GAIT_PITCH.y: break
	var finger := forearm.rotated(n, cock)
	var blade := finger.rotated(n, grip)
	var finger_local := (Vector3.UP - blade_local * blade_local.dot(Vector3.UP)).normalized()
	var toward := (finger - blade * blade.dot(finger)).normalized()
	var from := Basis(blade_local, finger_local, blade_local.cross(finger_local))
	var to := Basis(blade, toward, blade.cross(toward))
	return (to * from.inverse()).get_rotation_quaternion()


## A bone's skeleton-space orientation in a clip's first pose (rest rotations where the clip has no track).
static func _clip_basis(skeleton: Skeleton3D, clip: Animation, bone: int) -> Basis:
	var tracks := {}
	for track in clip.get_track_count():
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			tracks[str(clip.track_get_path(track).get_concatenated_subnames())] = track
	var result := Basis.IDENTITY
	while bone >= 0:
		var bone_name := skeleton.get_bone_name(bone)
		var turn := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		if tracks.has(bone_name): turn = clip.rotation_track_interpolate(tracks[bone_name], 0.0)
		result = Basis(turn) * result
		bone = skeleton.get_bone_parent(bone)
	return result


static func _find_player(skeleton: Skeleton3D) -> AnimationPlayer:
	var node: Node = skeleton.get_parent()
	while node != null:
		var found := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if found != null: return found
		node = node.get_parent()
	return null
