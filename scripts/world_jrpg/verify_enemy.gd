extends SceneTree
## Goblin enemy: one rigged GLB with idle / walk / attack / guard / hit / death, swappable weapon and
## shield, crumbling to dust when defeated; four weapon patterns placed in JRPGWorldSample2.
## Wolf: a quadruped with the same clips and no equipment, placed after the goblins.
## Grimm: an antlered quadruped (gore and bite attacks, no equipment), placed after the wolf.
## godot --headless --path . --script scripts/world_jrpg/verify_enemy.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/enemy/).
const GOBLIN = preload("res://scenes/characters/enemies/goblin.tscn")
const WOLF = preload("res://scenes/characters/enemies/wolf.tscn")
const GRIMM = preload("res://scenes/characters/enemies/grimm.tscn")
const PATTERNS := {"res://scenes/characters/enemies/goblin_axe.tscn": ["hand_axe", "round"],
	"res://scenes/characters/enemies/goblin_longsword.tscn": ["longsword", "kite"],
	"res://scenes/characters/enemies/goblin_staff.tscn": ["staff", "none"]}
const SAMPLE = preload("res://samples/JRPGWorldSample2.tscn")
# Where the source model's blade tip was (glTF axes, rest space).
const SOURCE_TIP := Vector3(-0.47, 0.72, 0.49)
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	var goblin := GOBLIN.instantiate() as Node3D
	root.add_child(goblin)
	var player: AnimationPlayer = goblin.animation_player
	check(player != null, "Goblin has an AnimationPlayer")
	for clip in goblin.CLIPS:
		check(player.has_animation(clip), "Goblin has the %s clip" % clip)
	check(player.get_animation("idle").loop_mode == Animation.LOOP_LINEAR and player.get_animation("death").loop_mode == Animation.LOOP_NONE, "idle loops, death holds its last frame")
	check(is_equal_approx(goblin.get_node("Model").scale.x, 2.025), "Goblin is drawn 1.5 times its first size")
	var skeleton: Skeleton3D = goblin.skeleton
	check(goblin.find_children("*", "Skeleton3D", true, false).size() == 1, "One skeleton")
	var body: MeshInstance3D = null
	for mesh: MeshInstance3D in goblin.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null: body = mesh
	check(body != null, "One skinned body mesh")
	var bounds := body.get_aabb()
	# The stray pieces floated up to 0.48 m behind the source model; only the body remains.
	check(bounds.position.z > -0.36 and bounds.position.y > -0.01, "Floating pieces behind the goblin are gone (%s)" % bounds)
	check(bounds.position.x > -0.42 and bounds.end.z < 0.4, "Blade and shield are no longer part of the body (%s)" % bounds)
	check(body.get_surface_override_material(0) is ShaderMaterial, "Goblin renders with the flat dissolve material")
	# Equipment sits where the source model held it.
	player.stop()
	skeleton.reset_bone_poses()
	var weapon := _held(goblin, "WeaponSocket")
	var shield := _held(goblin, "ShieldSocket")
	check(weapon != null and shield != null, "The scimitar and round shield hang from the hand sockets")
	if weapon:
		var in_skeleton := skeleton.global_transform.affine_inverse() * weapon.global_transform
		var aabb := weapon.get_aabb()
		var tip := in_skeleton * Vector3(aabb.get_center().x, aabb.end.y, aabb.get_center().z)
		check(tip.distance_to(SOURCE_TIP) < 0.08, "The scimitar tip is where the source model had it (%.3f m off)" % tip.distance_to(SOURCE_TIP))
	for id in ["hand_axe", "longsword", "staff", "none", "scimitar"]:
		goblin.set_weapon(id)
		check((_held(goblin, "WeaponSocket") != null) == (id != "none"), "Weapon swaps to " + id)
	for id in ["kite", "none", "round"]:
		goblin.set_shield(id)
		check((_held(goblin, "ShieldSocket") != null) == (id != "none"), "Shield swaps to " + id)
	var head := skeleton.find_bone("Head")
	var rest := skeleton.get_bone_global_rest(head).origin
	for clip in ["attack", "guard", "hit", "death"]:
		player.play(clip)
		player.seek(player.get_animation(clip).length * 0.5, true)
		var moved := skeleton.get_bone_global_pose(head).origin.distance_to(rest)
		check(moved > 0.02, "%s moves the head (%.3f m)" % [clip, moved])
	check(_looks_up(skeleton) > 0.4, "Goblin death first throws its head back to look up (%.2f rad)" % _looks_up(skeleton))
	check(_slumps_forward(skeleton), "Goblin death ends slumped forward where it knelt (%s)" % _slump_report(skeleton))
	if capture:
		await _capture(goblin)
	goblin.queue_free()
	for path: String in PATTERNS:
		var pattern := (load(path) as PackedScene).instantiate()
		root.add_child(pattern)
		check(pattern.weapon_id == PATTERNS[path][0] and pattern.shield_id == PATTERNS[path][1], "%s carries %s and %s" % [path.get_file(), PATTERNS[path][0], PATTERNS[path][1]])
		check(_held(pattern, "WeaponSocket") != null, path.get_file() + " shows its weapon")
		pattern.queue_free()
	await _check_wolf()
	await _check_grimm()
	await process_frame
	var world := SAMPLE.instantiate()
	root.add_child(world)
	await process_frame
	check(world.enemies.size() == 6, "JRPGWorldSample2 places four goblins, a wolf and a grimm")
	var ids: Array = world.enemies.map(func(e: Node) -> String: return e.enemy_id + ":" + e.weapon_id)
	check(ids == ["goblin:scimitar", "goblin:hand_axe", "goblin:longsword", "goblin:staff", "wolf:none", "grimm:none"], "Scimitar, hand axe, longsword and staff goblins, then the wolf and the grimm (%s)" % [ids])
	var demos: Array = world.enemies.map(func(e: Node) -> bool: return e.demo)
	check(demos == [true, false, false, false, true, true], "The first goblin, the wolf and the grimm run the motion demo (%s)" % [demos])
	var target: Node3D = world.enemies[1]
	var home := target.position
	world.player.position = target.position - Vector3(0, 0, 1.2)
	world.player.world_facing = Vector3(0, 0, 1)
	var hp: int = target.hp
	for i in 12:
		world._on_player_attack_impact("slash")
		await create_timer(0.1).timeout
		if target.is_dead(): break
	check(target.hp < hp, "Player blows reach the goblin")
	check(target.is_dead() and target.animation_player.current_animation == "death", "Enough blows fell the goblin")
	await create_timer(target.animation_player.get_animation("death").length + target.LIE_STILL + target.CRUMBLE * 0.5).timeout
	check(target.get_node_or_null("Dust") != null, "The fallen goblin crumbles into dust")
	var dissolving: float = _held(target, "WeaponSocket").get_instance_shader_parameter("dissolve")
	check(dissolving > 0.2 and dissolving < 0.9, "Body and weapon dissolve together (%.2f)" % dissolving)
	await create_timer(target.CRUMBLE * 0.5 + 0.2).timeout
	check(not target.get_node("Model").visible, "Nothing is left once the dust settles")
	await target.respawned
	check(target.hp == target.max_hp and target.get_node("Model").visible and target.position.distance_to(home) < 0.2, "The goblin comes back where it stood")
	quit(1 if failed else 0)

