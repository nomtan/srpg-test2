class_name BattleCursor
extends Node3D

signal confirm_pressed
signal cancel_pressed
signal grid_position_changed(grid_pos: Vector2i)

enum CursorMode { IDLE, MOVE_TARGETING, ACTION_MENU, ATTACK_TARGETING, COMBAT_CONFIRM, SKILL_MENU, SKILL_TARGETING, SKILL_CONFIRM }

var grid: GridSystem
var camera: Camera3D
var camera_controller: CameraController
var grid_position := Vector2i(3, 3)
var cursor_mesh: MeshInstance3D
var range_root: Node3D
var input_enabled: bool = true
var current_mode: CursorMode = CursorMode.IDLE
var _map_cross_mesh: ArrayMesh
var _range_cross_material: StandardMaterial3D

const _DRAG_THRESHOLD := 6.0
var _mouse_held := false
var _drag_start_pos := Vector2.ZERO
var _dragging := false


func setup(source_grid: GridSystem, source_camera: Camera3D, cam_controller: CameraController = null) -> void:
	grid = source_grid
	camera = source_camera
	camera_controller = cam_controller
	cursor_mesh = _create_highlight(Color(1.0, 0.85, 0.15, 0.75))
	add_child(cursor_mesh)
	range_root = Node3D.new()
	range_root.name = "MoveRange"
	add_child(range_root)
	_update_cursor_visual()


