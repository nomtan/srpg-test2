class_name SkillUnlockSystem
extends Node

var jobs: JobDatabase
var skills: SkillDatabase

func setup(job_database: JobDatabase, skill_database: SkillDatabase) -> void:
	jobs = job_database
	skills = skill_database

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

func equip_passive_skill(unit: BattleUnit, skill_id: String) -> bool:
	var skill := skills.get_skill(skill_id)
	if not skill or skill.skill_type != SkillData.SkillType.PASSIVE:
		return false
	if skill_id in unit.equipped_passive_skill_ids or unit.equipped_passive_skill_ids.size() >= BattleUnit.MAX_EQUIPPED_PASSIVE_SKILLS:
		return false
	if not skill_id in get_available_skill_ids_for_unit(unit):
		return false
	unit.equipped_passive_skill_ids.append(skill_id)
	return true

func unequip_passive_skill(unit: BattleUnit, skill_id: String) -> void:
	unit.equipped_passive_skill_ids.erase(skill_id)

func can_equip_skill(unit: BattleUnit, skill_id: String) -> bool:
	var skill := skills.get_skill(skill_id)
	return skill != null and skill.skill_type != SkillData.SkillType.PASSIVE and skill_id in get_available_skill_ids_for_unit(unit)

func validate_equipped_skills(unit: BattleUnit) -> void:
	var valid := get_available_skill_ids_for_unit(unit)
	for skill_id in unit.equipped_skill_ids.duplicate():
		var skill := skills.get_skill(skill_id)
		if skill_id not in valid or not skill or skill.skill_type == SkillData.SkillType.PASSIVE:
			unit.unequip_skill(skill_id)
	for skill_id in unit.equipped_passive_skill_ids.duplicate():
		var skill := skills.get_skill(skill_id)
		if skill_id not in valid or not skill or skill.skill_type != SkillData.SkillType.PASSIVE:
			unequip_passive_skill(unit, skill_id)