func _check_wolf() -> void:
	var wolf := WOLF.instantiate() as Node3D
	root.add_child(wolf)
	var player: AnimationPlayer = wolf.animation_player
	check(player != null, "Wolf has an AnimationPlayer")
	for clip in wolf.CLIPS:
		check(player.has_animation(clip), "Wolf has the %s clip" % clip)
	check(player.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and player.get_animation("attack").loop_mode == Animation.LOOP_NONE, "Wolf walk loops, attack plays once")
	var skeleton: Skeleton3D = wolf.skeleton
	for bone in ["Jaw", "Tail2", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		check(skeleton.find_bone(bone) >= 0, "Wolf skeleton has " + bone)
	var skinned := wolf.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.skin != null)
	check(skinned.size() == 1 and skinned[0].get_surface_override_material(0) is ShaderMaterial, "One skinned wolf body with the flat dissolve material")
	check(wolf.weapon_id == "none" and wolf.shield_id == "none" and skeleton.get_node_or_null("WeaponSocket") == null and skeleton.get_node_or_null("ShieldSocket") == null, "The wolf carries no weapon or shield")
	player.stop()
	skeleton.reset_bone_poses()
	var head := skeleton.find_bone("Head")
	var jaw := skeleton.find_bone("Jaw")
	var rest := skeleton.get_bone_global_rest(head).origin
	for clip in ["attack", "guard", "hit", "death"]:
		player.play(clip)
		player.seek(player.get_animation(clip).length * 0.5, true)
		var moved := skeleton.get_bone_global_pose(head).origin.distance_to(rest)
		check(moved > 0.02, "Wolf %s moves the head (%.3f m)" % [clip, moved])
	check(is_equal_approx(wolf.get_node("Model").scale.x, 3.6), "Wolf is drawn twice its first size")
	check(wolf.attack_clips() == ["attack", "attack_bite"], "Wolf has two attacks: claw and bite (%s)" % [wolf.attack_clips()])
	check(player.get_animation("attack_bite").loop_mode == Animation.LOOP_NONE, "attack_bite plays once")
	# Claw: the right forepaw goes up above the head, then slams down onto the ground ahead.
	var paw := skeleton.find_bone("RightHand")
	var paw_rest := skeleton.get_bone_global_rest(paw).origin
	player.play("attack")
	player.seek(11.0 / 30.0, true)
	var raised := skeleton.get_bone_global_pose(paw).origin
	player.seek(15.0 / 30.0, true)
	var slammed := skeleton.get_bone_global_pose(paw).origin
	check(raised.y > rest.y + 0.05 and slammed.y < 0.12 and slammed.z > paw_rest.z, "Wolf claw raises the paw above the head (%.3f m) and slams it down ahead (%s)" % [raised.y, slammed])
	# Bite: jaws wide in the leap, teeth in the target BITE_REACH ahead, airborne on the hop back, home at the end.
	var hips_bone := skeleton.find_bone("Hips")
	var hips_rest := skeleton.get_bone_global_rest(hips_bone).origin
	player.play("attack_bite")
	player.seek(6.0 / 30.0, true)
	var open := (skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion().inverse() * skeleton.get_bone_pose_rotation(jaw)).get_angle()
	player.seek(9.0 / 30.0, true)
	var reach := skeleton.get_bone_global_pose(hips_bone).origin.z - hips_rest.z
	# Highest point after the bite (from the push-off on): the hop back.
	var hop := Vector3(0, -1, 0)
	for frame in range(12, 24):
		player.seek(frame / 30.0, true)
		var at := skeleton.get_bone_global_pose(hips_bone).origin
		if at.y > hop.y: hop = at
	player.seek(player.get_animation("attack_bite").length, true)
	var home := skeleton.get_bone_global_pose(hips_bone).origin.distance_to(hips_rest)
	check(open > 0.4 and reach > 0.35, "Wolf bite leaps jaws open (%.2f rad) onto the target (%.3f m ahead)" % [open, reach])
	check(hop.y > hips_rest.y + 0.05 and hop.z - hips_rest.z < reach * 0.6 and home < 0.01, "Wolf jumps back (%s) to where it started (%.3f m off)" % [hop, home])
	# Trot: the left foreleg and right hind leg swing one way while the other pair swings the other.
	player.play("walk")
	var paws := []
	for t in [0.25, 0.75]:
		player.seek(player.get_animation("walk").length * t, true)
		paws.append([skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.z, skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin.z, skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin.z])
	var left_front: float = paws[1][0] - paws[0][0]
	var right_hind: float = paws[1][1] - paws[0][1]
	var right_front: float = paws[1][2] - paws[0][2]
	check(absf(left_front) > 0.04 and signf(left_front) == signf(right_hind) and signf(left_front) != signf(right_front), "Wolf walk swings diagonal leg pairs together (%.3f %.3f %.3f)" % [left_front, right_hind, right_front])
	check(_looks_up(skeleton) > 0.4, "Wolf death first throws its head back to look up (%.2f rad)" % _looks_up(skeleton))
	check(_slumps_forward(skeleton), "Wolf death ends sunk forward on its belly where it stood (%s)" % _slump_report(skeleton))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_wolf(wolf)
	wolf.queue_free()

