class_name StatusCalculator
extends Node

var job_database: JobDatabase
var equipment_database: Node

func setup(database: JobDatabase, equipment_db: Node = null) -> void:
	job_database = database; equipment_database = equipment_db

func calculate_final_base_stats(unit: BattleUnit) -> Dictionary:
	var stats := {"str": unit.base_str, "dex": unit.base_dex, "vit": unit.base_vit, "mnd": unit.base_mnd, "int": unit.base_int, "agi": unit.base_agi}
	_apply_job_bonus(stats, job_database.get_job(unit.main_job_id), 1.0)
	if unit.sub_job_id != unit.main_job_id: _apply_job_bonus(stats, job_database.get_job(unit.sub_job_id), 0.5)
	_add_bonus(stats, get_equipment_bonus(unit), 1.0)
	_add_bonus(stats, get_passive_bonus(unit), 1.0)
	_add_bonus(stats, get_buff_debuff_bonus(unit), 1.0)
	return stats

func calculate_build_stats(unit: BattleUnit) -> BuildStats:
	var stats := calculate_final_base_stats(unit)
	var build := BuildStats.new()
	build.attack_power = int(stats.str)
	build.magic_attack_power = int(stats.int)
	build.defense = int(stats.vit)
	build.magic_defense = int(stats.mnd)
	build.speed = int(stats.agi)
	build.move_range = _base_move(unit) + floori(int(stats.agi) / 20.0)
	build.jump_height = _base_jump(unit) + floori(int(stats.agi) / 30.0)
	build.accuracy = 70 + floori(int(stats.dex) / 2.0)
	build.critical_rate = 5 + floori(int(stats.dex) / 5.0)
	build.evasion = mini(60, 5 + floori(int(stats.agi) / 3.0) + floori(int(stats.dex) / 10.0))
	build.status_resistance = floori(int(stats.mnd) / 2.0)
	_apply_equipment_build_bonus(unit, build)
	_apply_equipment_resistance_bonus(unit, build)
	return build

func calculate_max_hp(unit: BattleUnit, stats: Dictionary) -> int:
	var hp_bonus := 0
	var main_job := job_database.get_job(unit.main_job_id)
	var sub_job := job_database.get_job(unit.sub_job_id)
	if main_job: hp_bonus += main_job.hp_bonus
	if sub_job and sub_job != main_job: hp_bonus += floori(sub_job.hp_bonus * 0.5)
	return 100 + int(stats.vit) * 5 + hp_bonus

func get_equipment_bonus(unit: BattleUnit) -> Dictionary:
	var bonus := {"str": 0, "dex": 0, "vit": 0, "mnd": 0, "int": 0, "agi": 0}
	if not equipment_database: return bonus
	for equipment_id: String in [unit.equipped_weapon_id, unit.equipped_armor_id, unit.equipped_accessory_id]:
		var equipment: EquipmentData = equipment_database.get_equipment(equipment_id)
		if equipment: _add_bonus(bonus, equipment.stat_bonus, 1.0)
	return bonus
func get_passive_bonus(_unit: BattleUnit) -> Dictionary: return {}
func get_buff_debuff_bonus(_unit: BattleUnit) -> Dictionary: return {}

func _apply_job_bonus(stats: Dictionary, job: JobData, weight: float) -> void:
	if job: _add_bonus(stats, job.stat_bonus, weight)
func _add_bonus(stats: Dictionary, bonus: Dictionary, weight: float) -> void:
	for key: String in stats: stats[key] = int(stats[key]) + floori(int(bonus.get(key, 0)) * weight)
func _base_move(unit: BattleUnit) -> int:
	var job := job_database.get_job(unit.main_job_id)
	return job.base_move_range if job else unit.move_range
func _base_jump(unit: BattleUnit) -> int:
	var job := job_database.get_job(unit.main_job_id)
	return job.base_jump_height if job else unit.jump_height

func _apply_equipment_build_bonus(unit: BattleUnit, build: BuildStats) -> void:
	if not equipment_database: return
	for equipment_id: String in [unit.equipped_weapon_id, unit.equipped_armor_id, unit.equipped_accessory_id]:
		var equipment: EquipmentData = equipment_database.get_equipment(equipment_id)
		if not equipment: continue
		build.accuracy += int(equipment.build_bonus.get("accuracy", 0))
		build.critical_rate += int(equipment.build_bonus.get("critical_rate", 0))
		build.evasion += int(equipment.build_bonus.get("evasion", 0))
		build.move_range += int(equipment.build_bonus.get("move_range", 0))
		build.jump_height += int(equipment.build_bonus.get("jump_height", 0))
	build.evasion = clampi(build.evasion, 0, 60); build.critical_rate = clampi(build.critical_rate, 0, 50)

func _apply_equipment_resistance_bonus(unit: BattleUnit, build: BuildStats) -> void:
	if not equipment_database: return
	for equipment_id: String in [unit.equipped_weapon_id, unit.equipped_armor_id, unit.equipped_accessory_id]:
		var equipment: EquipmentData = equipment_database.get_equipment(equipment_id)
		if not equipment: continue
		for element_key: String in equipment.elemental_resistance_bonus:
			build.elemental_resistances[element_key] = clampi(int(build.elemental_resistances.get(element_key, 0)) + int(equipment.elemental_resistance_bonus[element_key]), -100, 100)
