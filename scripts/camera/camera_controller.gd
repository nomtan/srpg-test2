class_name CameraController
extends Node3D

var camera: Camera3D
# 正投影なので、同じ方向のままカメラを遠ざけても表示倍率は変わらない。
# 回転中も40x40マップの端がカメラ背面へ回り込まない距離を確保する。
var focus_offset := Vector3(30.0, 46.8, -38.0)
var focus_target := Vector3.ZERO
var rotation_tween: Tween
var focus_tween: Tween

const TILT_STEP_DEGREES := 10.0
const MIN_ELEVATION_DEGREES := 20.0
const MAX_ELEVATION_DEGREES := 75.0


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	camera.far = 350.0
	focus_target = Vector3(3.5, 0.8, 3.5)
	camera.position = focus_target + focus_offset
	camera.look_at_from_position(camera.position, focus_target, Vector3.UP)
	add_child(camera)
	return camera


func pulse_focus() -> void:
	# Battle feedback must not change player-controlled zoom.
	return

func focus_on_unit(unit: BattleUnit) -> void:
	if not camera or not unit: return
	var current_offset := camera.global_position - focus_target
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


func rotate_view(direction: int) -> void:
	if not camera or direction == 0:
		return
	var start_offset := camera.position - focus_target
	var angle := deg_to_rad(90.0 * float(direction))
	var target_offset := start_offset.rotated(Vector3.UP, angle)
	_start_orbit_tween(start_offset, target_offset)


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


func _apply_orbit_offset(offset: Vector3, target: Vector3) -> void:
	if not camera:
		return
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)


func zoom_camera(delta: float) -> void:
	if not camera: return
	camera.size = clampf(camera.size - delta, 5.0, 96.0)
