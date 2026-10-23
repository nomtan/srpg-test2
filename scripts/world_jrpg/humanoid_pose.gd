extends RefCounted
## Skeleton-space pose building shared by the procedural humanoid_v1 clips (ground_sit, gait_cycle):
## the idle's first frame as the base pose, two-bone IK and baking poses into an Animation.
## Skeleton space: +Z forward, +X the character's left, +Y up. Poses are {bone name: local Transform3D}.

const ARM_CHAINS := {
	"L": ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"],
	"R": ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"],
}
const LEG_CHAINS := {
	"L": ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot"],
	"R": ["mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"],
}
const TOES := {"L": "mixamorig_LeftToeBase", "R": "mixamorig_RightToeBase"}
const SPINE := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const HIPS := "mixamorig_Hips"
const NECK := "mixamorig_Neck"
const HEAD := "head"

var skeleton: Skeleton3D
var path: NodePath
var _idle: Dictionary = {}
var _idle_global: Dictionary = {}
# Hips to ankle in the idle pose.
var leg_length := 1.0


## Samples the idle as the base pose. False when the Body lacks an idle or a humanoid_v1 bone.
func setup(player: AnimationPlayer, target: Skeleton3D) -> bool:
	if player == null or target == null or not player.has_animation("idle"): return false
	var required: Array = [HIPS, NECK, HEAD] + SPINE + TOES.values()
	for chain: Array in ARM_CHAINS.values() + LEG_CHAINS.values():
		required.append_array(chain)
	for bone: String in required:
		if target.find_bone(bone) < 0: return false
	skeleton = target
	path = player.get_node(player.root_node).get_path_to(target)
	_key_rest_tracks(player.get_animation("idle"))
	_sample_idle(player.get_animation("idle"))
	return true


## The importer drops the idle's tracks for bones it leaves at rest, but the procedural clips key every
## bone. Once a blend into the idle ends, the player stops writing those bones, so stopping mid-stride
## left the hips lowered and the feet turned. Keys every missing rotation and position at rest instead.
## The idle is shared by every instance of the Body; the keys only state what it already meant.
func _key_rest_tracks(idle: Animation) -> void:
	for index in skeleton.get_bone_count():
		var node_path := NodePath("%s:%s" % [path, skeleton.get_bone_name(index)])
		var rest := skeleton.get_bone_rest(index)
		if idle.find_track(node_path, Animation.TYPE_ROTATION_3D) < 0:
			var track := idle.add_track(Animation.TYPE_ROTATION_3D)
			idle.track_set_path(track, node_path)
			idle.rotation_track_insert_key(track, 0.0, rest.basis.get_rotation_quaternion())
		if idle.find_track(node_path, Animation.TYPE_POSITION_3D) < 0:
			var track := idle.add_track(Animation.TYPE_POSITION_3D)
			idle.track_set_path(track, node_path)
			idle.position_track_insert_key(track, 0.0, rest.origin)


## The idle's first frame as local bone poses; bones the idle leaves still keep their rest.
func _sample_idle(idle: Animation) -> void:
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var local := skeleton.get_bone_rest(index)
		var node_path := NodePath("%s:%s" % [path, bone])
		var rotation_track := idle.find_track(node_path, Animation.TYPE_ROTATION_3D)
		var position_track := idle.find_track(node_path, Animation.TYPE_POSITION_3D)
		if rotation_track >= 0:
			local.basis = Basis(idle.rotation_track_interpolate(rotation_track, 0.0)).scaled(local.basis.get_scale())
		if position_track >= 0:
			local.origin = idle.position_track_interpolate(position_track, 0.0)
		_idle[bone] = local
	for index in skeleton.get_bone_count():
		_idle_global[skeleton.get_bone_name(index)] = _global(_idle, index)
	var hips: Transform3D = _idle_global[HIPS]
	leg_length = maxf(hips.origin.y - (_idle_global[LEG_CHAINS.L[2]] as Transform3D).origin.y, 0.01)


## Every bone keyed at every sample time, so nothing is left over from the previous clip.
func _bake(times: Array, poses: Array, length: float, loop: Animation.LoopMode) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = loop
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var node_path := NodePath("%s:%s" % [path, bone])
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, node_path)
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, node_path)
		for sample in times.size():
			var transform: Transform3D = poses[sample][bone]
			animation.rotation_track_insert_key(rotation_track, times[sample], transform.basis.get_rotation_quaternion())
			animation.position_track_insert_key(position_track, times[sample], transform.origin)
	return animation


## Two-bone IK in skeleton space; the middle joint bends toward pole. Returns the middle joint's position.
func _two_bone(pose: Dictionary, names: Array, target: Vector3, pole: Vector3) -> Vector3:
	var rest: Array = names.map(func(bone: String) -> Transform3D: return _idle_global[bone])
	var root := _global(pose, skeleton.find_bone(names[0]))
	var a: float = (rest[1].origin - rest[0].origin).length()
	var b: float = (rest[2].origin - rest[1].origin).length()
	var reach := target - root.origin
	var d := clampf(reach.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var direction := reach.normalized()
	var bend_toward := pole.normalized()
	var side := (bend_toward - direction * direction.dot(bend_toward)).normalized()
	var bend := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var middle := root.origin + (direction * bend + side * sqrt(1.0 - bend * bend)) * a
	var end := root.origin + direction * d
	for index in 2:
		var joint := _global(pose, skeleton.find_bone(names[index]))
		var from: Vector3 = (rest[index + 1].origin - rest[index].origin).normalized()
		var to := (middle - joint.origin) if index == 0 else (end - joint.origin)
		joint.basis = Basis(Quaternion(from, to.normalized())) * rest[index].basis
		_set_global(pose, names[index], joint)
	return middle


## Points bone (toward its child) along direction, turning it from its idle orientation.
func _aim(pose: Dictionary, bone: String, child: String, direction: Vector3) -> void:
	var joint := _global(pose, skeleton.find_bone(bone))
	var from: Vector3 = ((_idle_global[child] as Transform3D).origin - (_idle_global[bone] as Transform3D).origin).normalized()
	joint.basis = Basis(Quaternion(from, direction.normalized())) * (_idle_global[bone] as Transform3D).basis
	_set_global(pose, bone, joint)


## Gives bone a skeleton-space orientation: its idle one turned by rotation.
func _orient(pose: Dictionary, bone: String, rotation: Basis) -> void:
	var joint := _global(pose, skeleton.find_bone(bone))
	joint.basis = rotation * (_idle_global[bone] as Transform3D).basis
	_set_global(pose, bone, joint)


func _set_global(pose: Dictionary, bone: String, transform: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(skeleton.find_bone(bone))
	pose[bone] = _global(pose, parent).affine_inverse() * transform if parent >= 0 else transform


func _global(pose: Dictionary, index: int) -> Transform3D:
	var transform: Transform3D = pose[skeleton.get_bone_name(index)]
	var parent := skeleton.get_bone_parent(index)
	while parent >= 0:
		transform = (pose[skeleton.get_bone_name(parent)] as Transform3D) * transform
		parent = skeleton.get_bone_parent(parent)
	return transform
