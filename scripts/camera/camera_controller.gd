class_name CameraController
extends Node3D

signal display_state_changed

enum FixedView { NW, WS, SE, EN }

var camera: Camera3D
# 正投影なので、同じ方向のままカメラを遠ざけても表示倍率は変わらない。
# 回転中も40x40マップの端がカメラ背面へ回り込まない距離を確保する。
var focus_offset := Vector3(30.0, 46.8, -38.0)
var focus_target := Vector3.ZERO
var rotation_tween: Tween
var focus_tween: Tween
var fixed_view: FixedView = FixedView.EN

const TILT_STEP_DEGREES := 10.0
const MIN_ELEVATION_DEGREES := 20.0
const MAX_ELEVATION_DEGREES := 45.0
const MOUSE_ORBIT_SENSITIVITY := 0.22
const KEYBOARD_PAN_SPEED_FACTOR := 0.65
const DEFAULT_CAMERA_SIZE := 18.0
const MIN_ZOOM_MULTIPLIER := 0.5
const MAX_ZOOM_MULTIPLIER := 1.2
const FIXED_VIEW_DIRECTIONS: Array[Vector2] = [
	Vector2(-0.70710678, -0.70710678), # NW
	Vector2(-0.70710678, 0.70710678),  # WS
	Vector2(0.70710678, 0.70710678),   # SE
	Vector2(0.70710678, -0.70710678),  # EN
]


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = DEFAULT_CAMERA_SIZE
	camera.far = 350.0
	focus_target = Vector3(3.5, 0.8, 3.5)
	focus_offset = _fixed_view_offset(focus_offset, fixed_view)
	camera.position = focus_target + focus_offset
	camera.look_at_from_position(camera.position, focus_target, Vector3.UP)
	add_child(camera)
	return camera


func pulse_focus() -> void:
	# Battle feedback must not change player-controlled zoom.
	return

func focus_on_unit(unit: BattleUnit) -> void:
	if not camera or not unit: return
	var current_offset := focus_offset
	if current_offset.is_zero_approx():
		current_offset = focus_offset
	focus_offset = current_offset
	focus_target = unit.global_position
	var destination := focus_target + current_offset
	if focus_tween and focus_tween.is_valid():
		focus_tween.kill()
	focus_tween = create_tween()
	focus_tween.tween_property(camera, "global_position", destination, 0.25)
	# アクティブユニットへのフォーカスでは、回転とズームを維持して位置だけを動かす。


func pan(screen_delta: Vector2) -> void:
	if not camera: return
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	var scale := camera.size / viewport_height
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var movement := -right * screen_delta.x * scale + up * screen_delta.y * scale
	camera.position += movement
	focus_target += movement


func pan_keyboard(screen_direction: Vector2, delta: float) -> void:
	if not camera or screen_direction.is_zero_approx():
		return
	_cancel_camera_tweens()
	var right := camera.global_basis.x
	right.y = 0.0
	if not right.is_zero_approx():
		right = right.normalized()
	var screen_up := camera.global_basis.y
	screen_up.y = 0.0
	if not screen_up.is_zero_approx():
		screen_up = screen_up.normalized()
	var speed := camera.size * KEYBOARD_PAN_SPEED_FACTOR
	var movement := (
		right * screen_direction.x
		- screen_up * screen_direction.y
	) * speed * delta
	camera.position += movement
	focus_target += movement


func orbit_from_mouse(relative: Vector2) -> void:
	orbit_view(
		0.0,
		-relative.y * MOUSE_ORBIT_SENSITIVITY
	)


func orbit_view(yaw_degrees: float, pitch_degrees: float = 0.0) -> void:
	if not camera or (is_zero_approx(yaw_degrees) and is_zero_approx(pitch_degrees)):
		return
	_cancel_camera_tweens()
	var offset := camera.position - focus_target
	var horizontal := Vector2(offset.x, offset.z)
	if horizontal.is_zero_approx():
		return
	var radius := offset.length()
	var elevation := rad_to_deg(atan2(offset.y, horizontal.length()))
	var target_elevation := clampf(
		elevation + pitch_degrees,
		MIN_ELEVATION_DEGREES,
		MAX_ELEVATION_DEGREES
	)
	var horizontal_direction := horizontal.normalized().rotated(deg_to_rad(yaw_degrees))
	var elevation_radians := deg_to_rad(target_elevation)
	var horizontal_radius := cos(elevation_radians) * radius
	var target_offset := Vector3(
		horizontal_direction.x * horizontal_radius,
		sin(elevation_radians) * radius,
		horizontal_direction.y * horizontal_radius
	)
	focus_offset = target_offset
	_apply_orbit_offset(target_offset, focus_target)
	fixed_view = _nearest_fixed_view(target_offset)