func _process(delta: float) -> void:
	if not camera_controller:
		return
	var pan_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		pan_direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		pan_direction.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		pan_direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pan_direction.y += 1.0
	if not pan_direction.is_zero_approx():
		camera_controller.pan_keyboard(pan_direction.normalized(), delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_mouse_held = true
					_drag_start_pos = event.position
					_dragging = false
				else:
					if not _dragging and input_enabled:
						_update_from_mouse(event.position)
						confirm_pressed.emit()
					_mouse_held = false
					_dragging = false
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				if event.pressed and input_enabled:
					cancel_pressed.emit()
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if camera_controller:
					camera_controller.zoom_camera(1.5)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if camera_controller:
					camera_controller.zoom_camera(-1.5)
					get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		if _mouse_held and not _dragging:
			if event.position.distance_to(_drag_start_pos) > _DRAG_THRESHOLD:
				_dragging = true
		if _dragging and camera_controller:
			camera_controller.orbit_from_mouse(event.relative)
			get_viewport().set_input_as_handled()
		elif not _dragging:
			_update_from_mouse(event.position)
		return

	if _is_key(event, KEY_Q):
		if camera_controller:
			camera_controller.rotate_view(-1)
			get_viewport().set_input_as_handled()
		return
	elif _is_key(event, KEY_E):
		if camera_controller:
			camera_controller.rotate_view(1)
			get_viewport().set_input_as_handled()
		return

	# R/F remain available for keyboard-only elevation adjustments.
	if _is_key(event, KEY_R):
		if camera_controller:
			camera_controller.tilt_view(1)
			get_viewport().set_input_as_handled()
		return
	elif _is_key(event, KEY_F):
		if camera_controller:
			camera_controller.tilt_view(-1)
			get_viewport().set_input_as_handled()
		return

	if not input_enabled:
		return

	var movement := Vector2i.ZERO
	if _is_key(event, KEY_A): movement = Vector2i.LEFT
	elif _is_key(event, KEY_D): movement = Vector2i.RIGHT
	elif _is_key(event, KEY_W): movement = Vector2i.UP
	elif _is_key(event, KEY_S): movement = Vector2i.DOWN

	if movement != Vector2i.ZERO:
		grid_position = Vector2i(
			clampi(grid_position.x + movement.x, 0, GridSystem.WIDTH - 1),
			clampi(grid_position.y + movement.y, 0, GridSystem.DEPTH - 1)
		)
		_update_cursor_visual()
		grid_position_changed.emit(grid_position)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		confirm_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_pressed.emit()
		get_viewport().set_input_as_handled()


func show_reachable(reachable: Dictionary, origin: Vector2i) -> void:
	clear_reachable()
	for grid_pos: Vector2i in reachable:
		if grid_pos == origin:
			continue
		var marker := _create_highlight(Color(0.15, 0.65, 1.0, 0.42))
		marker.position = grid.grid_to_world(grid_pos, 0.025)
		range_root.add_child(marker)
	_add_map_boundary_crosses()

func show_move_range(reachable: Dictionary, origin: Vector2i, danger_cells: Dictionary) -> void:
	clear_reachable()
	for grid_pos: Vector2i in reachable:
		if grid_pos == origin: continue
		var color := Color(0.62, 0.18, 0.85, 0.52) if danger_cells.has(grid_pos) else Color(0.15, 0.65, 1.0, 0.42)
		var marker := _create_highlight(color)
		marker.position = grid.grid_to_world(grid_pos, 0.025)
		range_root.add_child(marker)
	_add_map_boundary_crosses()


func show_attack_range(cells: Array[Vector2i]) -> void:
	clear_reachable()
	for grid_pos in cells:
		var marker := _create_highlight(Color(1.0, 0.2, 0.18, 0.48))
		marker.position = grid.grid_to_world(grid_pos, 0.03)
		range_root.add_child(marker)
	_add_map_boundary_crosses()

func show_skill_range(cells: Array[Vector2i], is_heal: bool) -> void:
	clear_reachable()
	var color := Color(0.2, 0.9, 0.4, 0.48) if is_heal else Color(1.0, 0.2, 0.18, 0.48)
	for grid_pos in cells:
		var marker := _create_highlight(color)
		marker.position = grid.grid_to_world(grid_pos, 0.035)
		range_root.add_child(marker)
	_add_map_boundary_crosses()

func show_skill_area(cells: Array[Vector2i]) -> void:
	clear_reachable()
	for grid_pos in cells:
		var marker := _create_highlight(Color(1.0, 0.86, 0.1, 0.55))
		marker.position = grid.grid_to_world(grid_pos, 0.04)
		range_root.add_child(marker)
	_add_map_boundary_crosses()


func clear_reachable() -> void:
	if not range_root:
		return
	for child in range_root.get_children():
		child.queue_free()


func set_grid_position(grid_pos: Vector2i) -> void:
	grid_position = grid_pos
	_update_cursor_visual()
	grid_position_changed.emit(grid_position)


func _update_cursor_visual() -> void:
	if cursor_mesh:
		cursor_mesh.position = grid.grid_to_world(grid_position, 0.055)


func _update_from_mouse(screen_position: Vector2) -> void:
	if not camera:
		return
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	# 高い面から順に交差させ、その高さを実際の表面に持つ最初のマスを採用する。
	for surface_height in range(GridSystem.MAX_HEIGHT, GridSystem.MIN_HEIGHT - 1, -1):
		var plane := Plane(Vector3.UP, float(surface_height))
		var hit = plane.intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var candidate := grid.world_to_grid(hit)
		if not grid.is_in_bounds(candidate):
			continue
		if grid.get_cell(candidate).height != surface_height:
			continue
		if candidate != grid_position:
			grid_position = candidate
			_update_cursor_visual()
			grid_position_changed.emit(grid_position)
		return


func _create_highlight(color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.86, 0.86)
	instance.mesh = plane
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	instance.material_override = material
	return instance


func _add_map_boundary_crosses() -> void:
	if not _map_cross_mesh:
		_map_cross_mesh = _build_map_cross_mesh()
	if not _range_cross_material:
		_range_cross_material = StandardMaterial3D.new()
		_range_cross_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_range_cross_material.albedo_color = Color(1.0, 0.98, 0.82, 0.5)
		_range_cross_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_range_cross_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_range_cross_material.render_priority = -100

	var instance := MeshInstance3D.new()
	instance.name = "MapGridBoundaryStars"
	instance.mesh = _map_cross_mesh
	instance.material_override = _range_cross_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.sorting_offset = -100.0
	range_root.add_child(instance)


func _build_map_cross_mesh() -> ArrayMesh:
	var cross_positions: Dictionary = {}
	var boundary_edges: Dictionary = {}
	var corner_offsets: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.ONE,
	]
	for grid_pos: Vector2i in grid.cells:
		var cell := grid.get_cell(grid_pos)
		if not cell:
			continue
		var surface_y := grid.grid_to_world(grid_pos, 0.055).y
		for corner_offset in corner_offsets:
			var corner := grid_pos + corner_offset
			var cross_key := Vector3i(corner.x, cell.height, corner.y)
			cross_positions[cross_key] = Vector3(
				float(corner.x) * GridSystem.CELL_SIZE,
				surface_y,
				float(corner.y) * GridSystem.CELL_SIZE
			)
		var cell_corners: Array[Vector2i] = [
			grid_pos,
			grid_pos + Vector2i.RIGHT,
			grid_pos + Vector2i.ONE,
			grid_pos + Vector2i.DOWN,
		]
		for edge_index in 4:
			var edge_start := cell_corners[edge_index]
			var edge_end := cell_corners[(edge_index + 1) % 4]
			if edge_end.x < edge_start.x or (edge_end.x == edge_start.x and edge_end.y < edge_start.y):
				var swapped_start := edge_start
				edge_start = edge_end
				edge_end = swapped_start
			var edge_key := "%d:%d:%d:%d:%d" % [
				edge_start.x, edge_start.y,
				edge_end.x, edge_end.y,
				cell.height,
			]
			boundary_edges[edge_key] = [
				Vector3(
					float(edge_start.x) * GridSystem.CELL_SIZE,
					surface_y,
					float(edge_start.y) * GridSystem.CELL_SIZE
				),
				Vector3(
					float(edge_end.x) * GridSystem.CELL_SIZE,
					surface_y,
					float(edge_end.y) * GridSystem.CELL_SIZE
				),
			]

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for edge_value in boundary_edges.values():
		var edge_points: Array = edge_value
		_append_boundary_line_geometry(
			vertices, normals, indices,
			edge_points[0] as Vector3,
			edge_points[1] as Vector3
		)
	for cross_position: Vector3 in cross_positions.values():
		_append_star_geometry(vertices, normals, indices, cross_position)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_star_geometry(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	origin: Vector3
) -> void:
	const ARM_LENGTH := 0.27
	const CENTER_WIDTH := 0.0467
	var base_index := vertices.size()
	vertices.append(origin)
	vertices.append(origin + Vector3(0.0, 0.0, -ARM_LENGTH))
	vertices.append(origin + Vector3(CENTER_WIDTH, 0.0, -CENTER_WIDTH))
	vertices.append(origin + Vector3(ARM_LENGTH, 0.0, 0.0))
	vertices.append(origin + Vector3(CENTER_WIDTH, 0.0, CENTER_WIDTH))
	vertices.append(origin + Vector3(0.0, 0.0, ARM_LENGTH))
	vertices.append(origin + Vector3(-CENTER_WIDTH, 0.0, CENTER_WIDTH))
	vertices.append(origin + Vector3(-ARM_LENGTH, 0.0, 0.0))
	vertices.append(origin + Vector3(-CENTER_WIDTH, 0.0, -CENTER_WIDTH))
	for _vertex_index in 9:
		normals.append(Vector3.UP)
	for outer_index in 8:
		indices.append(base_index)
		indices.append(base_index + outer_index + 1)
		indices.append(base_index + ((outer_index + 1) % 8) + 1)


func _append_boundary_line_geometry(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	start: Vector3,
	end: Vector3
) -> void:
	const STAR_ARM_LENGTH := 0.27
	const LINE_HALF_WIDTH := 0.012
	var direction := (end - start).normalized()
	var line_start := start + direction * STAR_ARM_LENGTH
	var line_end := end - direction * STAR_ARM_LENGTH
	var perpendicular := Vector3(-direction.z, 0.0, direction.x) * LINE_HALF_WIDTH
	var base_index := vertices.size()
	vertices.append(line_start - perpendicular)
	vertices.append(line_end - perpendicular)
	vertices.append(line_end + perpendicular)
	vertices.append(line_start + perpendicular)
	for _vertex_index in 4:
		normals.append(Vector3.UP)
	indices.append_array(PackedInt32Array([
		base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3,
	]))


func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
