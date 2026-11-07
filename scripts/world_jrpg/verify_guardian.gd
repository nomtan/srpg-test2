extends SceneTree
## Guardians (影（シャドウ） and 影２（シャドウ２）): each rigged model has a hinged jaw and clawed hands with its
## clips; the right-side panel's 出現 / 返還 buttons summon the chosen one behind the explorer's left shoulder
## (forming as ink, strokes swirling) and return it (erased, strokes scattering); it follows and faces the way
## the explorer faces. Choosing the other guardian while one is out swaps them.
## godot --headless --path . --script scripts/world_jrpg/verify_guardian.gd
## Rendered views: tools/asset_gen/character_pipeline/capture_guardian.gd.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const GUARDIANS := {
	"shadow1": preload("res://scenes/characters/guardians/shadow.tscn"),
	"shadow2": preload("res://scenes/characters/guardians/shadow2.tscn"),
}
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func reveal_of(guardian: Node3D) -> float:
	return guardian._reveal()

func check_model(id: String, scene: PackedScene) -> void:
	var lone: Node3D = scene.instantiate()
	root.add_child(lone)
	var skeleton := lone.find_child("Skeleton3D", true, false) as Skeleton3D
	check(skeleton != null, "%s has one skeleton" % id)
	for bone in ["Head", "Jaw", "RightHand", "RightFingers", "LeftHand", "LeftFingers", "Tail2"]:
		check(skeleton.find_bone(bone) >= 0, "%s bone %s" % [id, bone])
	var anim: AnimationPlayer = lone.animation_player
	for clip in ["idle", "roar", "attack", "attack_bite"]:
		check(anim.has_animation(clip), "%s clip %s" % [id, clip])
	check(anim.get_animation("idle").loop_mode == Animation.LOOP_LINEAR, "%s idle loops" % id)
	var jaw := skeleton.find_bone("Jaw")
	anim.play("roar")
	anim.seek(0.8, true)
	skeleton.force_update_all_bone_transforms()
	var rest := skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion()
	var open_angle := (rest.inverse() * skeleton.get_bone_pose_rotation(jaw)).get_angle()
	check(open_angle > 0.4, "%s roar opens the jaw wide (%.2f rad)" % [id, open_angle])
	check(not lone.visible and reveal_of(lone) == 0.0, "%s hidden until summoned" % id)
	check(lone.guardian_id == id, "%s scene carries its id" % id)
	lone.queue_free()

func run() -> void:
	# Models and rigs.
	for id: String in GUARDIANS:
		check_model(id, GUARDIANS[id])

	# World panel.
	var world = SAMPLE.instantiate()
	root.add_child(world)
	var actor: Node3D = world.player
	actor.set_process(false)
	check(world.guardian_buttons.size() == 2 and world.guardian_buttons[false].button_pressed, "出現 / 返還 buttons, 返還 lit at start")
	var panel := world.hud.find_child("GuardianPanel", true, false) as Control
	check(panel != null and panel.offset_right < -224, "Guardian panel sits left of the right-hand column")
	actor.world_facing = Vector3(0, 0, 1)
	actor._update_model()
	world._on_guardian_selected(true)
	var guardian: Node3D = world.guardian
	check(guardian != null and guardian.state == "appearing" and guardian.visible, "出現 starts the summon")
	check(world.guardian_buttons[true].button_pressed, "出現 lit")
	await create_timer(0.45).timeout
	var mid := reveal_of(guardian)
	check(mid > 0.0 and mid < 1.0, "Body forms gradually (reveal %.2f)" % mid)
	check(guardian.ink_fx.is_busy(), "Ink strokes swirl while it forms")
	await create_timer(1.0).timeout
	check(guardian.state == "present" and is_equal_approx(reveal_of(guardian), 1.0), "Fully formed")
	# Facing +Z (world): forward = +Z, so left = +X and behind = -Z.
	var local := guardian.global_position - actor.global_position
	check(local.x > 0.4 and local.z < -0.4 and local.y > 0.2, "Hovers behind the left shoulder (%s)" % local)
	check(guardian.global_basis.z.dot(Vector3(0, 0, 1)) > 0.95, "Faces the way the explorer faces")
	check(guardian.act("attack") and guardian.animation_player.current_animation == "attack", "Can strike while out")
	world._on_guardian_selected(false)
	check(guardian.state == "leaving" and world.guardian_buttons[false].button_pressed, "返還 starts the return")
	await create_timer(0.4).timeout
	var going := reveal_of(guardian)
	check(going > 0.0 and going < 1.0, "Erased gradually (reveal %.2f)" % going)
	await create_timer(0.9).timeout
	check(guardian.state == "hidden" and not guardian.visible, "Gone after the return")
	world._on_guardian_selected(true)
	await create_timer(0.3).timeout
	world._on_guardian_selected(false)
	check(guardian.state == "leaving", "Can be returned mid-summon")
	await create_timer(1.2).timeout

	# Choosing 影２: picked while hidden, then summoned; choosing 影 while it is out swaps them.
	check(world.guardian_choice_buttons.size() == 2 and world.guardian_choice_buttons["shadow1"].button_pressed, "影 / 影２ choice, 影 equipped at start")
	world._on_guardian_chosen("shadow2")
	check(world.guardian_id == "shadow2" and world.guardian_name_label.text == "影２（シャドウ２）", "影２ equipped, its name shown")
	check(world.guardian_choice_buttons["shadow2"].button_pressed, "影２ lit")
	check(guardian.state == "hidden", "影 stays returned")
	world._on_guardian_selected(true)
	var second: Node3D = world.guardian
	check(second != guardian and second.guardian_id == "shadow2" and second.state == "appearing", "出現 summons 影２")
	await create_timer(1.4).timeout
	check(second.state == "present", "影２ fully formed")
	local = second.global_position - actor.global_position
	check(local.x > 0.4 and local.z < -0.4, "影２ hovers behind the left shoulder (%s)" % local)
	check(second.act("attack_bite"), "影２ can bite")
	world._on_guardian_chosen("shadow1")
	check(second.state == "leaving" and world.guardian == guardian and guardian.state == "appearing", "Switching while out returns 影２ and summons 影")
	check(world.guardian_buttons[true].button_pressed, "出現 stays lit across the swap")
	await create_timer(1.4).timeout
	check(second.state == "hidden" and guardian.state == "present", "Swap settles: 影 out, 影２ gone")
	world._on_guardian_selected(false)
	check(guardian.state == "leaving", "返還 returns 影")
	print("GUARDIAN: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
