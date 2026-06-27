class_name StatusCalculator
extends Node

var job_database: JobDatabase

func setup(database: JobDatabase) -> void: job_database = database

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
	return build

func calculate_max_hp(unit: BattleUnit, stats: Dictionary) -> int:
	var hp_bonus := 0
	var main_job := job_database.get_job(unit.main_job_id)
	var sub_job := job_database.get_job(unit.sub_job_id)
	if main_job: hp_bonus += main_job.hp_bonus
	if sub_job and sub_job != main_job: hp_bonus += floori(sub_job.hp_bonus * 0.5)
	return 100 + int(stats.vit) * 5 + hp_bonus

func get_equipment_bonus(_unit: BattleUnit) -> Dictionary: return {}
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
