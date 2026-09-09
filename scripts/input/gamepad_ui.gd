extends Node
## Extend built-in UI actions without replacing the keyboard bindings.

func _ready() -> void:
	for spec in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B], ["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT], ["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = spec[1]
		if not InputMap.action_has_event(spec[0], event):
			InputMap.action_add_event(spec[0], event)
	for spec in [["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0], ["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = spec[1]
		event.axis_value = spec[2]
		if not InputMap.action_has_event(spec[0], event):
			InputMap.action_add_event(spec[0], event)