func _check_grimm() -> void:
	var grimm := GRIMM.instantiate() as Node3D
	root.add_child(grimm)
	var player: AnimationPlayer = grimm.animation_player
	check(player != null, "Grimm has an AnimationPlayer")
	for clip in grimm.CLIPS:
		check(player.has_animation(clip), "Grimm has the %s clip" % clip)
	check(grimm.attack_clips() == ["attack", "attack_bite"], "Grimm has two attacks: gore and bite (%s)" % [grimm.attack_clips()])
	check(player.get_animation("idle").loop_mode == Animation.LOOP_LINEAR and player.get_animation("attack_bite").loop_mode == Animation.LOOP_NONE, "Grimm idle loops, bite plays once")
	var skeleton: Skeleton3D = grimm.skeleton
	for bone in ["Jaw", "LeftAntler1", "RightAntler1", "Tail2", "LeftHand", "RightFoot"]:
		check(skeleton.find_bone(bone) >= 0, "Grimm skeleton has " + bone)
	var skinned := grimm.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.skin != null)
	check(skinned.size() == 1 and skinned[0].get_surface_override_material(0) is ShaderMaterial, "One skinned grimm body with the flat dissolve material")
	check(grimm.weapon_id == "none" and skeleton.get_node_or_null("WeaponSocket") == null and skeleton.get_node_or_null("ShieldSocket") == null, "The grimm carries no weapon or shield")
	check(is_equal_approx(grimm.get_node("Model").scale.x, 5.6) and grimm.max_hp == 5, "Grimm is drawn 5.6 times its source size and takes five blows")
	# The 3 mm sliver inside the mane is gone; the body keeps its own centre line (not the off-centre front feet).
	var bounds: AABB = skinned[0].get_aabb()
	check(absf(bounds.get_center().x) < 0.03 and bounds.position.y > -0.01, "Grimm stands centred on the ground (%s)" % bounds)
	player.stop()
	skeleton.reset_bone_poses()
	var head := skeleton.find_bone("Head")
	var antler := skeleton.find_bone("LeftAntler1")
	var rest := skeleton.get_bone_global_rest(head).origin
	var antler_span := skeleton.get_bone_global_rest(antler).origin.distance_to(rest)
	for clip in ["attack", "attack_bite", "guard", "hit", "death"]:
		player.play(clip)
		player.seek(player.get_animation(clip).length * 0.5, true)
		var moved := skeleton.get_bone_global_pose(head).origin.distance_to(rest)
		var span := skeleton.get_bone_global_pose(antler).origin.distance_to(skeleton.get_bone_global_pose(head).origin)
		check(moved > 0.02 and absf(span - antler_span) < 0.001, "Grimm %s moves the head (%.3f m) and the antlers ride on it" % [clip, moved])
	# Gore: reared up with the head high, then the head driven down and forward. Key frame f plays at (f + 1) / 30 s.
	player.play("attack")
	player.seek(13.0 / 30.0, true)
	var reared := skeleton.get_bone_global_pose(head).origin
	player.seek(17.0 / 30.0, true)
	var gored := skeleton.get_bone_global_pose(head).origin
	check(reared.y > rest.y + 0.03 and gored.y < reared.y - 0.05 and gored.z > rest.z + 0.08, "Grimm rears (%s) and drives its antlers forward (%s)" % [reared, gored])
	# Bite: jaws wide in the lunge GRIMM_BITE_REACH ahead, snapped shut, then back home.
	var jaw := skeleton.find_bone("Jaw")
	var hips_bone := skeleton.find_bone("Hips")
	var hips_rest := skeleton.get_bone_global_rest(hips_bone).origin
	player.play("attack_bite")
	player.seek(10.0 / 30.0, true)
	var open := (skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion().inverse() * skeleton.get_bone_pose_rotation(jaw)).get_angle()
	var reach := skeleton.get_bone_global_pose(hips_bone).origin.z - hips_rest.z
	player.seek(12.0 / 30.0, true)
	var shut := (skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion().inverse() * skeleton.get_bone_pose_rotation(jaw)).get_angle()
	player.seek(player.get_animation("attack_bite").length, true)
	var home := skeleton.get_bone_global_pose(hips_bone).origin.distance_to(hips_rest)
	check(open > 0.5 and shut < 0.1 and reach > 0.25 and home < 0.01, "Grimm bite lunges %.3f m jaws open (%.2f rad), snaps shut (%.2f) and returns (%.3f m off)" % [reach, open, shut, home])
	# Walk: the forelegs swing against each other.
	player.play("walk")
	var paws := []
	for t in [0.25, 0.75]:
		player.seek(player.get_animation("walk").length * t, true)
		paws.append(skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.z - skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin.z)
	check(signf(paws[0]) != signf(paws[1]) and absf(paws[0] - paws[1]) > 0.08, "Grimm walk alternates its forelegs (%s)" % [paws])
	check(_looks_up(skeleton) > 0.4, "Grimm death first howls at the sky (%.2f rad)" % _looks_up(skeleton))
	check(_slumps_forward(skeleton), "Grimm death ends sunk forward on its belly where it stood (%s)" % _slump_report(skeleton))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_grimm(grimm)
	grimm.queue_free()

