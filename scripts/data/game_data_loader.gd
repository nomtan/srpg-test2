class_name GameDataLoader
extends RefCounted

const ROOT := "res://data/admin"
const JOB_GROWTH := ["max_hp", "max_ap", "attack_power", "defense", "accuracy", "evasion"]
const STATS := ["str", "dex", "vit", "mnd", "int", "agi"]
const BUILD_STATS := ["accuracy", "critical_rate", "evasion", "move_range", "jump_height"]
const ELEMENTS := ["fire", "earth", "water", "thunder", "wind", "ice", "dark", "light"]
const SKILL_NUMBERS := {
	"apCost": "ap_cost", "power": "power", "accuracyModifier": "accuracy_modifier",
	"minRange": "min_range", "maxRange": "max_range", "areaRadius": "area_radius",
	"criticalModifier": "critical_modifier",
}
const WEAPON_NUMBERS := {
	"weaponPower": "weapon_power", "accuracyModifier": "weapon_accuracy_modifier",
	"criticalModifier": "weapon_critical_modifier", "minRange": "min_range", "maxRange": "max_range",
}

static func load_skills(skills: Dictionary, root: String = ROOT) -> void:
	var records := _read_records(root.path_join("skills"))
	for id: String in records:
		var skill := _make_skill(records[id])
		if skill == null:
			_warn("skills", id, "invalid skill fields")
			continue
		skills[id] = skill

static func load_jobs(jobs: Dictionary, skills: Dictionary, root: String = ROOT) -> void:
	var candidates := {}
	var records := _read_records(root.path_join("jobs"))
	for id: String in records:
		var job := _make_job(records[id])
		if job == null:
			_warn("jobs", id, "invalid job fields")
			continue
		var missing_skill := ""
		for entry: Dictionary in job.learnable_skills:
			if not skills.has(entry.skill_id):
				missing_skill = entry.skill_id
				break
		if not missing_skill.is_empty():
			_warn("jobs", id, "unknown skill '%s'" % missing_skill)
			continue
		candidates[id] = job
	# Removing a new invalid job can leave another new job with a dangling prerequisite.
	var changed := true
	while changed:
		changed = false
		for id: String in candidates.keys():
			for prerequisite: String in candidates[id].required_jobs:
				if not jobs.has(prerequisite) and not candidates.has(prerequisite):
					_warn("jobs", id, "unknown prerequisite '%s'" % prerequisite)
					candidates.erase(id)
					changed = true
					break
	jobs.merge(candidates, true)

static func load_equipment(equipment: Dictionary, root: String = ROOT) -> void:
	var records := _read_records(root.path_join("equipment"))
	for id: String in records:
		var item := _make_equipment(records[id], equipment.get(id) as WeaponData)
		if item == null:
			_warn("equipment", id, "invalid equipment fields")
			continue
		equipment[id] = item

static func _read_records(directory: String) -> Dictionary:
	var records := {}
	var files := DirAccess.get_files_at(directory)
	var seen_ids := {}
	var category := directory.get_file()
	var id_pattern := RegEx.create_from_string("^[a-zA-Z0-9_-]+$")
	for file: String in files:
		if file.get_extension() != "json":
			continue
		var source := FileAccess.open(directory.path_join(file), FileAccess.READ)
		if source == null:
			_warn(category, file, "could not read file")
			continue
		var json := JSON.new()
		if json.parse(source.get_as_text()) != OK or not json.data is Dictionary:
			_warn(category, file, "expected a JSON object (line %d)" % json.get_error_line())
			continue
		var row: Dictionary = json.data
		var id: Variant = row.get("id")
		if not id is String or id_pattern.search(id) == null:
			_warn(category, file, "invalid ID")
			continue
		if seen_ids.has(id):
			_warn(category, file, "duplicate ID '%s'" % id)
		seen_ids[id] = true
		if file.get_basename() != id:
			_warn(category, file, "ID '%s' must match the filename" % id)
			continue
		if not row.get("name") is String or row.name.strip_edges().is_empty():
			_warn(category, id, "missing name")
			continue
		records[id] = row
	return records

