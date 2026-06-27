class_name ThreatSystem
extends Node

var units: UnitManager
var attacks: AttackSystem
var paths: BattlePathfinding
var grid: GridSystem
var skill_database: SkillDatabase
var skill_system: SkillSystem

func setup(unit_manager: UnitManager, attack_system: AttackSystem, pathfinding: BattlePathfinding, source_grid: GridSystem, database: SkillDatabase, skills: SkillSystem) -> void:
	units = unit_manager
	attacks = attack_system
	paths = pathfinding
	grid = source_grid
	skill_database = database
	skill_system = skills

func get_threatening_enemies_for_cell(target_unit: BattleUnit, target_pos: Vector2i) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for enemy in units.get_enemy_units():
		var enemy_positions: Array[Vector2i] = [Vector2i(enemy.grid_x, enemy.grid_z)]
		var reachable := paths.find_reachable(grid, enemy_positions[0], enemy.move_range, enemy.jump_height)
		for enemy_pos: Vector2i in reachable:
			if enemy_pos not in enemy_positions: enemy_positions.append(enemy_pos)
		var skill_threat := false
		for skill in skill_database.get_skills_for_unit(enemy):
			for enemy_pos in enemy_positions:
				if skill_system.can_attack_skill_cell(enemy, skill, enemy_pos, target_unit, target_pos):
					skill_threat = true
					break
			if skill_threat: break
		if skill_threat:
			result.append(enemy)
			continue
		if attacks.can_attack_cell(enemy, target_unit, target_pos):
			result.append(enemy)
			continue
		for enemy_pos: Vector2i in reachable:
			if attacks.can_attack_position(enemy, enemy_pos, target_pos):
				result.append(enemy)
				break
	return result

func is_cell_threatened(target_unit: BattleUnit, target_pos: Vector2i) -> bool:
	return not get_threatening_enemies_for_cell(target_unit, target_pos).is_empty()