func _capture_grimm(grimm: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(10.4, 5.6, 9.2)
	root.add_child(camera)
	camera.look_at(Vector3(0, 2.4, 0.6))
	camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/enemy"))
	var player: AnimationPlayer = grimm.animation_player
	for shot in [["idle", 0.0], ["walk", 0.25], ["attack", 0.35], ["attack", 0.47], ["attack_bite", 0.35], ["guard", 0.6], ["hit", 0.2], ["death", 0.2], ["death", 1.0]]:
		player.play(shot[0])
		player.seek(player.get_animation(shot[0]).length * shot[1], true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/enemy/grimm_%s_%d.png" % [shot[0], int(shot[1] * 100)])
	camera.queue_free()

func _capture_wolf(wolf: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(5.6, 2.6, 4.2)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 1.0))
	camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/enemy"))
	var player: AnimationPlayer = wolf.animation_player
	for shot in [["idle", 0.0], ["walk", 0.25], ["attack", 0.37], ["attack", 0.5], ["attack_bite", 0.27], ["attack_bite", 0.4], ["attack_bite", 0.71], ["guard", 0.6], ["hit", 0.2], ["death", 1.0]]:
		player.play(shot[0])
		player.seek(player.get_animation(shot[0]).length * shot[1], true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/enemy/wolf_%s_%d.png" % [shot[0], int(shot[1] * 100)])
	camera.queue_free()

## The end of the death clip: collapsed forward where it stood rather than toppled onto its back or side.
## The head has dropped to three quarters of its standing height or less and stays in front of the hips,
## the hips have not rolled about the forward axis (measured from their rest turn), and the body has not slid
## away from its spot.
func _slumps_forward(skeleton: Skeleton3D) -> bool:
	var at := _slump_pose(skeleton)
	return at.head.y < at.rest_head.y * 0.75 and at.head.z > at.hips.origin.z and absf(at.roll) < 0.25 and Vector2(at.hips.origin.x, at.hips.origin.z).length() < 0.3

func _slump_report(skeleton: Skeleton3D) -> String:
	var at := _slump_pose(skeleton)
	return "head %s from %s, hips %s, roll %.2f" % [at.head, at.rest_head, at.hips.origin, at.roll]

func _slump_pose(skeleton: Skeleton3D) -> Dictionary:
	var player := skeleton.get_parent().get_parent().find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.play("death")
	player.seek(player.get_animation("death").length, true)
	var head := skeleton.find_bone("Head")
	var hips := skeleton.find_bone("Hips")
	var hips_pose := skeleton.get_bone_global_pose(hips)
	# The hips' turn away from rest, applied to the side axis: its rise is the roll.
	var turn := hips_pose.basis.orthonormalized() * skeleton.get_bone_global_rest(hips).basis.orthonormalized().inverse()
	return {"head": skeleton.get_bone_global_pose(head).origin, "rest_head": skeleton.get_bone_global_rest(head).origin,
		"hips": hips_pose, "roll": (turn * Vector3.RIGHT).y}

## How far (radians) the head tilts up from rest partway into the death clip, while it stares at the sky
## before the strength goes: the head bone's direction measured from forward (+Z) toward up (+Y).
func _looks_up(skeleton: Skeleton3D) -> float:
	var head := skeleton.find_bone("Head")
	var player := skeleton.get_parent().get_parent().find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.play("death")
	player.seek(20.0 / 30.0, true)
	var pose := skeleton.get_bone_global_pose(head).basis.y
	var rest := skeleton.get_bone_global_rest(head).basis.y
	return atan2(pose.y, pose.z) - atan2(rest.y, rest.z)

## The equipment mesh under a hand socket, ignoring parts already swapped out.
func _held(enemy: Node, socket: String) -> MeshInstance3D:
	var attachment: Node = enemy.skeleton.get_node_or_null(socket)
	if attachment == null: return null
	for part in attachment.get_node("Frame").get_children():
		if part.is_queued_for_deletion(): continue
		var meshes := part.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty(): return meshes[0]
	return null

func _capture(goblin: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(1.4, 1.4, 3.6)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0.85, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/enemy"))
	var player: AnimationPlayer = goblin.animation_player
	for id in ["scimitar", "hand_axe", "longsword", "staff"]:
		goblin.set_weapon(id)
		goblin.set_shield({"longsword": "kite", "staff": "none"}.get(id, "round"))
		for clip in ["idle", "attack"]:
			player.play(clip)
			player.seek(player.get_animation(clip).length * (0.0 if clip == "idle" else 0.35), true)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/enemy/goblin_%s_%s.png" % [id, clip])
	player.play("death")
	player.seek(player.get_animation("death").length, true)
	for k in 4:
		goblin._set_dissolve(k / 4.0 + 0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/enemy/goblin_dust_%d.png" % k)
	goblin._set_dissolve(0.0)
