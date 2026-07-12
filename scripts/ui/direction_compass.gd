class_name DirectionCompass
extends Control

const RADIUS := 48.0
const ARROW_HEAD_LENGTH := 10.0
const NORTH_COLOR := Color("#ff685f")
const CARDINAL_COLOR := Color("#f0eadc")
const AXIS_COLOR := Color("#aeb7c2")

var camera_controller: CameraController


func setup(controller: CameraController) -> void:
	camera_controller = controller
	queue_redraw()


func _process(_delta: float) -> void:
	if camera_controller and camera_controller.camera:
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, 66.0, Color(0.035, 0.045, 0.06, 0.78))
	draw_arc(center, 58.0, 0.0, TAU, 48, Color(0.62, 0.68, 0.75, 0.65), 2.0)

	var north := Vector2(0.0, -1.0)
	var east := Vector2(1.0, 0.0)
	if camera_controller and camera_controller.camera:
		var camera := camera_controller.camera
		var target := camera_controller.focus_target
		var origin_screen := camera.unproject_position(target)
		var north_screen := camera.unproject_position(target + Vector3(0.0, 0.0, -1.0))
		var east_screen := camera.unproject_position(target + Vector3(1.0, 0.0, 0.0))
		if not north_screen.is_equal_approx(origin_screen):
			north = (north_screen - origin_screen).normalized()
		var clockwise := Vector2(-north.y, north.x)
		if not east_screen.is_equal_approx(origin_screen):
			var projected_east := (east_screen - origin_screen).normalized()
			east = clockwise if clockwise.dot(projected_east) >= 0.0 else -clockwise

	_draw_axis(center, north, "N", NORTH_COLOR)
	_draw_axis(center, -north, "S", CARDINAL_COLOR)
	_draw_axis(center, east, "E", CARDINAL_COLOR)
	_draw_axis(center, -east, "W", CARDINAL_COLOR)
	draw_circle(center, 4.0, Color("#d9dee5"))


func _draw_axis(center: Vector2, direction: Vector2, label: String, color: Color) -> void:
	var endpoint := center + direction * RADIUS
	draw_line(center, endpoint, AXIS_COLOR, 3.0, true)
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([
		endpoint,
		endpoint - direction * ARROW_HEAD_LENGTH + side * 6.0,
		endpoint - direction * ARROW_HEAD_LENGTH - side * 6.0,
	]), color)
	var font := ThemeDB.fallback_font
	var font_size := 18
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_center := center + direction * (RADIUS + 14.0)
	draw_string(
		font,
		text_center - Vector2(text_size.x * 0.5, -text_size.y * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)
