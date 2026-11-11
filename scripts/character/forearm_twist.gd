extends SkeletonModifier3D
## Keeps the wrists of a whole-character rig (build_rigged_character.py) from bending and wringing under
## SwordCombat's shared clips, which turn the hand bone freely. Runs after the animation and the other modifiers:
## 1. The sword hand: the shared clips turn the hand only to point the blade, so the hand often bends far
##    off the forearm. With the blade's direction kept exactly, the hand is turned about the blade to the
##    one roll that leaves it closest to the forearm's line (only the edges roll, the sword still points as
##    the clip says). Where the blade runs nearly along the forearm the wrist stops at MAX_BEND and the blade
##    gives way instead.
## 2. Each hand's turn about the forearm is spread over the forearm's twist bones: each twist bone turns by
##    its share of the hand's twist, so the wrist does not wring when a grip turns the hand.

const SIDES := ["Left", "Right"]
# Twist bone suffix: share of the hand's twist.
const SHARES := {"ForeArmTwist1": 1.0 / 3.0, "ForeArmTwist2": 2.0 / 3.0}
# SwordCombat's sword grip under the right hand's bone (the blade along its +Y, in the hand bone's frame).
const SWORD_GRIP := "SwordHandSocket/SwordGrip"
# The furthest the sword hand bends off the forearm's line; past it the blade turns with the hand instead.
const MAX_BEND := deg_to_rad(40.0)

var _chains: Array = []
var _sword_hand := -1


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
	var blade_local := grip.basis.y.normalized()
	var finger_local := (Vector3.UP - blade_local * blade_local.dot(Vector3.UP)).normalized()
	var pose := skeleton.get_bone_pose_rotation(_sword_hand)
	var blade := pose * blade_local
	var forearm := skeleton.get_bone_pose_position(_sword_hand).normalized()
	var toward := forearm - blade * blade.dot(forearm)
	if toward.length() < 0.05: return
	toward = toward.normalized()
	var from := Basis(blade_local, finger_local, blade_local.cross(finger_local))
	var to := Basis(blade, toward, blade.cross(toward))
	var turned := (to * from.inverse()).get_rotation_quaternion()
	# Where the blade runs almost along the forearm no roll is enough: the wrist stops at MAX_BEND and the blade gives.
	var finger := turned * Vector3.UP
	var bend := finger.angle_to(forearm)
	if bend > MAX_BEND:
		turned = Quaternion(finger.cross(forearm).normalized(), bend - MAX_BEND) * turned
	skeleton.set_bone_pose_rotation(_sword_hand, turned)