static func _make_job(row: Dictionary) -> JobData:
	if not _enum_has(JobData.JobRank, row.get("rank")) or not _int_fields(row.get("growth"), JOB_GROWTH):
		return null
	if not _int_fields(row.get("statBonus"), STATS) or not _int_fields(row, ["hpBonus", "baseMoveRange", "baseJumpHeight"]):
		return null
	if row.baseMoveRange < 0 or row.baseJumpHeight < 0 or not _positive_number(row.get("speedModifier")):
		return null
	if not row.get("playerSelectable") is bool or not _resource_path(row.get("bodyScenePath")):
		return null
	if not row.get("requiredJobLevels") is Dictionary or not row.get("learnableSkills") is Array or not row.get("allowedWeaponTypes") is Array:
		return null
	var requirements := {}
	for id: String in row.requiredJobLevels:
		var level: Variant = row.requiredJobLevels[id]
		if id == row.id or not _integer(level) or level < 1:
			return null
		requirements[id] = int(level)
	var skills: Array[Dictionary] = []
	var seen_skills := {}
	for entry: Variant in row.learnableSkills:
		if not entry is Dictionary or not entry.get("skill_id") is String or entry.skill_id.is_empty():
			return null
		if not _integer(entry.get("job_level")) or entry.job_level < 1 or seen_skills.has(entry.skill_id):
			return null
		seen_skills[entry.skill_id] = true
		var skill: Dictionary = entry.duplicate()
		skill.job_level = int(entry.job_level)
		skills.append(skill)
	var weapons: Array[int] = []
	for weapon: Variant in row.allowedWeaponTypes:
		if not _integer(weapon) or weapon == WeaponData.WeaponType.NONE or not int(weapon) in WeaponData.WeaponType.values() or int(weapon) in weapons:
			return null
		weapons.append(int(weapon))
	var bonuses: Dictionary = row.statBonus.duplicate()
	bonuses.merge({"hp": row.hpBonus, "move": row.baseMoveRange, "jump": row.baseJumpHeight, "speed_modifier": row.speedModifier}, true)
	var growth := _int_values(row.growth, JOB_GROWTH)
	var job := JobData.create(row.id, row.name, growth, skills, JobData.JobRank[row.rank], bonuses, requirements)
	job.player_selectable = row.playerSelectable
	job.body_scene_path = row.bodyScenePath
	job.allowed_weapon_types = weapons
	return job

static func _make_skill(row: Dictionary) -> SkillData:
	if not row.get("type") is String or not _enum_has(SkillData.SkillType, row.type.to_upper()):
		return null
	if row.type.to_upper() == "PASSIVE":
		return _make_passive_skill(row)
	if not _enum_has(SkillData.TargetType, row.get("targetType")) or not _enum_has(SkillData.RangeType, row.get("rangeType")):
		return null
	if not _enum_has(BattleUnit.ElementType, row.get("element")) or not _enum_has(SkillData.ScalingType, row.get("scalingType")):
		return null
	if not _int_fields(row, SKILL_NUMBERS.keys()) or not _ranges_valid(row) or row.apCost < 0 or row.areaRadius < 0:
		return null
	if not row.get("requiresLineOfSight") is bool or not row.get("description", "") is String:
		return null
	var skill := SkillData.new()
	skill.skill_id = row.id
	skill.skill_name = row.name
	skill.description = row.get("description", "")
	skill.skill_type = SkillData.SkillType[row.type.to_upper()]
	skill.target_type = SkillData.TargetType[row.targetType]
	skill.range_type = SkillData.RangeType[row.rangeType]
	skill.element = BattleUnit.ElementType[row.element]
	skill.scaling_type = SkillData.ScalingType[row.scalingType]
	skill.requires_line_of_sight = row.requiresLineOfSight
	for key: String in SKILL_NUMBERS:
		skill.set(SKILL_NUMBERS[key], int(row[key]))
	return skill

