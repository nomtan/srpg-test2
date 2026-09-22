extends SceneTree
## Directly load the delivered GLBs, avoiding existing project import hooks.
const SOURCES := {
	"adventure": "res://assets/characters/tripo_adventure/prepared/phase1/",
	"knight": "res://assets/characters/tripo_knight2/prepared/phase1/",
	"black_mage": "res://assets/characters/tripo_black_mage/prepared/phase1/"
}
var failed := false
var results := {}

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failed = true

func glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	check(error == OK, "GLB import " + path)
	return doc.generate_scene(state) as Node3D

func descendants(node: Node, type: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type): found.append(node)
	for child in node.get_children(): found.append_array(descendants(child, type))
	return found

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var library_scene := glb("res://assets/characters/_shared/animations/common_combat.glb")
	root.add_child(library_scene)
	library_scene.print_tree_pretty()
	var players := descendants(library_scene, "AnimationPlayer")
	check(players.size() == 1, "shared animation player exists")
	if players.is_empty():
		quit(1)
		return
	var shared_player := players[0] as AnimationPlayer
	var library := shared_player.get_animation_library("")
	for clip in ["idle", "walk", "attack_melee", "cast_magic", "hit"]:
		check(library.has_animation(clip), "shared clip " + clip)
		if clip in ["idle", "walk"]:
			library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var reference: Skeleton3D
	var shader := load("res://assets/characters/_shared/phase1_palette.gdshader") as Shader
	check(shader != null, "palette/emblem shader loaded")
	for key: String in SOURCES:
		var model := glb(SOURCES[key] + "body.glb")
		root.add_child(model)
		var skeletons := descendants(model, "Skeleton3D")
		check(skeletons.size() == 1, key + " has one skeleton")
		if skeletons.is_empty(): continue
		var skeleton := skeletons[0] as Skeleton3D
		check(skeleton.get_bone_count() == 26, key + " 26 bones")
		if reference:
			for index in range(26):
				check(skeleton.get_bone_name(index) == reference.get_bone_name(index)
					and skeleton.get_bone_parent(index) == reference.get_bone_parent(index)
					and skeleton.get_bone_rest(index).is_equal_approx(reference.get_bone_rest(index)),
					key + " shared bind " + str(index))
		else:
			reference = skeleton
		var player := AnimationPlayer.new()
		model.add_child(player)
		player.root_node = NodePath("..")
		# One library resource is attached to every player; no Animation duplication.
		for clip: StringName in library.get_animation_list():
			var animation := library.get_animation(clip)
			for track in range(animation.get_track_count()):
				var old := animation.track_get_path(track)
				if old.get_subname_count() > 0:
					animation.track_set_path(track, NodePath(str(model.get_path_to(skeleton)) + ":" + str(old.get_subname(0))))
		player.add_animation_library("", library)
		var root_index := skeleton.find_bone("Root")
		var head_index := skeleton.find_bone("Head")
		var motions := {}
		for clip in ["idle", "walk", "attack_melee", "cast_magic", "hit"]:
			player.play(clip)
			player.seek(0.0, true)
			player.advance(0)
			var initial := skeleton.get_bone_global_pose(head_index)
			var initial_bones: Array[Transform3D] = []
			for index in skeleton.get_bone_count(): initial_bones.append(skeleton.get_bone_global_pose(index))
			player.seek(player.current_animation_length * 0.25, true)
			player.advance(0)
			skeleton.force_update_all_bone_transforms()
			check(skeleton.get_bone_pose_position(root_index).length() < 0.00001, key + " in-place " + clip)
			check(player.get_animation(clip) == library.get_animation(clip), key + " reuses " + clip)
			var moved := 0
			for index in skeleton.get_bone_count():
				if not initial_bones[index].is_equal_approx(skeleton.get_bone_global_pose(index)): moved += 1
			check(moved > 0, key + " actually animates " + clip)
			motions[clip] = {"moving_bones": moved, "head_moved": not initial.is_equal_approx(skeleton.get_bone_global_pose(head_index))}
		player.pause()
		# Imported BoneAttachments receive their first deferred skeleton update
		# after the process-frame signal. Allow initialization to settle first.
		await process_frame
		await process_frame
		var sockets := {}
		for label in ["HeadSocket", "WeaponSocket_R", "WeaponSocket_L"]:
			sockets[label] = model.find_child(label, true, false) != null
			check(sockets[label], key + " socket " + label)
			var node := model.find_child(label,true,false) as Node3D
			var bone: String = {"HeadSocket":"Head", "WeaponSocket_R":"Hand_R", "WeaponSocket_L":"Hand_L"}[label]
			await process_frame
			var expected_transform := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
			if not node.global_transform.is_equal_approx(expected_transform):
				print("SOCKET_DIAGNOSTIC ", key, " ", label, " actual=", node.global_transform, " expected=", expected_transform)
			check(node.global_transform.is_equal_approx(expected_transform), key + " socket bone frame " + label)
		for other: String in SOURCES:
			if other == key: continue
			var head := glb(SOURCES[other] + "head_default.glb")
			check(descendants(head, "Skeleton3D").is_empty(), other + " rigid head has no extra skeleton")
			var socket := model.find_child("HeadSocket",true,false) as Node3D
			socket.add_child(head)
			player.play("cast_magic")
			player.seek(0.4, true)
			player.advance(0)
			player.pause()
			skeleton.force_update_all_bone_transforms()
			await process_frame
			check(socket.global_transform.is_equal_approx(skeleton.global_transform * skeleton.get_bone_global_pose(head_index)), key + " follows swapped " + other)
			head.free()
		for node in descendants(model, "MeshInstance3D"):
			var mesh := node as MeshInstance3D
			var base := mesh.get_active_material(0) as StandardMaterial3D
			check(base != null and base.albedo_texture != null, key + " original albedo imported")
			var material := ShaderMaterial.new()
			material.shader = shader
			material.set_shader_parameter("base_color_texture", base.albedo_texture)
			var mask := Image.load_from_file(ProjectSettings.globalize_path(SOURCES[key] + "palette_mask.png"))
			check(not mask.is_empty(), key + " palette mask imported")
			var counts := [0, 0]
			for y in mask.get_height():
				for x in mask.get_width():
					var color := mask.get_pixel(x,y)
					if color.r > 0.5: counts[0] += 1
					if color.g > 0.5: counts[1] += 1
			check(counts[0] > 100 and counts[1] > 100, key + " independent primary/secondary")
			material.set_shader_parameter("palette_mask", ImageTexture.create_from_image(mask))
			material.set_shader_parameter("palette_enabled", true)
			mesh.material_override = material
		results[key] = {"clips": motions, "sockets": sockets, "bones": skeleton.get_bone_count()}
	await process_frame
	var file := FileAccess.open("res://artifacts/character_phase1/godot_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": not failed, "characters": results}, "  "))
	print("PHASE1_GODOT_COMPLETE ", not failed)
	quit(1 if failed else 0)
