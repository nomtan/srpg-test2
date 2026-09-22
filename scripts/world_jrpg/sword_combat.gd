extends RefCounted
## Player-only equipment and authored full-body clips for the shared Tripo rig.
## The imported character and sword resources are never modified.
const SWORD = preload("res://assets/weapons/sword/test_sword/swordl.glb")
const SLASH := "sword/slash"
const OVERHEAD := "sword/overhead"
const GRIP := Vector3(0.0, 0.687, -0.253)
const SOURCE_BLADE := Vector3(0.0, -0.70, 0.715)
const READY_BLADE := Vector3(-0.55, 0.24, 1.0)

var skeleton: Skeleton3D
var socket: BoneAttachment3D
var grip: Node3D
var _idle: Dictionary = {}
var _idle_global: Dictionary = {}

func install(model: Node3D, player: AnimationPlayer) -> bool:
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or player == null or not player.has_animation("idle"):
		return false
	for bone in ["spine", "chest", "head", "upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "forearm.L", "hand.L"]:
		if skeleton.find_bone(bone) < 0: return false
	player.play("idle", 0)
	player.advance(0)
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		_idle[bone] = skeleton.get_bone_pose(index)
		_idle_global[bone] = skeleton.get_bone_global_pose(index)
	_attach_sword()
	var library := AnimationLibrary.new()
	var path := player.get_node(player.root_node).get_path_to(skeleton)
	library.add_animation("slash", _make_attack(path, false))
	library.add_animation("overhead", _make_attack(path, true))
	player.add_animation_library("sword", library)
	return true

func _attach_sword() -> void:
	socket = BoneAttachment3D.new()
	socket.name = "SwordHandSocket"
	socket.bone_name = "hand.R"
	skeleton.add_child(socket)
	grip = Node3D.new()
	grip.name = "SwordGrip"
	# The hand bone begins at the wrist; the palm center is 0.02 units along it.
	grip.position = Vector3(0, 0.02, 0)
	var hand: Transform3D = _idle_global["hand.R"]
	grip.basis = hand.basis.inverse() * Basis(Quaternion(Vector3.UP, READY_BLADE.normalized()))
	socket.add_child(grip)
	var sword := SWORD.instantiate() as Node3D
	sword.name = "EquippedSword"
	# Normalize the diagonal source blade to +Y and put its handle at the origin.
	sword.basis = Basis(Quaternion(SOURCE_BLADE.normalized(), Vector3.UP)).scaled(Vector3.ONE * 0.52)
	sword.position = -(sword.basis * GRIP)
	grip.add_child(sword)

func _make_attack(path: NodePath, overhead: bool) -> Animation:
	var animation := Animation.new()
	animation.resource_name = "上段斬り" if overhead else "横薙ぎ"
	animation.length = 0.88 if overhead else 0.64
	animation.loop_mode = Animation.LOOP_NONE
	# Time, torso yaw/pitch, upper-arm direction, forearm direction, blade direction.
	# Arms are aimed in character space (+Z forward); lengths come from each rig.
	var keys: Array
	if overhead:
		keys = [
			[0.0, 0.0, 0.0, null, null, null],
			[0.20, -12.0, -7.0, Vector3(-.45,.8,.25), Vector3(.10,.8,-.45), Vector3(0,.25,-1)],
			[0.32, -8.0, -5.0, Vector3(-.35,.9,.30), Vector3(.12,.85,.10), Vector3(0,.95,-.30)],
			[0.44, 8.0, 13.0, Vector3(-.30,-.25,1), Vector3(.18,-.25,1), Vector3(0,-.70,1)],
			[0.56, 14.0, 10.0, Vector3(-.35,-.45,.9), Vector3(.15,-.25,.95), Vector3(.15,-.50,1)],
			[0.70, 7.0, 4.0, Vector3(-.60,-.65,.25), Vector3(-.10,-.65,.55), Vector3(.12,-.05,1)],
			[0.88, 0.0, 0.0, null, null, null],
		]
	else:
		keys = [
			[0.0, 0.0, 0.0, null, null, null],
			[0.14, -32.0, -3.0, Vector3(-.9,.10,.15), Vector3(-.6,.25,.6), Vector3(-1,.15,-.35)],
			[0.21, -22.0, 0.0, Vector3(-.75,.05,.6), Vector3(-.35,.10,1), Vector3(-1,.05,.5)],
			[0.30, 24.0, 5.0, Vector3(-.25,-.15,1), Vector3(.7,.10,.8), Vector3(.75,0,1)],
			[0.39, 35.0, 4.0, Vector3(.20,-.2,1), Vector3(.9,.05,.25), Vector3(1,-.15,.15)],
			[0.49, 17.0, 2.0, Vector3(-.25,-.65,.7), Vector3(.3,-.45,.75), Vector3(.55,.1,.85)],
			[0.64, 0.0, 0.0, null, null, null],
		]
	var tracks: Dictionary = {}
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(index)
		var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation_track, NodePath(str(path) + ":" + bone))
		var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(position_track, NodePath(str(path) + ":" + bone))
		tracks[bone] = [rotation_track, position_track]
	for key: Array in keys:
		var pose := _pose(key)
		for bone: String in tracks:
			var transform: Transform3D = pose[bone]
			animation.rotation_track_insert_key(tracks[bone][0], key[0], transform.basis.get_rotation_quaternion())
			animation.position_track_insert_key(tracks[bone][1], key[0], transform.origin)
	return animation

func _pose(key: Array) -> Dictionary:
	var pose := _idle.duplicate()
	if key[3] == null: return pose
	var spine: Transform3D = pose["spine"]
	spine.basis = Basis.from_euler(Vector3(deg_to_rad(key[2]), deg_to_rad(key[1]), 0)) * spine.basis
	pose["spine"] = spine
	# Counter-rotate the head so the eyes stay on the target while the body turns.
	var head: Transform3D = pose["head"]
	head.basis = Basis(Vector3.UP, deg_to_rad(-key[1] * .7)) * head.basis
	pose["head"] = head
	_aim_arm(pose, "R", key[3], key[4])
	_aim_arm(pose, "L", Vector3(.65,-.55,.25), Vector3(-.2,.3,.8))
	var hand: Transform3D = _global(pose, skeleton.find_bone("hand.R"))
	var idle_hand: Transform3D = _idle_global["hand.R"]
	hand.basis = Basis(Quaternion(READY_BLADE.normalized(), (key[5] as Vector3).normalized())) * idle_hand.basis
	_set_global(pose, "hand.R", hand)
	return pose

func _aim_arm(pose: Dictionary, side: String, upper: Vector3, fore: Vector3) -> void:
	for spec in [["upper_arm." + side, upper], ["forearm." + side, fore], ["hand." + side, fore]]:
		var bone: String = spec[0]
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
