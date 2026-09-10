extends Node3D
## Phase 5 Godot import test for Character Builder "Export for Godot" output.
## Loads the newest .glb in res://test/exports/ (falls back to the shipped explorer base),
## reads the sibling <name>.character.json for the animation mapping, and plays back
## idle / run / attack. Standalone: does not touch Main.tscn or gameplay scripts.
##
## Keys:  1 = idle   2 = run   3 = attack   R = reload   TAB = cycle raw clips

const EXPORT_DIR := "res://test/exports"
const FALLBACK_GLB := "res://assets/world_jrpg/explorer_base_1.glb"
## Explorer reference height (base_1.bbmodel * 1/12), used only for the scale read-out.
const REFERENCE_HEIGHT_M := 1.845

var _model: Node3D
var _anim: AnimationPlayer
var _mapping := {}
var _active_set := "default"
var _clip_names: PackedStringArray = []
var _clip_cycle := 0
var _status: Label
var _source_label := ""

func _ready() -> void:
	_build_environment()
	_load_character()

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.11, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.6
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.4
	add_child(light)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	add_child(cam)
	cam.look_at_from_position(Vector3(2.2, 1.6, 3.4), Vector3(0, 1.0, 0))

	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override("font_size", 18)
	var layer := CanvasLayer.new()
	layer.add_child(_status)
	add_child(layer)

func _load_character() -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	_anim = null
	_mapping.clear()
	_active_set = "default"
	_clip_names = []

	var path := _newest_export()
	var used_fallback := false
	if path.is_empty():
		path = FALLBACK_GLB
		used_fallback = true

	_model = _instantiate_glb(path)
	if _model == null:
		_set_status("FAILED to load: %s" % path)
		push_error("character_export_test: could not load %s" % path)
		return
	add_child(_model)
	_source_label = path.get_file()

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		_clip_names = _anim.get_animation_list()
		for clip_name in _clip_names:
			var a := _anim.get_animation(clip_name)
			if a and (clip_name.ends_with("idle") or clip_name.ends_with("run") or clip_name == "idle" or clip_name == "run" or clip_name.ends_with("walk_mcp_test") or clip_name == "walk"):
				a.loop_mode = Animation.LOOP_LINEAR

	_load_mapping(path)
	_play_role("idle")
	_report(path, used_fallback)

func _newest_export() -> String:
	var dir := DirAccess.open(EXPORT_DIR)
	if dir == null:
		return ""
	var best := ""
	var best_time := -1
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.get_extension().to_lower() == "glb":
			var full := "%s/%s" % [EXPORT_DIR, file]
			var t := int(FileAccess.get_modified_time(full))
			if t >= best_time:
				best_time = t
				best = full
		file = dir.get_next()
	dir.list_dir_end()
	return best

func _instantiate_glb(path: String) -> Node3D:
	# Prefer Godot's imported PackedScene (keeps import-dock settings); fall back to a
	# runtime glTF parse for a file that was only just dropped in and not reimported.
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return (res as PackedScene).instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, path.get_base_dir(), state)
	if err != OK:
		push_error("GLTFDocument.append_from_buffer failed (%s) for %s" % [err, path])
		return null
	var scene := doc.generate_scene(state)
	return scene as Node3D

func _load_mapping(glb_path: String) -> void:
	var json_path := glb_path.get_basename() + ".character.json"
	if not FileAccess.file_exists(json_path):
		# Editor-imported glb: sibling json is next to the source file.
		json_path = glb_path.get_base_dir() + "/" + glb_path.get_file().get_basename() + ".character.json"
	if not FileAccess.file_exists(json_path):
		return
	var text := FileAccess.get_file_as_string(json_path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_mapping = data.get("animations", {})
	_active_set = str(data.get("activeAnimationSet", "default"))

func _resolve_clip(role: String) -> String:
	for set_key in [_active_set, "default"]:
		var set_map: Variant = _mapping.get(set_key, {})
		if typeof(set_map) == TYPE_DICTIONARY and set_map.has(role):
			var clip := str(set_map[role])
			if _anim and _anim.has_animation(clip):
				return clip
	# Heuristic fallback (also covers the explorer base glb, which has no json).
	for clip_name in _clip_names:
		if clip_name == role or clip_name.ends_with("_" + role) or clip_name.ends_with("." + role):
			return clip_name
	if role == "attack":
		return _resolve_clip("run")
	if role == "run":
		for clip_name in _clip_names:
			if clip_name.ends_with("walk_mcp_test") or clip_name == "walk":
				return clip_name
	return _clip_names[0] if _clip_names.size() > 0 else ""

func _play_role(role: String) -> void:
	if _anim == null:
		_set_status("%s\nNo AnimationPlayer in GLB." % _source_label)
		return
	var clip := _resolve_clip(role)
	if clip.is_empty():
		_set_status("%s\nNo clip for '%s'." % [_source_label, role])
		return
	_anim.play(clip, 0.15)
	_set_status("%s\n[1]idle [2]run [3]attack  R=reload  TAB=raw\nrole=%s  clip=%s  set=%s" % [_source_label, role, clip, _active_set])

func _report(path: String, used_fallback: bool) -> void:
	var aabb := _visible_aabb(_model)
	var h := aabb.size.y
	var delta := h - REFERENCE_HEIGHT_M
	print("--- character_export_test ---")
	print("  source: %s%s" % [path, "  (FALLBACK)" if used_fallback else ""])
	print("  meshes: %d   materials: %d" % [_count_meshes(_model), _count_materials(_model)])
	print("  animations: %s" % [", ".join(_clip_names)])
	print("  AABB size (m): %.3f x %.3f x %.3f" % [aabb.size.x, aabb.size.y, aabb.size.z])
	print("  height %.3f m vs explorer base %.3f m (Δ %.3f m, %.1f%%)" % [h, REFERENCE_HEIGHT_M, delta, 100.0 * delta / REFERENCE_HEIGHT_M])
	if h < 0.8 or h > 3.0:
		push_warning("Exported character height %.3f m is outside 0.8-3.0 m" % h)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1: _play_role("idle")
		KEY_2: _play_role("run")
		KEY_3: _play_role("attack")
		KEY_R: _load_character()
		KEY_TAB:
			if _anim and _clip_names.size() > 0:
				_clip_cycle = (_clip_cycle + 1) % _clip_names.size()
				var clip := _clip_names[_clip_cycle]
				_anim.play(clip, 0.1)
				_set_status("%s\nraw clip %d/%d: %s" % [_source_label, _clip_cycle + 1, _clip_names.size(), clip])

func _set_status(text: String) -> void:
	if _status:
		_status.text = text

# --- small scene helpers -----------------------------------------------------
func _visible_aabb(node: Node) -> AABB:
	var out := AABB()
	var started := false
	for inst in _all_visual_instances(node):
		var vi := inst as VisualInstance3D
		var world: AABB = vi.global_transform * vi.get_aabb()
		if not started:
			out = world
			started = true
		else:
			out = out.merge(world)
	return out

func _all_visual_instances(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node as VisualInstance3D)
	for child in node.get_children():
		found.append_array(_all_visual_instances(child))
	return found

func _count_meshes(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		n += 1
	for child in node.get_children():
		n += _count_meshes(child)
	return n

func _count_materials(node: Node) -> int:
	var mats := {}
	for inst in _all_visual_instances(node):
		if inst is MeshInstance3D:
			var mi := inst as MeshInstance3D
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					var m := mi.get_active_material(i)
					if m:
						mats[m.get_instance_id()] = true
	return mats.size()
