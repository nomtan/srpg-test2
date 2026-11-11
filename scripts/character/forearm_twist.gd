extends SkeletonModifier3D
## Spreads the hand's turn about the forearm over the forearm's twist bones (build_rigged_character.py):
## each twist bone turns by its share of the hand's twist, so the wrist does not wring when a grip turns
## the hand (SwordCombat's clips put the whole turn on the hand bone). Runs after the animation and the
## other modifiers; the hand itself is left as posed, so held weapons stay where they are.

const SIDES := ["Left", "Right"]
# Twist bone suffix: share of the hand's twist.
const SHARES := {"ForeArmTwist1": 1.0 / 3.0, "ForeArmTwist2": 2.0 / 3.0}

var _chains: Array = []


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
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
	for chain: Array in _chains:
		var hand: int = chain[0]
		# The hand's turn about its own axis (local +Y, along the arm): the twist of a swing-twist split.
		var turn := skeleton.get_bone_rest(hand).basis.get_rotation_quaternion().inverse() * skeleton.get_bone_pose_rotation(hand)
		var angle := wrapf(2.0 * atan2(turn.y, turn.w), -PI, PI)
		for twist: Array in chain[1]:
			var rest := skeleton.get_bone_rest(twist[0])
			skeleton.set_bone_pose_rotation(twist[0], rest.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, angle * twist[1]))
			skeleton.set_bone_pose_position(twist[0], rest.origin)
