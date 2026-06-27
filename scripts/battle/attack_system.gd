class_name AttackSystem
extends Node

enum AttackDirection { FRONT, SIDE, BACK }

var grid: GridSystem
var line_of_sight: LineOfSight


func setup(source_grid: GridSystem, los: LineOfSight) -> void:
	grid = source_grid
	line_of_sight = los


func get_attackable_cells(attacker: BattleUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin := Vector2i(attacker.grid_x, attacker.grid_z)
	for z in GridSystem.DEPTH:
		for x in GridSystem.WIDTH:
			var candidate := Vector2i(x, z)
			if can_attack_position(attacker, origin, candidate): result.append(candidate)
	return result


func can_attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if not attacker or not target or not attacker.is_alive() or not target.is_alive(): return false
	if attacker.team == target.team: return false
	return can_attack_position(attacker, Vector2i(attacker.grid_x, attacker.grid_z), Vector2i(target.grid_x, target.grid_z))


func can_attack_from_position(attacker: BattleUnit, from_pos: Vector2i, target: BattleUnit) -> bool:
	if not target or not target.is_alive() or attacker.team == target.team: return false
	return can_attack_position(attacker, from_pos, Vector2i(target.grid_x, target.grid_z))


func can_attack_cell(attacker: BattleUnit, target_unit: BattleUnit, target_pos: Vector2i) -> bool:
	if not attacker.is_alive() or attacker.team == target_unit.team: return false
	return can_attack_position(attacker, Vector2i(attacker.grid_x, attacker.grid_z), target_pos)


func can_attack_position(attacker: BattleUnit, from_pos: Vector2i, target_pos: Vector2i) -> bool:
	var distance := absi(from_pos.x - target_pos.x) + absi(from_pos.y - target_pos.y)
	var height_diff := grid.get_cell(from_pos).height - grid.get_cell(target_pos).height
	var max_range := get_adjusted_max_range(attacker, height_diff)
	var height_limit := 1 if attacker.attack_type == BattleUnit.AttackType.MELEE else 3
	if not (distance >= attacker.min_attack_range and distance <= max_range and absi(height_diff) <= height_limit): return false
	if attacker.attack_type == BattleUnit.AttackType.RANGED and not line_of_sight.has_line_between(from_pos, target_pos): return false
	return true


func get_adjusted_max_range(attacker: BattleUnit, height_diff: int) -> int:
	if attacker.attack_type == BattleUnit.AttackType.MELEE: return attacker.max_attack_range
	if height_diff > 0: return attacker.max_attack_range + mini(height_diff, 2)
	if height_diff < 0: return maxi(attacker.min_attack_range, attacker.max_attack_range + height_diff)
	return attacker.max_attack_range


func calculate_hit_rate(attacker: BattleUnit, target: BattleUnit) -> int:
	var height_diff := grid.get_cell(Vector2i(attacker.grid_x, attacker.grid_z)).height - grid.get_cell(Vector2i(target.grid_x, target.grid_z)).height
	var height_bonus := mini(height_diff * 5, 15) if height_diff > 0 else maxi(height_diff * 7, -21)
	var terrain_bonus := grid.get_cell(Vector2i(target.grid_x, target.grid_z)).evasion_bonus
	var direction_bonus: int = {AttackDirection.FRONT: -5, AttackDirection.SIDE: 10, AttackDirection.BACK: 20}[get_attack_direction(attacker, target)]
	return clampi(attacker.accuracy - target.evasion - terrain_bonus + height_bonus + direction_bonus, 5, 95)


func calculate_damage(attacker: BattleUnit, target: BattleUnit) -> int:
	var terrain_defense := grid.get_cell(Vector2i(target.grid_x, target.grid_z)).defense_bonus
	var direction_bonus: int = {AttackDirection.FRONT: 0, AttackDirection.SIDE: 2, AttackDirection.BACK: 5}[get_attack_direction(attacker, target)]
	return maxi(1, attacker.attack_power - target.defense - target.temporary_defense_bonus - terrain_defense + direction_bonus)

func calculate_critical_rate(attacker: BattleUnit, _target: BattleUnit, skill: SkillData = null) -> int:
	var rate := attacker.build_stats.critical_rate if attacker.build_stats else 0
	if skill: rate += skill.critical_modifier
	return clampi(rate, 0, 50)


func get_attack_direction(attacker: BattleUnit, target: BattleUnit) -> AttackDirection:
	var delta := Vector2i(attacker.grid_x - target.grid_x, attacker.grid_z - target.grid_z)
	if absi(delta.x) == absi(delta.y): return AttackDirection.SIDE
	var incoming: BattleUnit.FacingDirection
	if absi(delta.x) > absi(delta.y): incoming = BattleUnit.FacingDirection.EAST if delta.x > 0 else BattleUnit.FacingDirection.WEST
	else: incoming = BattleUnit.FacingDirection.SOUTH if delta.y > 0 else BattleUnit.FacingDirection.NORTH
	if incoming == target.facing: return AttackDirection.FRONT
	if (int(incoming) + 2) % 4 == int(target.facing): return AttackDirection.BACK
	return AttackDirection.SIDE


func get_direction_name(direction: AttackDirection) -> String:
	return ["Front", "Side", "Back"][int(direction)]


func get_battle_preview(attacker: BattleUnit, target: BattleUnit) -> Dictionary:
	var attacker_pos := Vector2i(attacker.grid_x, attacker.grid_z)
	var target_pos := Vector2i(target.grid_x, target.grid_z)
	var height_diff := grid.get_cell(attacker_pos).height - grid.get_cell(target_pos).height
	var damage := calculate_damage(attacker, target)
	var target_cell := grid.get_cell(target_pos)
	return {"damage": damage, "hit_rate": calculate_hit_rate(attacker, target), "after_hp": maxi(0, target.hp - damage), "height_diff": height_diff, "min_range": attacker.min_attack_range, "max_range": get_adjusted_max_range(attacker, height_diff), "direction": get_direction_name(get_attack_direction(attacker, target)), "terrain": target_cell.terrain, "evasion_bonus": target_cell.evasion_bonus, "defense_bonus": target_cell.defense_bonus, "line_of_sight": "Clear"}


func execute_attack(attacker: BattleUnit, target: BattleUnit) -> Dictionary:
	if not can_attack(attacker, target): return {"success": false, "hit": false, "damage": 0, "message": "Cannot attack", "defeated": false}
	attacker.face_toward(Vector2i(target.grid_x, target.grid_z))
	var hit_rate := calculate_hit_rate(attacker, target)
	if randi_range(1, 100) > hit_rate: return {"success": true, "hit": false, "damage": 0, "message": "Miss!", "defeated": false, "hit_rate": hit_rate}
	var damage := calculate_damage(attacker, target)
	var critical := randi_range(1, 100) <= calculate_critical_rate(attacker, target)
	if critical: damage = maxi(1, roundi(damage * 1.5))
	target.take_damage(damage)
	return {"success": true, "hit": true, "damage": damage, "message": "Critical Hit!" if critical else "Hit!", "defeated": not target.is_alive(), "hit_rate": hit_rate, "critical": critical}
