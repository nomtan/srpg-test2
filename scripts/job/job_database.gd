class_name JobDatabase
extends Node

var jobs: Dictionary = {}

func _ready() -> void:
	# Basic jobs
	_add("fighter", "格闘士", JobData.JobRank.BASIC, {"str": 4, "dex": 2, "vit": 3, "mnd": 0, "int": 0, "agi": 2})
	_add("swordsman", "剣術士", JobData.JobRank.BASIC, {"str": 3, "dex": 2, "vit": 2, "mnd": 2, "int": 0, "agi": 2}, {}, [{"job_level": 1, "skill_id": "power_slash"}, {"job_level": 2, "skill_id": "guard_stance"}, {"job_level": 3, "skill_id": "earth_break"}])
	_add("lancer", "槍術士", JobData.JobRank.BASIC, {"str": 3, "dex": 2, "vit": 2, "mnd": -1, "int": 0, "agi": 4})
	_add("axeman", "斧術士", JobData.JobRank.BASIC, {"str": 6, "dex": -1, "vit": 4, "mnd": 0, "int": -1, "agi": -2})
	_add("archer", "弓術士", JobData.JobRank.BASIC, {"str": 2, "dex": 5, "vit": -1, "mnd": 0, "int": 0, "agi": 3}, {}, [{"job_level": 1, "skill_id": "aimed_shot"}, {"job_level": 3, "skill_id": "piercing_arrow"}])
	_add("dual_blader", "双剣士", JobData.JobRank.BASIC, {"str": 2, "dex": 4, "vit": -2, "mnd": 0, "int": 0, "agi": 6})
	_add("healer", "治癒士", JobData.JobRank.BASIC, {"str": -1, "dex": 0, "vit": -1, "mnd": 5, "int": 2, "agi": -1})
	_add("mage", "魔術士", JobData.JobRank.BASIC, {"str": -2, "dex": 0, "vit": -2, "mnd": 2, "int": 6, "agi": -1})
	# Advanced jobs
	_add("monk", "モンク", JobData.JobRank.ADVANCED, {"str": 7, "dex": 3, "vit": 5, "mnd": 1, "int": 0, "agi": 3}, {"fighter": 5})
	_add("holy_knight", "聖騎士", JobData.JobRank.ADVANCED, {"str": 5, "dex": 3, "vit": 5, "mnd": 4, "int": 1, "agi": 2}, {"swordsman": 5})
	_add("dragoon", "竜騎士", JobData.JobRank.ADVANCED, {"str": 5, "dex": 3, "vit": 4, "mnd": -1, "int": 0, "agi": 6}, {"lancer": 5})
	_add("heavy_knight", "重騎士", JobData.JobRank.ADVANCED, {"str": 7, "dex": -1, "vit": 8, "mnd": 1, "int": -1, "agi": -2}, {"axeman": 5})
	_add("sniper", "スナイパー", JobData.JobRank.ADVANCED, {"str": 3, "dex": 8, "vit": 0, "mnd": 1, "int": 0, "agi": 4}, {"archer": 5})
	_add("ninja", "忍者", JobData.JobRank.ADVANCED, {"str": 3, "dex": 6, "vit": -1, "mnd": 1, "int": 1, "agi": 8}, {"dual_blader": 5})
	_add("priest", "プリースト", JobData.JobRank.ADVANCED, {"str": 0, "dex": 1, "vit": 0, "mnd": 8, "int": 3, "agi": 0}, {"healer": 5})
	_add("sorcerer", "ソーサラー", JobData.JobRank.ADVANCED, {"str": -2, "dex": 1, "vit": -1, "mnd": 4, "int": 9, "agi": 0}, {"mage": 5})
	# Master jobs (data registration only in this phase)
	_add("sword_saint", "剣聖", JobData.JobRank.MASTER, {"str": 10, "dex": 7, "vit": 8, "mnd": 3, "int": 0, "agi": 5}, {"holy_knight": 5, "heavy_knight": 5})
	_add("paladin", "パラディン", JobData.JobRank.MASTER, {"str": 5, "dex": 3, "vit": 8, "mnd": 10, "int": 4, "agi": 1}, {"holy_knight": 5, "priest": 5})
	_add("magic_swordsman", "魔法剣士", JobData.JobRank.MASTER, {"str": 7, "dex": 4, "vit": 5, "mnd": 6, "int": 7, "agi": 4}, {"holy_knight": 5, "sorcerer": 5}, [{"job_level": 1, "skill_id": "aqua_edge"}, {"job_level": 3, "skill_id": "healing_water"}])
	_add("fortress_knight", "フォートレスナイト", JobData.JobRank.MASTER, {"str": 7, "dex": 3, "vit": 11, "mnd": 4, "int": 0, "agi": 3}, {"heavy_knight": 5, "holy_knight": 5})
	_add("spear_saint", "槍聖", JobData.JobRank.MASTER, {"str": 7, "dex": 9, "vit": 5, "mnd": 3, "int": 0, "agi": 10}, {"dragoon": 5, "sniper": 5})
	_add("gunslinger", "ガンスリンガー", JobData.JobRank.MASTER, {"str": 1, "dex": 11, "vit": 3, "mnd": 3, "int": 6, "agi": 7}, {"sniper": 5, "sorcerer": 5})
	_add("war_god", "武神", JobData.JobRank.MASTER, {"str": 11, "dex": 6, "vit": 10, "mnd": 3, "int": 0, "agi": 4}, {"monk": 5, "heavy_knight": 5})
	_add("fist_saint", "拳聖", JobData.JobRank.MASTER, {"str": 8, "dex": 9, "vit": 5, "mnd": 3, "int": 0, "agi": 11}, {"monk": 5, "ninja": 5})
	_add("assassin", "アサシン", JobData.JobRank.MASTER, {"str": 4, "dex": 10, "vit": -1, "mnd": 0, "int": 3, "agi": 11}, {"ninja": 5, "sniper": 5})
	_add("alchemist", "アルケミスト", JobData.JobRank.MASTER, {"str": 0, "dex": 7, "vit": 4, "mnd": 7, "int": 7, "agi": 4}, {"priest": 5, "sorcerer": 5})
	_add("scholar", "学者", JobData.JobRank.MASTER, {"str": -1, "dex": 3, "vit": 3, "mnd": 11, "int": 11, "agi": 0}, {"priest": 5, "sorcerer": 5})
	_add("necromancer", "ネクロマンサー", JobData.JobRank.MASTER, {"str": -2, "dex": 6, "vit": -1, "mnd": 7, "int": 11, "agi": 7}, {"sorcerer": 5, "ninja": 5})
	# Enemy-only compatibility jobs.
	_add("bandit", "Bandit", JobData.JobRank.BASIC, {"str": 4, "dex": 1, "vit": 2, "mnd": 0, "int": 0, "agi": 2}, {}, [{"job_level": 1, "skill_id": "heavy_attack"}], false)
	_add("enemy_archer", "Enemy Archer", JobData.JobRank.BASIC, {"str": 2, "dex": 4, "vit": 0, "mnd": 0, "int": 0, "agi": 2}, {}, [{"job_level": 1, "skill_id": "aimed_shot"}], false)
	_configure_weapon_types()

