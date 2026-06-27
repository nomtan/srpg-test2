class_name AttackSystem
extends Node

var grid: GridSystem


func setup(source_grid: GridSystem) -> void:
	grid = source_grid


func get_attackable_cells(attacker: BattleUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin := Vector2i(attacker.grid_x, attacker.grid_z)
	for z in GridSystem.DEPTH:
		for x in GridSystem.WIDTH:
			var candidate := Vector2i(x, z)
			var distance := absi(origin.x - x) + absi(origin.y - z)
			if distance > 0 and distance <= attacker.attack_range:
				if absi(grid.get_cell(origin).height - grid.get_cell(candidate).height) <= 1:
					result.append(candidate)
	return result


func can_attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if not attacker or not target or not attacker.is_alive() or not target.is_alive():
		return false
	if attacker.team == target.team:
		return false
	return Vector2i(target.grid_x, target.grid_z) in get_attackable_cells(attacker)


func can_attack_from_position(attacker: BattleUnit, from_pos: Vector2i, target: BattleUnit) -> bool:
	if not target or not target.is_alive() or attacker.team == target.team:
		return false
	var target_pos := Vector2i(target.grid_x, target.grid_z)
	var distance := absi(from_pos.x - target_pos.x) + absi(from_pos.y - target_pos.y)
	if distance == 0 or distance > attacker.attack_range:
		return false
	return absi(grid.get_cell(from_pos).height - grid.get_cell(target_pos).height) <= 1


func calculate_damage(attacker: BattleUnit, target: BattleUnit) -> int:
	return maxi(1, attacker.attack_power - target.defense)


func execute_attack(attacker: BattleUnit, target: BattleUnit) -> int:
	if not can_attack(attacker, target):
		return 0
	var damage := calculate_damage(attacker, target)
	target.take_damage(damage)
	return damage