func rotate_view(direction: int) -> void:
	if not camera or direction == 0:
		return
	var start_offset := camera.position - focus_target
	# Positive switches clockwise (EN -> SE -> WS -> NW); negative reverses it.
	fixed_view = posmod(int(fixed_view) - direction, FIXED_VIEW_DIRECTIONS.size())
	# Keep the configured radius even when another key is pressed mid-transition.
	var target_offset := _fixed_view_offset(focus_offset, fixed_view)
	_start_orbit_tween(start_offset, target_offset)


func _fixed_view_offset(source_offset: Vector3, view: FixedView) -> Vector3:
	var horizontal_radius := Vector2(source_offset.x, source_offset.z).length()
	var direction := FIXED_VIEW_DIRECTIONS[int(view)]
	return Vector3(
		direction.x * horizontal_radius,
		source_offset.y,
		direction.y * horizontal_radius
	)


func _nearest_fixed_view(offset: Vector3) -> FixedView:
	var horizontal := Vector2(offset.x, offset.z)
	if horizontal.is_zero_approx():
		return fixed_view
	var direction := horizontal.normalized()
	var nearest_index := 0
	var nearest_dot := -INF
	for view_index in FIXED_VIEW_DIRECTIONS.size():
		var view_dot := direction.dot(FIXED_VIEW_DIRECTIONS[view_index])
		if view_dot > nearest_dot:
			nearest_dot = view_dot
			nearest_index = view_index
	return nearest_index


func tilt_view(direction: int) -> void:
	if not camera or direction == 0:
		return
	var start_offset := camera.position - focus_target
	var horizontal := Vector2(start_offset.x, start_offset.z)
	if horizontal.is_zero_approx():
		return
	var radius := start_offset.length()
	var elevation := rad_to_deg(atan2(start_offset.y, horizontal.length()))
	var target_elevation := clampf(
		elevation + TILT_STEP_DEGREES * float(direction),
		MIN_ELEVATION_DEGREES,
		MAX_ELEVATION_DEGREES
	)
	if is_equal_approx(target_elevation, elevation):
		return
	var elevation_radians := deg_to_rad(target_elevation)
	var horizontal_direction := horizontal.normalized()
	var horizontal_radius := cos(elevation_radians) * radius
	var target_offset := Vector3(
		horizontal_direction.x * horizontal_radius,
		sin(elevation_radians) * radius,
		horizontal_direction.y * horizontal_radius
	)
	_start_orbit_tween(start_offset, target_offset)


func _start_orbit_tween(start_offset: Vector3, target_offset: Vector3) -> void:
	if rotation_tween and rotation_tween.is_valid():
		rotation_tween.kill()
	focus_offset = target_offset
	rotation_tween = create_tween()
	rotation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	rotation_tween.tween_method(
		_apply_orbit_offset.bind(focus_target),
		start_offset,
		target_offset,
		0.3
	)


func _cancel_camera_tweens() -> void:
	if rotation_tween and rotation_tween.is_valid():
		rotation_tween.kill()
	if focus_tween and focus_tween.is_valid():
		focus_tween.kill()


func _apply_orbit_offset(offset: Vector3, target: Vector3) -> void:
	if not camera:
		return
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)
	display_state_changed.emit()


func zoom_camera(delta: float) -> void:
	if not camera: return
	var minimum_size := DEFAULT_CAMERA_SIZE / MAX_ZOOM_MULTIPLIER
	var maximum_size := DEFAULT_CAMERA_SIZE / MIN_ZOOM_MULTIPLIER
	camera.size = clampf(camera.size - delta, minimum_size, maximum_size)
	display_state_changed.emit()


func get_fixed_view_name() -> String:
	if camera:
		return FixedView.keys()[int(_nearest_fixed_view(camera.position - focus_target))]
	return FixedView.keys()[int(fixed_view)]


func get_azimuth_degrees() -> float:
	if not camera:
		return 0.0
	var offset := camera.position - focus_target
	return fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)


func get_elevation_degrees() -> float:
	if not camera:
		return 0.0
	var offset := camera.position - focus_target
	var horizontal_length := Vector2(offset.x, offset.z).length()
	return rad_to_deg(atan2(offset.y, horizontal_length))


func get_zoom_multiplier() -> float:
	if not camera or is_zero_approx(camera.size):
		return 1.0
	return DEFAULT_CAMERA_SIZE / camera.size
