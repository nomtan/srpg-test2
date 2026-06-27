class_name JobData
extends Resource

enum JobRank { BASIC, ADVANCED, MASTER }

var job_id: String
var job_name: String
var growth: Dictionary
var learnable_skills: Array[Dictionary] = []
var job_rank: JobRank = JobRank.BASIC
var required_jobs: Array[String] = []
var required_job_levels: Dictionary = {}
var stat_bonus: Dictionary = {"str": 0, "dex": 0, "vit": 0, "mnd": 0, "int": 0, "agi": 0}
var hp_bonus := 0
var base_move_range := 4
var base_jump_height := 1
var speed_modifier := 1.0
var player_selectable := true

static func create(id: String, display_name: String, values: Dictionary, skills: Array[Dictionary] = [], rank: JobRank = JobRank.BASIC, bonuses: Dictionary = {}, requirements: Dictionary = {}) -> JobData:
	var job := JobData.new()
	job.job_id = id; job.job_name = display_name; job.growth = values; job.learnable_skills = skills
	job.job_rank = rank
	for key: String in job.stat_bonus:
		job.stat_bonus[key] = int(bonuses.get(key, 0))
	job.hp_bonus = int(bonuses.get("hp", 0))
	job.base_move_range = int(bonuses.get("move", 4))
	job.base_jump_height = int(bonuses.get("jump", 1))
	job.speed_modifier = float(bonuses.get("speed_modifier", 1.0))
	job.required_jobs.clear()
	for required_id: Variant in requirements.keys():
		job.required_jobs.append(str(required_id))
	job.required_job_levels = requirements.duplicate(true)
	return job
