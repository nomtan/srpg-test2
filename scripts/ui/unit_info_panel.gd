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


func show_battle_preview(attacker: BattleUnit, target: BattleUnit, preview: Dictionary) -> void:
	var range_text := str(preview.min_range) if preview.min_range == preview.max_range else "%d - %d" % [preview.min_range, preview.max_range]
	label.text = "Attacker: %s\nTarget: %s\nDirection: %s\nHP: %d / %d\nDamage: %d  Hit: %d%%\nAfter HP: %d / %d\nRange: %s  Height: %+d\nTerrain: %s (Eva %+d / Def %+d)\nLine of Sight: %s" % [attacker.unit_name, target.unit_name, preview.direction, target.hp, target.max_hp, preview.damage, preview.hit_rate, preview.after_hp, target.max_hp, range_text, preview.height_diff, preview.terrain, preview.evasion_bonus, preview.defense_bonus, preview.line_of_sight]


func show_cell(cell: GridCell, unit: BattleUnit = null) -> void:
	var facing_names := ["North", "East", "South", "West"]
	var element_names := ["None", "Earth", "Water", "Wind", "Fire", "Thunder", "Ice", "Light", "Dark"]
	var unit_text := "%s  Lv %d  EXP %d/%d\nHP: %d / %d  AP: %d / %d\nMain: %s Lv %d  JobEXP: %d/%d\nSub: %s  Skills: %d/%d\nElement: %s\nAccuracy: %d  Evasion: %d\nFacing: %s  Status: %s\n" % [unit.unit_name, unit.level, unit.exp, unit.exp_to_next_level, unit.hp, unit.max_hp, unit.ap, unit.max_ap, unit.main_job_name, unit.get_job_level_for(unit.main_job_id), unit.get_job_exp_for(unit.main_job_id), unit.job_exp_to_next_level, unit.sub_job_name, unit.equipped_skill_ids.size(), BattleUnit.MAX_EQUIPPED_SKILLS, element_names[int(unit.element)], unit.accuracy, unit.evasion, facing_names[int(unit.facing)], unit.get_status_name()] if unit else ""
	if unit and unit.build_stats:
		var b := unit.build_stats
		unit_text += "CT %d / 100  Speed %d\nSTR %d DEX %d VIT %d MND %d INT %d AGI %d\nATK %d MATK %d DEF %d MDEF %d\nACC %d CRIT %d%% EVA %d%% SPD %d MOVE %d JUMP %d RES %d\n" % [unit.ct, b.speed, unit.strength, unit.dexterity, unit.vitality, unit.mind, unit.intelligence, unit.agility, b.attack_power, b.magic_attack_power, b.defense, b.magic_defense, b.accuracy, b.critical_rate, b.evasion, b.speed, b.move_range, b.jump_height, b.status_resistance]
	label.text = unit_text + "Terrain: %s\nMove Cost: %d\nEvasion: %+d%%  Defense: %+d\nWalkable: %s  LOS Block: %s" % [cell.terrain, cell.move_cost, cell.evasion_bonus, cell.defense_bonus, "Yes" if cell.walkable else "No", "Yes" if cell.blocks_line_of_sight else "No"]


func show_blocked_target(target: BattleUnit) -> void:
	label.text = "Target: %s\nCannot Attack\nReason: Line of sight blocked" % target.unit_name
