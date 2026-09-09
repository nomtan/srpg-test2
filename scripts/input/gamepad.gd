class_name GamepadInput
extends RefCounted

const DEADZONE := 0.22
var last_direction := Vector2i.ZERO
var repeat_timer := 0.0

static func stick(right: bool = false) -> Vector2:
	var devices := Input.get_connected_joypads()
	if devices.is_empty(): return Vector2.ZERO
	return read_stick(devices[0], right)

static func read_stick(device: int, right: bool = false) -> Vector2:
	var value := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X if right else JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y if right else JOY_AXIS_LEFT_Y))
	var length := value.length()
	if length <= DEADZONE: return Vector2.ZERO
	return value.normalized() * clampf((length - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)

static func held(button: JoyButton, device: int = -1) -> bool:
	if device >= 0: return Input.is_joy_button_pressed(device, button)
	var devices := Input.get_connected_joypads()
	return not devices.is_empty() and Input.is_joy_button_pressed(devices[0], button)

static func zoom() -> float:
	var devices := Input.get_connected_joypads()
	if devices.is_empty(): return 0.0
	return read_zoom(devices[0])

static func read_zoom(device: int) -> float:
	return maxf(0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) - DEADZONE) - maxf(0, Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) - DEADZONE)

# Translate discrete shortcuts through the existing scene handlers.
static func as_key(event: InputEvent, bindings: Dictionary) -> InputEvent:
	if event is InputEventJoypadButton and bindings.has(event.button_index):
		var key := InputEventKey.new()
		key.keycode = bindings[event.button_index]
		key.pressed = event.pressed
		return key
	return event

func step(delta: float, enabled: bool = true, include_stick: bool = true, device: int = -1) -> Vector2i:
	var value := (read_stick(device) if device >= 0 else stick()) if include_stick else Vector2.ZERO
	if held(JOY_BUTTON_DPAD_LEFT, device): value.x -= 1
	if held(JOY_BUTTON_DPAD_RIGHT, device): value.x += 1
	if held(JOY_BUTTON_DPAD_UP, device): value.y -= 1
	if held(JOY_BUTTON_DPAD_DOWN, device): value.y += 1
	return repeat_direction(value, delta, enabled)

func repeat_direction(value: Vector2, delta: float, enabled: bool = true) -> Vector2i:
	var direction := Vector2i.ZERO
	if enabled and value.length() > 0.35:
		direction = Vector2i(int(signf(value.x)), 0) if absf(value.x) > absf(value.y) else Vector2i(0, int(signf(value.y)))
	repeat_timer -= delta
	if direction == Vector2i.ZERO:
		last_direction = direction
		return Vector2i.ZERO
	if direction != last_direction:
		last_direction = direction
		repeat_timer = 0.32
		return direction
	if repeat_timer <= 0:
		repeat_timer = 0.12
		return direction
	return Vector2i.ZERO
