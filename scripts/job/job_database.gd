class_name JobDatabase
extends Node

var jobs: Dictionary = {}
func _ready() -> void:
	jobs["swordsman"] = JobData.create("swordsman", "剣術師", {"max_hp": 6, "max_ap": 1, "attack_power": 2, "defense": 1, "accuracy": 1, "evasion": 0}, [{"job_level": 1, "skill_id": "power_slash"}, {"job_level": 2, "skill_id": "guard_stance"}, {"job_level": 3, "skill_id": "earth_break"}])
	jobs["magic_swordsman"] = JobData.create("magic_swordsman", "魔法剣士", {"max_hp": 4, "max_ap": 2, "attack_power": 1, "defense": 1, "accuracy": 1, "evasion": 1}, [{"job_level": 1, "skill_id": "aqua_edge"}, {"job_level": 3, "skill_id": "healing_water"}])
	jobs["archer"] = JobData.create("archer", "弓術師", {"max_hp": 4, "max_ap": 1, "attack_power": 1, "defense": 0, "accuracy": 2, "evasion": 1}, [{"job_level": 1, "skill_id": "aimed_shot"}, {"job_level": 3, "skill_id": "piercing_arrow"}])
	jobs["bandit"] = JobData.create("bandit", "盗賊", {"max_hp": 4, "max_ap": 1, "attack_power": 1, "defense": 0, "accuracy": 1, "evasion": 2}, [{"job_level": 1, "skill_id": "heavy_attack"}])
	jobs["enemy_archer"] = JobData.create("enemy_archer", "敵弓兵", {"max_hp": 4, "max_ap": 1, "attack_power": 1, "defense": 0, "accuracy": 1, "evasion": 1}, [{"job_level": 1, "skill_id": "aimed_shot"}])
func get_job(id: String) -> JobData: return jobs.get(id)
func get_growth(id: String) -> Dictionary:
	var job := get_job(id)
	return job.growth if job else {}
