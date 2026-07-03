class_name CameraController
extends Node3D

var camera: Camera3D
# 元の斜め視点と同じ x/y オフセットで z 成分だけ反転。
# カメラをマップ手前 (z<0) に置くことで z=0〜39 全体が正面に収まる。
var focus_offset := Vector3(7.5, 11.7, -9.5)


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	var look_target := Vector3(2.0, 0.8, 2.0)
	camera.position = look_target + focus_offset
	camera.look_at_from_position(camera.position, look_target, Vector3.UP)
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
	var target := unit.global_position
	var destination := target + focus_offset
	var tween := create_tween()
	# アクティブユニットへのフォーカスでは、回転とズームを維持して位置だけを動かす。
	tween.tween_property(camera, "global_position", destination, 0.25)


func pan(screen_delta: Vector2) -> void:
	if not camera: return
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	var scale := camera.size / viewport_height
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	camera.position -= right * screen_delta.x * scale - up * screen_delta.y * scale


func zoom_camera(delta: float) -> void:
	if not camera: return
	camera.size = clampf(camera.size - delta, 5.0, 30.0)
