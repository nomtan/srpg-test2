class_name EnemyAI
extends Node

var grid: GridSystem
var unit_manager: UnitManager
var pathfinding: BattlePathfinding
var attack_system: AttackSystem


func setup(source_grid: GridSystem, units: UnitManager, paths: BattlePathfinding, attacks: AttackSystem) -> void:
	grid = source_grid
	unit_manager = units
	pathfinding = paths
	attack_system = attacks


func process_enemy_unit(enemy: BattleUnit) -> String:
	var target := find_attackable_player_unit(enemy)
	if target:
		return _attack(enemy, target)
	var nearest := find_nearest_player_unit(enemy)
	if not nearest:
		return "%sは待機" % enemy.unit_name
	var reachable := pathfinding.find_reachable(
		grid, Vector2i(enemy.grid_x, enemy.grid_z), enemy.move_range, enemy.jump_height
	)
	var destination := _find_best_destination(enemy, nearest, reachable)
	if destination != Vector2i(enemy.grid_x, enemy.grid_z):
		unit_manager.move_unit_to_grid(enemy, destination)
	target = find_attackable_player_unit(enemy)
	return _attack(enemy, target) if target else "%sは移動して待機" % enemy.unit_name


func find_nearest_player_unit(enemy: BattleUnit) -> BattleUnit:
	var result: BattleUnit
	var best_distance := 999999
	for player in unit_manager.get_player_units():
		var distance := absi(enemy.grid_x - player.grid_x) + absi(enemy.grid_z - player.grid_z)
		if distance < best_distance:
			best_distance = distance
			result = player
	return result


func find_attackable_player_unit(enemy: BattleUnit) -> BattleUnit:
	for player in unit_manager.get_player_units():
		if attack_system.can_attack(enemy, player):
			return player
	return null


func _find_best_destination(enemy: BattleUnit, target: BattleUnit, reachable: Dictionary) -> Vector2i:
	var origin := Vector2i(enemy.grid_x, enemy.grid_z)
	var best := origin
	var best_score := 999999
	for candidate: Vector2i in reachable:
		var distance := absi(candidate.x - target.grid_x) + absi(candidate.y - target.grid_z)
		var can_attack := attack_system.can_attack_from_position(enemy, candidate, target)
		var score := distance + int(reachable[candidate])
		if can_attack: score -= 10000
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _attack(enemy: BattleUnit, target: BattleUnit) -> String:
	var damage := attack_system.execute_attack(enemy, target)
	if not target.is_alive(): unit_manager.remove_unit(target)
	return "%sが%sに%dダメージ" % [enemy.unit_name, target.unit_name, damage]
