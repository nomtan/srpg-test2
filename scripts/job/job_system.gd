class_name JobSystem
extends Node

var database: JobDatabase
func setup(job_database: JobDatabase) -> void: database = job_database

func grant_job_exp(unit: BattleUnit, amount: int) -> Dictionary:
	var level_ups := unit.add_job_exp(amount)
	var unlocked: Array[String] = []
	var job := database.get_job(unit.main_job_id)
	if job:
		for entry in job.learnable_skills:
			for level_up in level_ups:
				if int(entry.job_level) == int(level_up.job_level): unlocked.append(entry.skill_id)
	return {"amount": amount, "level_ups": level_ups, "learned": unlocked}