func _add(id: String, display_name: String, rank: JobData.JobRank, bonuses: Dictionary, requirements: Dictionary = {}, skills: Array[Dictionary] = [], selectable: bool = true) -> void:
	var growth := {"max_hp": 5, "max_ap": 1, "attack_power": 1, "defense": 1, "accuracy": 1, "evasion": 1}
	var job := JobData.create(id, display_name, growth, skills, rank, bonuses, requirements)
	job.player_selectable = selectable
	jobs[id] = job

func get_job(id: String) -> JobData: return jobs.get(id)
func get_all_job_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in jobs: result.append(id)
	return result
func get_growth(id: String) -> Dictionary:
	var job := get_job(id)
	return job.growth if job else {}

func _configure_weapon_types() -> void:
	var weapon_rules: Dictionary = {
		"fighter": [9], "swordsman": [1], "lancer": [3], "axeman": [2], "archer": [4],
		"dual_blader": [5, 6], "healer": [7, 8], "mage": [7], "monk": [9],
		"holy_knight": [1, 8], "dragoon": [3, 1], "heavy_knight": [2, 3],
		"sniper": [4, 5], "ninja": [5, 6], "priest": [7, 8], "sorcerer": [7],
		"sword_saint": [1, 6], "paladin": [1, 8], "magic_swordsman": [1, 7],
		"fortress_knight": [1, 2, 3], "spear_saint": [3], "gunslinger": [4],
		"war_god": [2, 9], "fist_saint": [9], "assassin": [5, 6],
		"alchemist": [7, 8], "scholar": [7], "necromancer": [7],
		"bandit": [2, 5], "enemy_archer": [4]
	}
	for job_id: String in weapon_rules:
		var job := get_job(job_id)
		if job:
			job.allowed_weapon_types.clear()
			for type: int in weapon_rules[job_id]: job.allowed_weapon_types.append(type)
