class_name UnitProgressData
extends RefCounted

var data: Dictionary = {}

static func from_unit(unit: BattleUnit) -> UnitProgressData:
	var progress := UnitProgressData.new()
	progress.data = {
		"unit_id": unit.unit_id,
		"level": unit.level,
		"exp": unit.exp,
		"max_hp": unit.max_hp,
		"max_ap": unit.max_ap,
		"attack_power": unit.attack_power,
		"defense": unit.defense,
		"accuracy": unit.accuracy,
		"evasion": unit.evasion,
		"strength": unit.strength,
		"dexterity": unit.dexterity,
		"vitality": unit.vitality,
		"mind": unit.mind,
		"intelligence": unit.intelligence,
		"agility": unit.agility,
		"base_str": unit.base_str,
		"base_dex": unit.base_dex,
		"base_vit": unit.base_vit,
		"base_mnd": unit.base_mnd,
		"base_int": unit.base_int,
		"base_agi": unit.base_agi,
		"main_job_id": unit.main_job_id,
		"sub_job_id": unit.sub_job_id,
		"job_levels": unit.job_levels.duplicate(true),
		"job_exps": unit.job_exps.duplicate(true),
		"learned_skill_ids": unit.learned_skill_ids.duplicate(),
		"equipped_skill_ids": unit.equipped_skill_ids.duplicate(),
		"unlocked_job_ids": unit.unlocked_job_ids.duplicate(),
	}
	return progress

func to_dict() -> Dictionary:
	return data.duplicate(true)
