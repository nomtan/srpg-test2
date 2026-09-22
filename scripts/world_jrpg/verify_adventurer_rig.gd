extends SceneTree
## Exercise actual imported skins, shared bones, animation and modular swaps.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const NPC = preload("res://scenes/characters/adventurer_npc.tscn")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func mesh_of(part: Node3D) -> MeshInstance3D:
	return part if part is MeshInstance3D else part.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func skin_points(mesh: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var data := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = data[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
	var matrices: Array[Transform3D] = []
	for i in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(i))
		matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(i))
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for i in vertices.size():
		var point := Vector3.ZERO
		for j in 4:
			point += (matrices[bones[i * 4 + j]] * vertices[i]) * weights[i * 4 + j]
		result[i] = point
	return result

func seek(npc: AdventurerCharacter, clip: String, time: float) -> void:
	npc.play_animation(clip, 0)
	npc.animation_player.seek(time, true)
	npc.animation_player.advance(0)
	npc.animation_player.pause()

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/meshy_adventure/rig/" + name + ".png")

func run() -> void:
	root.size = Vector2i(1280, 720)
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	var npc := world.get_node("AdventurerNPC") as AdventurerCharacter
	await process_frame
	var rig := npc.skeleton
	check(rig != null and rig.get_bone_count() == 30, "All 30 fitted bones imported")
	check(npc.find_children("*", "Skeleton3D", true, false).size() == 1, "Exactly one skeleton drives body, face and hair")
	check(npc.animation_player != null and npc.animation_player.current_animation == "idle", "Stationary NPC starts its idle animation")
	for clip in {"idle": 3.0, "rig_check": 4.0}:
		check(npc.animation_player.has_animation(clip), "Clip imported: " + clip)
		var anim := npc.animation_player.get_animation(clip)
		check(is_equal_approx(anim.length, {"idle": 3.0, "rig_check": 4.0}[clip]) and anim.loop_mode == Animation.LOOP_LINEAR, "Clip duration and loop: " + clip)
	for part in [npc.body, npc.face, npc.hair]:
		var mesh := mesh_of(part)
		check(mesh.skin != null and mesh.get_node(mesh.skeleton) == rig, "Shared skin binding: " + str(part.name))
		var arrays := mesh.mesh.surface_get_arrays(0)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var valid := true
		for i in range(0, weights.size(), 4):
			valid = valid and absf(weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3] - 1) < .0001
		check(valid and weights.size() > 0, "Every vertex has normalized weights: " + str(part.name))
	var face := mesh_of(npc.face)
	check(face.get_active_material(0).get_shader_parameter("use_expression_uv") == true, "Mouth uses stable rest coordinates under skinning")
	var arrays := face.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var uv_valid := uv2.size() == points.size()
	for i in uv2.size():
		if uv2[i].x < 5:
			uv_valid = uv_valid and absf(uv2[i].x - .5 - points[i].x) < .0001 and absf(uv2[i].y - points[i].y) < .0001
	check(uv_valid, "Expression rest coordinates survive GLB axis/UV conversion")
	var origin := npc.position
	seek(npc, "idle", 0)
	var rests: Array[Transform3D] = []
	for i in rig.get_bone_count():
		rests.append(rig.get_bone_pose(i))
	var rest_body := skin_points(mesh_of(npc.body), rig)
	var rest_face := skin_points(face, rig)
	var rest_hair := skin_points(mesh_of(npc.hair), rig)
	seek(npc, "rig_check", 1.0)
	for bone in ["head", "chest", "upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L", "foot.L", "cape.L", "cape_tip.L", "coat_front.L", "coat_back.L"]:
		var index := rig.find_bone(bone)
		check(index >= 0 and not rig.get_bone_pose(index).is_equal_approx(rests[index]), "Pose animates " + bone)
	for pair in [[npc.body, rest_body], [npc.face, rest_face], [npc.hair, rest_hair]]:
		var posed := skin_points(mesh_of(pair[0]), rig)
		var maximum := 0.0
		for i in posed.size():
			maximum = maxf(maximum, posed[i].distance_to(pair[1][i]))
		check(maximum > .02, "Skin actually deforms " + str(pair[0].name) + " (%.3f m)" % maximum)
	var body_id := npc.body.get_instance_id()
	check(npc.set_hairstyle("swept") and mesh_of(npc.hair).get_node(mesh_of(npc.hair).skeleton) == rig, "Hair swapped during a pose stays on shared skeleton")
	check(npc.set_face(npc.appearance.face_scene) and mesh_of(npc.face).get_node(mesh_of(npc.face).skeleton) == rig, "Face swapped during a pose stays on shared skeleton")
	check(npc.set_expression("smile") and npc.body.get_instance_id() == body_id, "Expressions and identity still work while skinned")
	check(npc.find_children("*", "Skeleton3D", true, false).size() == 1, "Swaps do not accumulate extra skeletons")
	var other := NPC.instantiate() as AdventurerCharacter
	other.animate_idle = false
	root.add_child(other)
	other.hide()
	check(other.skeleton != rig and mesh_of(other.body).mesh == mesh_of(npc.body).mesh, "Characters share mesh data but have independent poses")
	check(other.skeleton.get_bone_pose_rotation(other.skeleton.find_bone("head")).is_equal_approx(Quaternion.IDENTITY), "Another character keeps its neutral head pose")
	seek(npc, "idle", 0)
	var reset := true
	for i in rig.get_bone_count():
		reset = reset and rig.get_bone_pose(i).is_equal_approx(rests[i])
	check(reset, "Returning to idle resets every animated bone")
	check(npc.position == origin, "Rig and animations never translate the stationary NPC")
	for clip in ["idle", "rig_check"]:
		var min_floor := INF
		for time in [0.0, .5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]:
			seek(npc, clip, fmod(time, npc.animation_player.get_animation(clip).length))
			var posed := skin_points(mesh_of(npc.body), rig)
			for point in posed:
				min_floor = minf(min_floor, point.y)
		check(min_floor > -.012, "No ground penetration in " + clip + " (%.6f m)" % min_floor)
	if "--capture" in OS.get_cmdline_user_args():
		world.hud.visible = false
		world.field_weather.controls.visible = false
		world.player.hide()
		npc.rotation.y = 0
		world.camera.position = npc.position + Vector3(-.1, 1.8, 4.8)
		world.camera.look_at(npc.position + Vector3(0, 1.15, 0))
		npc.set_hairstyle("tousled")
		npc.set_expression("neutral")
		seek(npc, "idle", 0)
		await capture("idle")
		seek(npc, "rig_check", 1.0)
		npc.set_expression("smile")
		await capture("pose_left_smile")
		seek(npc, "rig_check", 3.0)
		npc.set_hairstyle("swept")
		npc.set_expression("angry")
		await capture("pose_right_swept")
	other.queue_free()
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
