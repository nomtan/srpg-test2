class_name ThreatSystem
extends Node

var units: UnitManager
var attacks: AttackSystem
var paths: BattlePathfinding
var grid: GridSystem

func setup(unit_manager: UnitManager, attack_system: AttackSystem, pathfinding: BattlePathfinding, source_grid: GridSystem) -> void:
	units = unit_manager
	attacks = attack_system
	paths = pathfinding
	grid = source_grid

func get_threatening_enemies_for_cell(target_unit: BattleUnit, target_pos: Vector2i) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for enemy in units.get_enemy_units():
		if attacks.can_attack_cell(enemy, target_unit, target_pos):
			result.append(enemy)
			continue
		var reachable := paths.find_reachable(grid, Vector2i(enemy.grid_x, enemy.grid_z), enemy.move_range, enemy.jump_height)
		for enemy_pos: Vector2i in reachable:
			if attacks.can_attack_position(enemy, enemy_pos, target_pos):
				result.append(enemy)
				break
	return result

func is_cell_threatened(target_unit: BattleUnit, target_pos: Vector2i) -> bool:
	return not get_threatening_enemies_for_cell(target_unit, target_pos).is_empty()
