class_name AdminMasterLoader
extends RefCounted

## Reads admin-managed JSON snapshots. Missing/invalid files are skipped.
## Keep the existing hard-coded databases as fallback during migration.
const ROOT := "res://data/admin"

static func load_records(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not category in ["skills", "jobs", "equipment"]:
		return result
	var directory := DirAccess.open(ROOT.path_join(category))
	if directory == null:
		return result
	directory.list_dir_begin()
	var filename := directory.get_next()
	while filename != "":
		if not directory.current_is_dir() and filename.ends_with(".json"):
			var file := FileAccess.open(ROOT.path_join(category).path_join(filename), FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary and str(parsed.get("id", "")) == filename.trim_suffix(".json"):
					result.append(parsed)
				else:
					push_warning("Invalid admin data: " + filename)
		filename = directory.get_next()
	directory.list_dir_end()
	return result

static func apply_skills(database: SkillDatabase) -> int:
	var loaded := 0
	for record: Dictionary in load_records("skills"):
		var id := str(record.get("id", ""))
		var type_name := str(record.get("type", "attack")).to_upper()
		var target_name := str(record.get("targetType", "ENEMY"))
		var range_name := str(record.get("rangeType", "MELEE"))
		var element_name := str(record.get("element", "NONE"))
		if not SkillData.SkillType.has(type_name) or not SkillData.TargetType.has(target_name) or not SkillData.RangeType.has(range_name) or not BattleUnit.ElementType.has(element_name):
			push_warning("Invalid skill enum: " + id)
			continue
		var skill := SkillData.create(id, str(record.get("name", id)), SkillData.SkillType[type_name], SkillData.TargetType[target_name], SkillData.RangeType[range_name], BattleUnit.ElementType[element_name], int(record.get("apCost", 0)), int(record.get("power", 0)), int(record.get("accuracyModifier", 0)), int(record.get("minRange", 1)), int(record.get("maxRange", 1)), int(record.get("areaRadius", 0)), bool(record.get("requiresLineOfSight", true)))
		skill.description = str(record.get("description", ""))
		skill.critical_modifier = int(record.get("criticalModifier", 0))
		var scaling := str(record.get("scalingType", "PHYSICAL"))
		if SkillData.ScalingType.has(scaling):
			skill.scaling_type = SkillData.ScalingType[scaling]
		database.skills[id] = skill
		loaded += 1
	return loaded

static func apply_jobs(database: JobDatabase) -> int:
	var loaded := 0
	for record: Dictionary in load_records("jobs"):
		var id := str(record.get("id", ""))
		var rank_name := str(record.get("rank", "BASIC"))
		if not JobData.JobRank.has(rank_name):
			push_warning("Invalid job rank: " + id)
			continue
		var learnable: Array[Dictionary] = []
		for entry: Variant in record.get("learnableSkills", []):
			if entry is Dictionary:
				learnable.append(entry)
		var bonuses: Dictionary = record.get("statBonus", {}).duplicate(true)
		bonuses["hp"] = int(record.get("hpBonus", 0))
		bonuses["move"] = int(record.get("baseMoveRange", 4))
		bonuses["jump"] = int(record.get("baseJumpHeight", 1))
		bonuses["speed_modifier"] = float(record.get("speedModifier", 1.0))
		var job := JobData.create(id, str(record.get("name", id)), record.get("growth", {}), learnable, JobData.JobRank[rank_name], bonuses, record.get("requiredJobLevels", {}))
		job.player_selectable = bool(record.get("playerSelectable", true))
		job.body_scene_path = str(record.get("bodyScenePath", ""))
		for weapon_type: Variant in record.get("allowedWeaponTypes", []):
			job.allowed_weapon_types.append(int(weapon_type))
		database.jobs[id] = job
		loaded += 1
	return loaded
