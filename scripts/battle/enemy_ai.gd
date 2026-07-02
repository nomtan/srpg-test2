class_name EnemyAI
extends Node

signal floating_result(target: BattleUnit, result_type: String, amount: int)

var grid: GridSystem
var unit_manager: UnitManager
var pathfinding: BattlePathfinding
var attack_system: AttackSystem
var unit_mover: UnitMover
var skill_database: SkillDatabase
var skill_system: SkillSystem


func setup(source_grid: GridSystem, units: UnitManager, paths: BattlePathfinding, attacks: AttackSystem, mover: UnitMover, database: SkillDatabase, skills: SkillSystem) -> void:
	grid = source_grid
	unit_manager = units
	pathfinding = paths
	attack_system = attacks
	unit_mover = mover
	skill_database = database
	skill_system = skills


func process_enemy_unit(enemy: BattleUnit) -> String:
	var skill_message := _try_skill(enemy)
	if not skill_message.is_empty(): return skill_message
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
		var path := pathfinding.find_path(grid, enemy, destination)
		await unit_mover.move_unit_along_path(enemy, path)
		unit_manager.move_unit_to_grid(enemy, destination)
	target = find_attackable_player_unit(enemy)
	skill_message = _try_skill(enemy)
	if not skill_message.is_empty(): return skill_message
	if target: return _attack(enemy, target)
	enemy.face_toward(Vector2i(nearest.grid_x, nearest.grid_z))
	return "%sは移動して待機" % enemy.unit_name

func _try_skill(enemy: BattleUnit) -> String:
	for skill in skill_database.get_skills_for_unit(enemy):
		if not skill_system.can_use_skill(enemy, skill) or skill.skill_type != SkillData.SkillType.ATTACK: continue
		for player in unit_manager.get_player_units():
			var target_pos := Vector2i(player.grid_x, player.grid_z)
			if skill_system.can_target_skill(enemy, skill, target_pos):
				var result := skill_system.execute_skill(enemy, skill, target_pos)
				_show_skill_results(result)
				return result.message
	return ""


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
	var best: BattleUnit = null
	var best_hit_rate := -1
	for player in unit_manager.get_player_units():
		if attack_system.can_attack(enemy, player):
			var hit_rate := attack_system.calculate_hit_rate(enemy, player)
			var priority := hit_rate
			if player.unit_id == "vain": priority += 8
			if enemy.enemy_type == BattleUnit.EnemyType.BOSS and enemy.hp * 2 <= enemy.max_hp: priority += 15
			if priority > best_hit_rate or (priority == best_hit_rate and (not best or player.hp < best.hp)):
				best = player
				best_hit_rate = priority
	return best


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
	var result := attack_system.execute_attack(enemy, target)
	floating_result.emit(target, "damage" if result.hit else "miss", int(result.damage))
	if not target.is_alive(): unit_manager.remove_unit(target)
	if not result.hit: return "%s attacks %s\nMiss!" % [enemy.unit_name, target.unit_name]
	var message := "%s attacks %s\nHit! %d damage" % [enemy.unit_name, target.unit_name, result.damage]
	if result.defeated: message += "\n%s defeated" % target.unit_name
	return message

func _show_skill_results(result: Dictionary) -> void:
	if not result.has("results"): return
	for target_result: Dictionary in result.results:
		var type: String = target_result.result_type
		var amount := int(target_result.heal) if type == "heal" else int(target_result.damage)
		floating_result.emit(target_result.target, type, amount)
