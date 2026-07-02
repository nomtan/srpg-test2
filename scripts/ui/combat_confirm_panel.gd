class_name CombatConfirmPanel
extends PanelContainer

signal confirmed
signal cancelled

@onready var preview_label: Label = $VBox/PreviewLabel

func _ready() -> void:
	$VBox/Buttons/ConfirmButton.pressed.connect(func() -> void: confirmed.emit())
	$VBox/Buttons/CancelButton.pressed.connect(func() -> void: cancelled.emit())

func open(attacker: BattleUnit, target: BattleUnit, preview: Dictionary) -> void:
	preview_label.text = "Attacker: %s\nWeapon: %s\nTarget: %s\n\nDamage: %d  Hit Rate: %d%%  Critical: %d%%\nTarget HP: %d / %d\nAfter HP: %d / %d\nDirection: %s\nTerrain: %s\nLine of Sight: %s\nDefeat: %s" % [attacker.unit_name, preview.weapon_name, target.unit_name, preview.damage, preview.hit_rate, preview.critical_rate, target.hp, target.max_hp, preview.after_hp, target.max_hp, preview.direction, preview.terrain, preview.line_of_sight, "Yes" if preview.after_hp == 0 else "No"]
	visible = true
	$VBox/Buttons/ConfirmButton.grab_focus()

func close() -> void: visible = false

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
