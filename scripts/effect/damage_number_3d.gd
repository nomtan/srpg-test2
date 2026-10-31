class_name DamageNumber3D
extends Label3D
## Damage dealt, popping up over the struck unit: it bursts in oversized, settles, floats up
## and a little aside while easing out, then fades. Drawn over everything at a fixed screen size.

const RISE := 0.6
const DRIFT := 0.25
const POP_SIZE := 0.0018
const SETTLED_SIZE := 0.0012
const POP_TIME := 0.07
const SETTLE_TIME := 0.12
const FLOAT_TIME := 0.9
const FADE_TIME := 0.35


func play(amount: int, start: Vector3) -> void:
	text = str(amount)
	font_size = 64
	outline_size = 16
	modulate = Color(1.0, 0.96, 0.84)
	outline_modulate = Color(0.32, 0.1, 0.02, 0.95)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	double_sided = true
	render_priority = 20
	outline_render_priority = 19
	pixel_size = SETTLED_SIZE * 0.4
	global_position = start
	var aside := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized() * DRIFT
	var size := create_tween()
	size.tween_property(self, "pixel_size", POP_SIZE, POP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	size.tween_property(self, "pixel_size", SETTLED_SIZE, SETTLE_TIME).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	var motion := create_tween()
	motion.tween_property(self, "global_position", start + Vector3.UP * RISE + aside, FLOAT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	motion.parallel().tween_property(self, "modulate:a", 0.0, FADE_TIME).set_delay(FLOAT_TIME - FADE_TIME)
	motion.parallel().tween_property(self, "outline_modulate:a", 0.0, FADE_TIME).set_delay(FLOAT_TIME - FADE_TIME)
	motion.finished.connect(queue_free)
