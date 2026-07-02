class_name CameraController
extends Node3D

var camera: Camera3D
var focus_offset := Vector3(7.5, 11.7, 9.5)


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(9.5, 12.5, 11.5)
	focus_offset = camera.position - Vector3(2.0, 0.8, 2.0)
	camera.look_at_from_position(camera.position, Vector3(2.0, 0.8, 2.0), Vector3.UP)
	add_child(camera)
	return camera


func pulse_focus() -> void:
	if not camera: return
	var tween := create_tween()
	tween.tween_property(camera, "size", 12.0, 0.15)
	tween.tween_interval(0.25)
	tween.tween_property(camera, "size", 14.0, 0.2)

func focus_on_unit(unit: BattleUnit) -> void:
	if not camera or not unit: return
	var target := unit.global_position
	var destination := target + focus_offset
	var start := camera.global_position
	var tween := create_tween()
	tween.tween_method(func(weight: float) -> void:
		camera.look_at_from_position(start.lerp(destination, weight), target, Vector3.UP), 0.0, 1.0, 0.25)


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
