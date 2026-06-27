class_name SkillSystem
extends Node

var grid: GridSystem
var units: UnitManager
var attacks: AttackSystem
var elements: ElementSystem
var los: LineOfSight
var status_calculator: Node

func setup(source_grid: GridSystem, unit_manager: UnitManager, attack_system: AttackSystem, element_system: ElementSystem, line: LineOfSight, calculator: Node = null) -> void:
	grid = source_grid; units = unit_manager; attacks = attack_system; elements = element_system; los = line; status_calculator = calculator

func can_use_skill(user: BattleUnit, skill: SkillData) -> bool: return user.is_alive() and user.ap >= skill.ap_cost

func get_skill_range_cells(user: BattleUnit, skill: SkillData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var origin := Vector2i(user.grid_x, user.grid_z)
	for z in GridSystem.DEPTH:
		for x in GridSystem.WIDTH:
			var pos := Vector2i(x, z)
			var distance := absi(origin.x - x) + absi(origin.y - z)
			if distance < skill.min_range or distance > skill.max_range: continue
			if skill.requires_line_of_sight and not los.has_line_between(origin, pos): continue
			result.append(pos)
	return result

func can_target_skill(user: BattleUnit, skill: SkillData, target_pos: Vector2i) -> bool:
	if target_pos not in get_skill_range_cells(user, skill): return false
	if skill.area_radius > 0: return true
	var target := units.unit_at(target_pos)
	if not target or not target.is_alive(): return false
	if skill.target_type == SkillData.TargetType.SELF: return target == user
	return target.team != user.team if skill.target_type == SkillData.TargetType.ENEMY else target.team == user.team

func can_attack_skill_cell(user: BattleUnit, skill: SkillData, from_pos: Vector2i, target_unit: BattleUnit, target_pos: Vector2i) -> bool:
	if skill.skill_type != SkillData.SkillType.ATTACK or user.ap < skill.ap_cost or user.team == target_unit.team: return false
	var distance := absi(from_pos.x - target_pos.x) + absi(from_pos.y - target_pos.y)
	if distance < skill.min_range or distance > skill.max_range: return false
	return not skill.requires_line_of_sight or los.has_line_between(from_pos, target_pos)

func get_area_units(user: BattleUnit, skill: SkillData, center: Vector2i) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in units.units:
		if not unit.is_alive(): continue
		if absi(unit.grid_x - center.x) + absi(unit.grid_z - center.y) > skill.area_radius: continue
		if skill.target_type == SkillData.TargetType.ENEMY and unit.team != user.team: result.append(unit)
		elif skill.target_type == SkillData.TargetType.ALLY and unit.team == user.team: result.append(unit)
	return result

func get_skill_area_cells(center: Vector2i, skill: SkillData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in GridSystem.DEPTH:
		for x in GridSystem.WIDTH:
			if absi(x - center.x) + absi(z - center.y) <= skill.area_radius: result.append(Vector2i(x, z))
	return result

func calculate_preview(user: BattleUnit, skill: SkillData, target_pos: Vector2i) -> Dictionary:
	var targets: Array[BattleUnit] = []
	if skill.area_radius > 0:
		targets = get_area_units(user, skill, target_pos)
	else:
		var single_target := units.unit_at(target_pos)
		if single_target:
			targets.append(single_target)
	var target: BattleUnit = targets[0] if not targets.is_empty() else null
	var value := skill.power
	var hit_rate := 100
	if target and skill.skill_type == SkillData.SkillType.ATTACK:
		var terrain_defense := grid.get_cell(Vector2i(target.grid_x, target.grid_z)).defense_bonus
		if skill.scaling_type == SkillData.ScalingType.MAGICAL:
			var magic_attack := user.build_stats.magic_attack_power if user.build_stats else user.intelligence
			var magic_defense := target.build_stats.magic_defense if target.build_stats else target.mind
			value = maxi(1, magic_attack + skill.power - magic_defense)
		else:
			value = maxi(1, user.attack_power + skill.power - target.defense - target.temporary_defense_bonus - terrain_defense)
		value = elements.apply_element_modifiers(value, skill.element, target)
		hit_rate = clampi(attacks.calculate_hit_rate(user, target) + skill.accuracy_modifier + elements.get_hit_modifier(skill.element, target.element), 5, 95)
	elif skill.scaling_type == SkillData.ScalingType.HEALING:
		var final_stats: Dictionary = status_calculator.calculate_final_base_stats(user) if status_calculator else {"mnd": user.mind}
		value = skill.power + floori(int(final_stats.mnd) * 1.5)
	return {"value": value, "hit_rate": hit_rate, "targets": targets, "ap_cost": skill.ap_cost, "is_heal": skill.skill_type == SkillData.SkillType.HEAL}

func execute_skill(user: BattleUnit, skill: SkillData, target_pos: Vector2i) -> Dictionary:
	if not can_use_skill(user, skill) or not can_target_skill(user, skill, target_pos): return {"success": false, "message": "Cannot use skill"}
	var preview := calculate_preview(user, skill, target_pos)
	user.ap = maxi(0, user.ap - skill.ap_cost)
	var messages: Array[String] = ["%s uses %s" % [user.unit_name, skill.skill_name]]
	var target_results: Array[Dictionary] = []
	for target: BattleUnit in preview.targets:
		if skill.skill_type == SkillData.SkillType.BUFF:
			target.temporary_defense_bonus += 3
			messages.append("%s gains Defense +3" % target.unit_name)
			target_results.append({"target": target, "hit": true, "damage": 0, "heal": 0, "defeated": false, "result_type": "buff"})
		elif preview.is_heal:
			var healed := mini(int(preview.value), target.max_hp - target.hp)
			target.hp += healed
			messages.append("%s recovers %d HP" % [target.unit_name, healed])
			target_results.append({"target": target, "hit": true, "damage": 0, "heal": healed, "defeated": false, "result_type": "heal"})
		elif randi_range(1, 100) <= int(preview.hit_rate):
			var critical := skill.scaling_type == SkillData.ScalingType.PHYSICAL and randi_range(1, 100) <= attacks.calculate_critical_rate(user, target, skill)
			var damage := roundi(int(preview.value) * 1.5) if critical else int(preview.value)
			target.take_damage(damage)
			messages.append("%s takes %d damage%s" % [target.unit_name, damage, " (Critical!)" if critical else ""])
			target_results.append({"target": target, "hit": true, "damage": damage, "heal": 0, "defeated": not target.is_alive(), "result_type": "damage", "critical": critical})
			if not target.is_alive(): units.remove_unit(target)
		else:
			messages.append("Miss!")
			target_results.append({"target": target, "hit": false, "damage": 0, "heal": 0, "defeated": false, "result_type": "miss"})
	return {"success": true, "message": "\n".join(messages), "preview": preview, "results": target_results}
