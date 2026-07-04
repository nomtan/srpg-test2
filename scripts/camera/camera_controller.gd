class_name CameraController
extends Node3D

var camera: Camera3D
# 元の斜め視点と同じ x/y オフセットで z 成分だけ反転。
# カメラをマップ手前 (z<0) に置くことで z=0〜39 全体が正面に収まる。
var focus_offset := Vector3(7.5, 11.7, -9.5)
var focus_target := Vector3.ZERO
var rotation_tween: Tween


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	focus_target = Vector3(2.0, 0.8, 2.0)
	camera.position = focus_target + focus_offset
	camera.look_at_from_position(camera.position, focus_target, Vector3.UP)
	add_child(camera)
	return camera


func pulse_focus() -> void:
	if not camera: return
	var tween := create_tween()
	tween.tween_property(camera, "size", 16.0, 0.15)
	tween.tween_interval(0.25)
	tween.tween_property(camera, "size", 18.0, 0.2)

func focus_on_unit(unit: BattleUnit) -> void:
	if not camera or not unit: return
	focus_target = unit.global_position
	var destination := focus_target + focus_offset
	var tween := create_tween()
	# アクティブユニットへのフォーカスでは、回転とズームを維持して位置だけを動かす。
	tween.tween_property(camera, "global_position", destination, 0.25)


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
	if rotation_tween and rotation_tween.is_valid():
		rotation_tween.kill()
	var start_offset := camera.position - focus_target
	var angle := deg_to_rad(90.0 * float(direction))
	focus_offset = start_offset.rotated(Vector3.UP, angle)
	rotation_tween = create_tween()
	rotation_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	rotation_tween.tween_method(
		_apply_orbit_rotation.bind(start_offset, focus_target),
		0.0,
		angle,
		0.3
	)


func _apply_orbit_rotation(angle: float, start_offset: Vector3, target: Vector3) -> void:
	if not camera:
		return
	camera.position = target + start_offset.rotated(Vector3.UP, angle)
	camera.look_at(target, Vector3.UP)


func zoom_camera(delta: float) -> void:
	if not camera: return
	camera.size = clampf(camera.size - delta, 5.0, 30.0)