static func _make_passive_skill(row: Dictionary) -> SkillData:
	if row.get("activationMode") != "equipped" or not row.get("description", "") is String:
		return null
	var skill := SkillData.new()
	for key: String in ["effects", "triggers"]:
		var entries: Variant = row.get(key, [])
		if not entries is Array:
			return null
		for entry: Variant in entries:
			if not entry is Dictionary:
				return null
			if key == "effects":
				skill.passive_effects.append(entry)
			else:
				skill.passive_triggers.append(entry)
	skill.skill_id = row.id
	skill.skill_name = row.name
	skill.description = row.get("description", "")
	skill.skill_type = SkillData.SkillType.PASSIVE
	return skill

static func _make_equipment(row: Dictionary, built_in_weapon: WeaponData) -> EquipmentData:
	if not row.get("type") is String or not _enum_has(EquipmentData.EquipmentType, row.type.to_upper()):
		return null
	if not _integer(row.get("price")) or row.price < 0 or not row.get("description") is String:
		return null
	if not _int_fields(row.get("statBonus"), STATS, false) or not _int_fields(row.get("buildBonus"), BUILD_STATS, false):
		return null
	if not _int_fields(row.get("elementalResistanceBonus"), ELEMENTS, false):
		return null
	var type: EquipmentData.EquipmentType = EquipmentData.EquipmentType[row.type.to_upper()]
	var item: EquipmentData
	match type:
		EquipmentData.EquipmentType.WEAPON:
			item = _make_weapon(row, built_in_weapon)
		EquipmentData.EquipmentType.ARMOR:
			if row.get("armorCategory") in ["light", "medium", "heavy", "robe"]:
				var armor := ArmorData.new()
				armor.armor_category = row.armorCategory
				item = armor
		EquipmentData.EquipmentType.ACCESSORY:
			item = AccessoryData.new()
	if item == null:
		return null
	item.configure(row.id, row.name, type, row.statBonus, row.buildBonus)
	item.description = row.description
	item.price = int(row.price)
	item.elemental_resistance_bonus.merge(_int_values(row.elementalResistanceBonus, ELEMENTS), true)
	return item

static func _make_weapon(row: Dictionary, built_in: WeaponData) -> WeaponData:
	if not _enum_has(WeaponData.WeaponType, row.get("weaponType")) or row.weaponType == "NONE":
		return null
	if not _int_fields(row, WEAPON_NUMBERS.keys()) or not _ranges_valid(row) or not row.get("requiresLineOfSight") is bool:
		return null
	# Preserve legacy visual paths, including the original short bow's optional model.
	var original_path := built_in.visual_model_path if built_in else ""
	if not _resource_path(row.get("visualModelPath"), original_path) or not _positive_number(row.get("visualScale")):
		return null
	var weapon := WeaponData.new()
	weapon.weapon_type = WeaponData.WeaponType[row.weaponType]
	weapon.requires_line_of_sight = row.requiresLineOfSight
	weapon.visual_model_path = row.visualModelPath
	weapon.visual_scale = float(row.visualScale)
	for key: String in WEAPON_NUMBERS:
		weapon.set(WEAPON_NUMBERS[key], int(row[key]))
	return weapon

static func _ranges_valid(row: Dictionary) -> bool:
	return row.minRange >= 0 and row.maxRange >= row.minRange

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and absf(float(value)) <= 9007199254740991.0 and floorf(float(value)) == float(value)

static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0

static func _int_fields(value: Variant, fields: Array, required: bool = true) -> bool:
	if not value is Dictionary:
		return false
	for key: String in fields:
		if (required or value.has(key)) and not _integer(value.get(key)):
			return false
	return true

static func _int_values(value: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for key: String in fields:
		if value.has(key):
			result[key] = int(value[key])
	return result

static func _enum_has(values: Dictionary, value: Variant) -> bool:
	return value is String and values.has(value)

static func _resource_path(value: Variant, original_path: String = "") -> bool:
	return value is String and (value.is_empty() or value == original_path or (value.begins_with("res://") and ResourceLoader.exists(value)))

static func _warn(category: String, id: String, reason: String) -> void:
	push_warning("Master data [%s/%s]: %s; keeping built-in data where available" % [category, id, reason])
