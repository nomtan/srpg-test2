extends SceneTree
## Headless geometry checks; add -- --render to compare actual frame times.
const Vegetation = preload("res://scripts/world_jrpg/natural_vegetation.gd")
const World = preload("res://scripts/world_jrpg/world.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	for kind in ["oak", "pine", "grass", "reed"]:
		for variant in 3:
			var plants := Vegetation.new()
			for i in 7:
				plants.plant(kind, Vector3(90 + i, 4, 70), 1.2, i * 0.7, variant)
			plants.commit(parent)
	var valid := true
	for node: MultiMeshInstance3D in parent.get_children():
		if "_lod" in node.name: continue
		var middle: MultiMeshInstance3D = parent.get_node(str(node.name) + "_lod1")
		var near_mesh: Mesh = node.multimesh.mesh
		var mid_mesh: Mesh = middle.multimesh.mesh
		valid = valid and mid_mesh.surface_get_array_len(0) < near_mesh.surface_get_array_len(0) * 0.5
		valid = valid and node.multimesh.custom_aabb == middle.multimesh.custom_aabb
		valid = valid and node.visibility_range_end == middle.visibility_range_begin
		valid = valid and middle.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		valid = valid and near_mesh.surface_get_material(0) == mid_mesh.surface_get_material(0)
		for i in middle.multimesh.instance_count:
			var stride := 2 if "grass" in node.name or "reed" in node.name else 1
			valid = valid and middle.multimesh.get_instance_transform(i) == node.multimesh.get_instance_transform(i * stride)
		if "oak" in node.name or "pine" in node.name:
			var far_node: MultiMeshInstance3D = parent.get_node(str(node.name) + "_lod2")
			valid = valid and far_node.multimesh.mesh.surface_get_array_len(0) < near_mesh.surface_get_array_len(0) * 0.15
			valid = valid and far_node.multimesh.custom_aabb == node.multimesh.custom_aabb
			valid = valid and middle.visibility_range_end == far_node.visibility_range_begin and far_node.visibility_range_end == 0
			valid = valid and far_node.multimesh.mesh.surface_get_material(0) == near_mesh.surface_get_material(0)
		print(node.name, " triangles: ", near_mesh.surface_get_array_len(0) / 3, " -> ", mid_mesh.surface_get_array_len(0) / 3)
	check(valid, "LOD budgets, shared weather/cutaway materials, placements and gap-free ranges")
	parent.free()
	if "--render" in OS.get_cmdline_user_args() and not failed:
		await _render_comparison()
	quit(1 if failed else 0)

func _render_comparison() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/vegetation-lod")
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.field_weather.apply_conditions(1, 0)
	var nodes := world.find_children("Natural_*", "MultiMeshInstance3D", true, false)
	var ranges: Dictionary = {}
	for node in nodes: ranges[node] = Vector2(node.visibility_range_begin, node.visibility_range_end)
	for preset in [4, 3, 1]:
		world._preset(preset)
		for baseline in [true, false]:
			for node in nodes:
				node.visible = not baseline or not "_lod" in node.name
				node.visibility_range_begin = 0.0 if baseline else ranges[node].x
				node.visibility_range_end = (85.0 if "grass" in node.name or "reed" in node.name else 0.0) if baseline else ranges[node].y
			for frame in 45: await process_frame
			var start := Time.get_ticks_usec()
			for frame in 90: await process_frame
			var milliseconds := float(Time.get_ticks_usec() - start) / 90000.0
			print("RENDER preset=", preset, " baseline=", baseline, " ms/frame=", milliseconds,
				" primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			await RenderingServer.frame_post_draw
			var path := "res://.godot/vegetation-lod/view_%d_%s.png" % [preset, "before" if baseline else "after"]
			check(root.get_texture().get_image().save_png(path) == OK, "Capture " + path)
