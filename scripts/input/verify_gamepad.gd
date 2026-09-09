extends SceneTree

var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
	else: print("PASS: ", message)

func axis(which: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 15
	event.axis = which
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	axis(JOY_AXIS_LEFT_X, 0.15)
	check(GamepadInput.read_stick(15).is_zero_approx(), "stick drift ignored")
	axis(JOY_AXIS_LEFT_X, 0.6)
	check(GamepadInput.read_stick(15).x > 0 and GamepadInput.read_stick(15).x < 1, "analog walking magnitude preserved")
	axis(JOY_AXIS_RIGHT_Y, -1)
	check(GamepadInput.read_stick(15, true).y == -1 and GamepadInput.read_stick(15).y == 0, "left and right sticks independent")
	var pad := GamepadInput.new()
	check(pad.repeat_direction(GamepadInput.read_stick(15), 0.016) == Vector2i.RIGHT, "immediate grid movement")
	check(pad.repeat_direction(GamepadInput.read_stick(15), 0.1) == Vector2i.ZERO, "initial repeat delay")
	check(pad.repeat_direction(GamepadInput.read_stick(15), 0.23) == Vector2i.RIGHT, "held stick repeats")
	check(pad.repeat_direction(GamepadInput.read_stick(15), 0.2, false) == Vector2i.ZERO, "menu and busy state suppress grid movement")
	axis(JOY_AXIS_LEFT_X, -1)
	check(pad.repeat_direction(GamepadInput.read_stick(15), 0.016) == Vector2i.LEFT, "direction reversal responds immediately")
	axis(JOY_AXIS_TRIGGER_RIGHT, 1)
	check(GamepadInput.read_zoom(15) > 0, "right trigger zooms in")
	axis(JOY_AXIS_TRIGGER_LEFT, 1)
	check(is_zero_approx(GamepadInput.read_zoom(15)), "opposing zoom triggers cancel")
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	check(button.is_action_pressed("ui_accept"), "native menu accepts gamepad A")
	check(GamepadInput.as_key(button, {JOY_BUTTON_A: KEY_ENTER}).is_action_pressed("ui_accept"), "confirm mapping")
	button.pressed = false
	check(not GamepadInput.as_key(button, {JOY_BUTTON_A: KEY_ENTER}).is_action_pressed("ui_accept"), "button release does not confirm")
	check(GamepadInput.stick() == Vector2.ZERO and GamepadInput.zoom() == 0, "no controller means no movement or zoom")
	quit(1 if failed else 0)
