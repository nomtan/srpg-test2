class_name JobSystem
extends Node

var database: JobDatabase
func setup(job_database: JobDatabase) -> void: database = job_database

func grant_job_exp(unit: BattleUnit, amount: int) -> Dictionary:
	var level_ups := unit.add_job_exp(amount)
	var learned: Array[String] = []
	var job := database.get_job(unit.job_id)
	if job:
		for entry in job.learnable_skills:
			if int(entry.job_level) <= unit.job_level and entry.skill_id not in unit.skill_ids:
				unit.skill_ids.append(entry.skill_id); learned.append(entry.skill_id)
	return {"amount": amount, "level_ups": level_ups, "learned": learned}
