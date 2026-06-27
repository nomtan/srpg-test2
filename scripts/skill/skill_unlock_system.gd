class_name SkillUnlockSystem
extends Node

var jobs: JobDatabase
func setup(database: JobDatabase) -> void: jobs = database

func get_available_skill_ids_for_unit(unit: BattleUnit) -> Array[String]:
	var result: Array[String] = unit.learned_skill_ids.duplicate()
	_append_job_skills(result, unit.main_job_id, unit.get_job_level_for(unit.main_job_id))
	var sub_access := maxi(1, floori(float(unit.get_job_level_for(unit.main_job_id)) / 2.0))
	_append_job_skills(result, unit.sub_job_id, sub_access)
	return result

func _append_job_skills(result: Array[String], job_id: String, access_level: int) -> void:
	var job := jobs.get_job(job_id)
	if not job: return
	for entry in job.learnable_skills:
		if int(entry.job_level) <= access_level and entry.skill_id not in result: result.append(entry.skill_id)

func can_equip_skill(unit: BattleUnit, skill_id: String) -> bool: return skill_id in get_available_skill_ids_for_unit(unit)
func validate_equipped_skills(unit: BattleUnit) -> void:
	var valid := get_available_skill_ids_for_unit(unit)
	for skill_id in unit.equipped_skill_ids.duplicate():
		if skill_id not in valid: unit.unequip_skill(skill_id)
