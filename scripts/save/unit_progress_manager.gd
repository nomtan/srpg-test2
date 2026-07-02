class_name UnitProgressManager
extends Node

var units_progress: Dictionary = {}
var job_database: JobDatabase

func setup(database: JobDatabase) -> void:
	job_database = database

func is_empty() -> bool:
	return units_progress.is_empty()

func create_default_units(units: Array[BattleUnit]) -> void:
	units_progress.clear()
	update_progress_from_units(units)

func update_progress_from_units(units: Array[BattleUnit]) -> void:
	for unit in units:
		units_progress[unit.unit_id] = UnitProgressData.from_unit(unit).to_dict()

func apply_progress_to_units(units: Array[BattleUnit]) -> void:
	for unit in units:
		apply_progress_to_unit(unit)

func apply_progress_to_unit(unit: BattleUnit) -> void:
	if not units_progress.has(unit.unit_id):
		units_progress[unit.unit_id] = UnitProgressData.from_unit(unit).to_dict()
		return
	var saved: Dictionary = units_progress[unit.unit_id]
	unit.level = int(saved.get("level", unit.level))
	unit.exp = int(saved.get("exp", unit.exp))
	for property_name: String in ["max_hp", "max_ap", "attack_power", "defense", "accuracy", "evasion", "strength", "dexterity", "vitality", "mind", "intelligence", "agility"]:
		unit.set(property_name, int(saved.get(property_name, unit.get(property_name))))
	unit.base_str = int(saved.get("base_str", saved.get("strength", unit.base_str)))
	unit.base_dex = int(saved.get("base_dex", saved.get("dexterity", unit.base_dex)))
	unit.base_vit = int(saved.get("base_vit", saved.get("vitality", unit.base_vit)))
	unit.base_mnd = int(saved.get("base_mnd", saved.get("mind", unit.base_mnd)))
	unit.base_int = int(saved.get("base_int", saved.get("intelligence", unit.base_int)))
	unit.base_agi = int(saved.get("base_agi", saved.get("agility", unit.base_agi)))
	unit.main_job_id = str(saved.get("main_job_id", unit.main_job_id))
	unit.sub_job_id = str(saved.get("sub_job_id", unit.sub_job_id))
	unit.job_levels = _dictionary_copy(saved.get("job_levels", unit.job_levels))
	unit.job_exps = _dictionary_copy(saved.get("job_exps", unit.job_exps))
	unit.learned_skill_ids = _string_array(saved.get("learned_skill_ids", unit.learned_skill_ids))
	unit.equipped_skill_ids = _string_array(saved.get("equipped_skill_ids", unit.equipped_skill_ids))
	unit.unlocked_job_ids = _string_array(saved.get("unlocked_job_ids", unit.unlocked_job_ids))
	unit.equipped_weapon_id = str(saved.get("equipped_weapon_id", unit.equipped_weapon_id))
	unit.equipped_armor_id = str(saved.get("equipped_armor_id", unit.equipped_armor_id))
	unit.equipped_accessory_id = str(saved.get("equipped_accessory_id", unit.equipped_accessory_id))
	_apply_job_names(unit)
	unit.job_id = unit.main_job_id
	unit.job_name = unit.main_job_name
	unit.job_level = unit.get_job_level_for(unit.main_job_id)
	unit.job_exp = unit.get_job_exp_for(unit.main_job_id)
	unit.hp = unit.max_hp
	unit.ap = unit.max_ap
	unit.is_dead = false
	unit.update_visual_state()

func to_dict() -> Dictionary:
	return units_progress.duplicate(true)

func from_dict(data: Dictionary) -> void:
	units_progress = data.duplicate(true)

func _apply_job_names(unit: BattleUnit) -> void:
	var main_job := job_database.get_job(unit.main_job_id) if job_database else null
	var sub_job := job_database.get_job(unit.sub_job_id) if job_database else null
	unit.main_job_name = main_job.job_name if main_job else unit.main_job_id
	unit.sub_job_name = sub_job.job_name if sub_job else ("None" if unit.sub_job_id.is_empty() else unit.sub_job_id)

func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			result.append(str(entry))
	return result

func _dictionary_copy(value: Variant) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}
