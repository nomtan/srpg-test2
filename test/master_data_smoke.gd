extends Node
## Run with: godot --headless --path . res://test/master_data_smoke.tscn

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var jobs := JobDatabase.new()
	var skills := SkillDatabase.new()
	var equipment := EquipmentDatabase.new()
	jobs._ready()
	skills._register_builtins()
	equipment._register_builtins()
	var builtin_jobs := jobs.jobs.duplicate()
	var builtin_skills := skills.skills.duplicate()
	var builtin_equipment := equipment.equipments.duplicate()
	GameDataLoader.load_skills(skills.skills)
	GameDataLoader.load_equipment(equipment.equipments)
	GameDataLoader.load_jobs(jobs.jobs, skills.skills)
	_compare("jobs", jobs.jobs, builtin_jobs, 31)
	_compare("skills", skills.skills, builtin_skills, 8)
	_compare("equipment", equipment.equipments, builtin_equipment, 17)
	_check_fallback(jobs.jobs, skills.skills)
	_check_save_and_battle(jobs, skills, equipment)
	jobs.free()
	skills.free()
	equipment.free()
	print("Master data smoke: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _compare(category: String, loaded: Dictionary, builtin: Dictionary, count: int) -> void:
	_check(loaded.size() == count and builtin.size() == count, category + " count")
	for id: String in builtin:
		var before: Resource = builtin[id]
		var after: Resource = loaded.get(id)
		_check(after != null and after != before, "%s/%s loaded from JSON" % [category, id])
		if after == null:
			continue
		for property: Dictionary in before.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_check(after.get(property.name) == before.get(property.name), "%s/%s.%s matches built-in" % [category, id, property.name])

func _check_fallback(jobs: Dictionary, skills: Dictionary) -> void:
	var folder := "user://master-data-smoke-%d/jobs" % Time.get_ticks_usec()
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "create isolated fixture folder")
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/admin/jobs/swordsman.json"))
	var fixtures := {
		"a_duplicate": JSON.stringify(sample),
		"z_duplicate": JSON.stringify(sample),
		"swordsman": "{invalid",
		"monk": JSON.stringify(_job_fixture(sample, "monk", {}, [{"skill_id": "missing", "job_level": 1}])),
		"a_dependent": JSON.stringify(_job_fixture(sample, "a_dependent", {"z_invalid": 1})),
		"z_invalid": JSON.stringify(_job_fixture(sample, "z_invalid", {"missing": 1})),
		"valid": JSON.stringify(_job_fixture(sample, "valid", {"swordsman": 1})),
	}
	for id: String in fixtures:
		var file := FileAccess.open(folder.path_join(id + ".json"), FileAccess.WRITE)
		_check(file != null, "write fixture " + id)
		if file:
			file.store_string(fixtures[id])
			file.close()
	var result := jobs.duplicate()
	GameDataLoader.load_jobs(result, skills, folder.get_base_dir())
	_check(result.get("swordsman") == jobs.swordsman and result.get("monk") == jobs.monk, "invalid rows keep fallback records")
	_check(not result.has("a_dependent") and not result.has("z_invalid"), "dangling prerequisite chain is rejected")
	_check(result.has("valid") and result.valid.get("required_job_levels") == {"swordsman": 1}, "valid row can reference a fallback job")
	for id: String in fixtures:
		DirAccess.remove_absolute(folder.path_join(id + ".json"))
	DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(folder.get_base_dir())

func _job_fixture(sample: Dictionary, id: String, requirements: Dictionary, skills: Array = []) -> Dictionary:
	return sample.merged({"id": id, "requiredJobLevels": requirements, "learnableSkills": skills}, true)

func _check_save_and_battle(jobs: JobDatabase, skills: SkillDatabase, equipment: EquipmentDatabase) -> void:
	var progress := UnitProgressManager.new()
	progress.setup(jobs)
	var save := SaveManager.new()
	var migrated := save.migrate_save_data({"units": {"smoke": {"main_job_id": "swordsman", "equipped_skill_ids": ["guard_stance"], "equipped_weapon_id": "iron_sword"}}})
	progress.from_dict(migrated.units)
	var unit := BattleUnit.new()
	unit.unit_id = "smoke"
	progress.apply_progress_to_unit(unit)
	_check(unit.main_job_name == jobs.get_job("swordsman").job_name and unit.equipped_skill_ids == ["guard_stance"], "legacy save job and skill IDs resolve")
	var grid := GridSystem.new()
	grid.generate_grid()
	var manager := UnitManager.new()
	manager.grid = grid
	manager.units.append(unit)
	grid.set_occupied_unit(Vector2i(unit.grid_x, unit.grid_z), unit)
	var system := SkillSystem.new()
	system.setup(grid, manager, null, null, null, null, equipment)
	var guard := skills.get_skill("guard_stance")
	unit.ap = 12
	var result := system.execute_skill(unit, guard, Vector2i(unit.grid_x, unit.grid_z))
	_check(result.success and unit.ap == 6 and unit.temporary_defense_bonus == 3, "loaded guard stance preserves combat effects")
	for node: Node in [system, manager, grid, unit, progress, save]:
		node.free()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("Master data smoke: " + label)
