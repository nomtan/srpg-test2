class_name FloatingNumberManager
extends Node3D

func show_damage(unit: BattleUnit, amount: int) -> void: _spawn(unit, str(amount), "damage")
func show_heal(unit: BattleUnit, amount: int) -> void: _spawn(unit, str(amount), "heal")
func show_miss(unit: BattleUnit) -> void: _spawn(unit, "Miss", "miss")

func _spawn(unit: BattleUnit, value_text: String, number_type: String) -> void:
	var number := FloatingNumber3D.new()
	add_child(number)
	number.play(value_text, unit.global_position, number_type)
