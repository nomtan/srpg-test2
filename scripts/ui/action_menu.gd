class_name ActionMenu
extends VBoxContainer

signal attack_selected
signal wait_selected
signal cancel_selected

@onready var attack_button: Button = $AttackButton


func _ready() -> void:
	$AttackButton.pressed.connect(func() -> void: attack_selected.emit())
	$WaitButton.pressed.connect(func() -> void: wait_selected.emit())
	$CancelButton.pressed.connect(func() -> void: cancel_selected.emit())


func open() -> void:
	visible = true
	attack_button.grab_focus()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	var right_click: bool = (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	)
	if visible and (event.is_action_pressed("ui_cancel") or right_click):
		cancel_selected.emit()
		get_viewport().set_input_as_handled()
