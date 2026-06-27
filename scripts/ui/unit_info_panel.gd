class_name UnitInfoPanel
extends PanelContainer

@onready var label: Label = $UnitInfoLabel


func show_unit(unit: BattleUnit, expected_damage: int = -1) -> void:
	if not unit:
		label.text = ""
		return
	label.text = "%s\nHP: %d / %d" % [unit.unit_name, unit.hp, unit.max_hp]
	if expected_damage >= 0:
		label.text += "\nDamage: %d\nAfter HP: %d / %d" % [
			expected_damage, maxi(0, unit.hp - expected_damage), unit.max_hp
		]


func show_damage_preview(attacker: BattleUnit, target: BattleUnit, damage: int) -> void:
	label.text = "Attacker: %s\nTarget: %s\nHP: %d / %d\nDamage: %d\nAfter HP: %d / %d" % [
		attacker.unit_name, target.unit_name, target.hp, target.max_hp,
		damage, maxi(0, target.hp - damage), target.max_hp
	]
