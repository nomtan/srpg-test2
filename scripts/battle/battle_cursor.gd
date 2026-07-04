class_name BattleCursor
extends Node3D

signal confirm_pressed
signal cancel_pressed
signal grid_position_changed(grid_pos: Vector2i)

enum CursorMode { IDLE, MOVE_TARGETING, ACTION_MENU, ATTACK_TARGETING, COMBAT_CONFIRM, SKILL_MENU, SKILL_TARGETING, SKILL_CONFIRM }

var grid: GridSystem
var camera: Camera3D
var camera_controller: CameraController
var grid_position := Vector2i(1, 1)
var cursor_mesh: MeshInstance3D
var range_root: Node3D
var input_enabled: bool = true
var current_mode: CursorMode = CursorMode.IDLE

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
			camera_controller.pan(event.relative)
			get_viewport().set_input_as_handled()
		elif input_enabled:
			_update_from_mouse(event.position)
		return

	# Q/E rotate the quarter view even while cursor actions are disabled.
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

	if not input_enabled:
		return

	var movement := Vector2i.ZERO
	if event.is_action_pressed("ui_left") or _is_key(event, KEY_A): movement = Vector2i.LEFT
	elif event.is_action_pressed("ui_right") or _is_key(event, KEY_D): movement = Vector2i.RIGHT
	elif event.is_action_pressed("ui_up") or _is_key(event, KEY_W): movement = Vector2i.UP
	elif event.is_action_pressed("ui_down") or _is_key(event, KEY_S): movement = Vector2i.DOWN

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

func show_move_range(reachable: Dictionary, origin: Vector2i, danger_cells: Dictionary) -> void:
	clear_reachable()
	for grid_pos: Vector2i in reachable:
		if grid_pos == origin: continue
		var color := Color(0.62, 0.18, 0.85, 0.52) if danger_cells.has(grid_pos) else Color(0.15, 0.65, 1.0, 0.42)
		var marker := _create_highlight(color)
		marker.position = grid.grid_to_world(grid_pos, 0.025)
		range_root.add_child(marker)


func show_attack_range(cells: Array[Vector2i]) -> void:
	clear_reachable()
	for grid_pos in cells:
		var marker := _create_highlight(Color(1.0, 0.2, 0.18, 0.48))
		marker.position = grid.grid_to_world(grid_pos, 0.03)
		range_root.add_child(marker)

func show_skill_range(cells: Array[Vector2i], is_heal: bool) -> void:
	clear_reachable()
	var color := Color(0.2, 0.9, 0.4, 0.48) if is_heal else Color(1.0, 0.2, 0.18, 0.48)
	for grid_pos in cells:
		var marker := _create_highlight(color)
		marker.position = grid.grid_to_world(grid_pos, 0.035)
		range_root.add_child(marker)

func show_skill_area(cells: Array[Vector2i]) -> void:
	clear_reachable()
	for grid_pos in cells:
		var marker := _create_highlight(Color(1.0, 0.86, 0.1, 0.55))
		marker.position = grid.grid_to_world(grid_pos, 0.04)
		range_root.add_child(marker)


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
	for surface_height in range(3, 0, -1):
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


func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode
