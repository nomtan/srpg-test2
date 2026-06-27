class_name FloatingNumber3D
extends Label3D

func play(value_text: String, start_position: Vector3, number_type: String) -> void:
	text = value_text
	global_position = start_position + Vector3(0, 1.4, 0)
	font_size = 64
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	double_sided = true
	render_priority = 10
	outline_size = 12
	outline_modulate = Color(0.05, 0.05, 0.05, 0.95)
	modulate = {"damage": Color("#ff4b4b"), "heal": Color("#55ef88"), "miss": Color.WHITE}.get(number_type, Color.WHITE)
	var tween := create_tween()
	tween.tween_property(self, "global_position", global_position + Vector3(0, 0.9, 0), 0.85)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.85)
	tween.finished.connect(queue_free)
