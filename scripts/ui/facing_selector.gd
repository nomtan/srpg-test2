class_name FacingSelector
extends VBoxContainer

signal direction_selected(direction: BattleUnit.FacingDirection)
signal cancelled


func _ready() -> void:
	$NorthButton.pressed.connect(func() -> void: direction_selected.emit(BattleUnit.FacingDirection.NORTH))
	$EastButton.pressed.connect(func() -> void: direction_selected.emit(BattleUnit.FacingDirection.EAST))
	$SouthButton.pressed.connect(func() -> void: direction_selected.emit(BattleUnit.FacingDirection.SOUTH))
	$WestButton.pressed.connect(func() -> void: direction_selected.emit(BattleUnit.FacingDirection.WEST))


func open() -> void:
	visible = true
	$NorthButton.grab_focus()


func close() -> void: visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
