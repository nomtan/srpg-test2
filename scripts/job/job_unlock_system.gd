class_name JobUnlockSystem
extends Node

var job_database: JobDatabase

func setup(database: JobDatabase) -> void:
	job_database = database

func can_unlock_job(unit: BattleUnit, job_id: String) -> bool:
	var job := job_database.get_job(job_id)
	if not job or not job.player_selectable or job.unlock_pending: return false
	if job.job_rank == JobData.JobRank.MASTER:
		if job.required_jobs.size() != 1: return false
		var prerequisite := job_database.get_job(job.required_jobs[0])
		if not prerequisite or prerequisite.job_rank != JobData.JobRank.ADVANCED: return false
	for required_job_id: String in job.required_jobs:
		var owns_job := required_job_id in unit.unlocked_job_ids or unit.job_levels.has(required_job_id) \
			or required_job_id in [unit.main_job_id, unit.sub_job_id]
		if not owns_job: return false
		if unit.get_job_level_for(required_job_id) < int(job.required_job_levels.get(required_job_id, 1)):
			return false
	return true

func unlock_available_jobs(unit: BattleUnit) -> Array[String]:
	var unlocked: Array[String] = []
	for job_id: String in job_database.get_all_job_ids():
		if job_id in unit.unlocked_job_ids or not can_unlock_job(unit, job_id): continue
		unit.unlocked_job_ids.append(job_id)
		unlocked.append(job_id)
	return unlocked

func get_selectable_jobs(unit: BattleUnit) -> Array[String]:
	return unit.unlocked_job_ids.duplicate()
