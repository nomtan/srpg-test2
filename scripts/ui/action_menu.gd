class_name ActionMenu
extends VBoxContainer

signal attack_selected
signal wait_selected
signal cancel_selected
signal skill_selected
signal move_selected

@onready var attack_button: Button = $AttackButton
@onready var move_button: Button = $MoveButton
@onready var skill_button: Button = $SkillButton


func _ready() -> void:
	$AttackButton.pressed.connect(func() -> void: attack_selected.emit())
	$WaitButton.pressed.connect(func() -> void: wait_selected.emit())
	$CancelButton.pressed.connect(func() -> void: cancel_selected.emit())
	$SkillButton.pressed.connect(func() -> void: skill_selected.emit())
	$MoveButton.pressed.connect(func() -> void: move_selected.emit())


func open(unit: BattleUnit = null) -> void:
	visible = true
	if unit:
		move_button.disabled = unit.has_moved
		attack_button.disabled = unit.has_used_action
		skill_button.disabled = unit.has_used_action
	var first_button := move_button if not move_button.disabled else attack_button
	if first_button.disabled: first_button = $WaitButton
	first_button.grab_focus()


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
