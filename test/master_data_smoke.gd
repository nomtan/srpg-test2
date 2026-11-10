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
	_check_passive_slots_and_save(jobs, skills)
	await _check_reactions(skills)
	_check_stat_modifiers(jobs, skills, equipment)
	_check_skill_icons()
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

func _check_passive_slots_and_save(jobs: JobDatabase, skills: SkillDatabase) -> void:
	var unlocks := SkillUnlockSystem.new()
	unlocks.setup(jobs, skills)
	var progress := UnitProgressManager.new()
	progress.setup(jobs, unlocks)
	var unit := BattleUnit.new()
	unit.unit_id = "passive_smoke"
	for id: String in ["test_one", "test_two", "test_three", "test_four", "test_unlearned"]:
		var skill := GameDataLoader._make_skill({"id": id, "name": id, "type": "passive", "activationMode": "equipped", "effects": [], "triggers": []})
		_check(skill != null, "parse passive skill " + id)
		if skill:
			skills.skills[id] = skill
	unit.learned_skill_ids.assign(["test_one", "test_two", "test_three", "test_four", "power_slash"])
	_check(skills.get_passives_for_unit(unit).is_empty(), "learning alone does not activate a passive")
	_check(not unlocks.equip_passive_skill(unit, "test_unlearned") and not unlocks.equip_passive_skill(unit, "power_slash"), "passive slots reject unlearned and active skills")
	for id: String in ["test_one", "test_two", "test_three"]:
		_check(unlocks.equip_passive_skill(unit, id), "equip " + id)
	_check(not unlocks.equip_passive_skill(unit, "test_one") and not unlocks.equip_passive_skill(unit, "test_four"), "reject duplicate and fourth slot")
	unit.equipped_skill_ids.assign(["test_one", "power_slash"])
	var active := skills.get_skills_for_unit(unit)
	_check(active.size() == 1 and active[0].skill_id == "power_slash", "only active skills reach the battle list")
	unlocks.unequip_passive_skill(unit, "test_two")
	_check(skills.get_passives_for_unit(unit).size() == 2, "unequip deactivates passive")
	progress.update_progress_from_units([unit])
	var saved := progress.to_dict()
	unit.equipped_passive_skill_ids.clear()
	progress.apply_progress_to_unit(unit)
	_check(unit.equipped_passive_skill_ids == ["test_one", "test_three"], "restore passive loadout from save")
	saved[unit.unit_id].equipped_passive_skill_ids = ["test_one", "missing", "test_unlearned", "test_one", "power_slash", 9]
	progress.from_dict(saved)
	progress.apply_progress_to_unit(unit)
	_check(unit.equipped_passive_skill_ids == ["test_one"], "discard invalid, unlearned, active and duplicate IDs")
	saved[unit.unit_id].erase("equipped_passive_skill_ids")
	progress.from_dict(saved)
	progress.apply_progress_to_unit(unit)
	_check(unit.equipped_passive_skill_ids.is_empty(), "old save defaults to empty passive slots")
	for node: Node in [unit, progress, unlocks]:
		node.free()

func _check_reactions(skills: SkillDatabase) -> void:
	var counter := {"type": "counter_attack", "powerMultiplier": 1}
	var heal := {"type": "heal", "target": "self", "powerMultiplier": 1}
	var first := {"event": "on_attacked", "attackOrigins": ["active"], "hitResults": ["hit", "evade"], "chance": 0.5, "effects": [counter]}
	var second := first.merged({"chance": 1}, true)
	var recovery := first.merged({"attackOrigins": ["active", "reaction"], "chance": 1, "effects": [counter, heal]}, true)
	skills.skills["test_counter"] = GameDataLoader._make_skill({"id": "test_counter", "name": "Counter", "type": "passive", "activationMode": "equipped", "triggers": [first, second]})
	skills.skills["test_recovery"] = GameDataLoader._make_skill({"id": "test_recovery", "name": "Recovery", "type": "passive", "activationMode": "equipped", "triggers": [recovery]})
	var grid := GridSystem.new()
	grid.generate_grid()
	var manager := UnitManager.new()
	manager.grid = grid
	var attacker := BattleUnit.new()
	var defender := BattleUnit.new()
	attacker.configure("attacker", "Attacker", Vector2i(10, 10), "player")
	defender.configure("defender", "Defender", Vector2i(11, 10), "enemy")
	for unit: BattleUnit in [attacker, defender]:
		var position := Vector2i(unit.grid_x, unit.grid_z)
		grid.get_cell(position).height = 0
		grid.set_occupied_unit(position, unit)
		manager.units.append(unit)
	attacker.hp = 30
	attacker.equipped_passive_skill_ids.append("test_recovery")
	defender.equipped_passive_skill_ids.append("test_counter")
	defender.has_acted = true
	defender.ap = 0
	var attacks := AttackSystem.new()
	attacks.setup(grid, null)
	attacks.setup_reactions(skills, manager)
	var events: Array[AttackContext] = []
	attacks.on_attacked.connect(func(context: AttackContext) -> void: events.append(context))
	for hit: bool in [true, false]:
		_seed_chance(true)
		var context := attacks.notify_attacked(attacker, defender, hit, 5 if hit else 0, AttackContext.Origin.ACTIVE)
		_check(events.size() == 2 and events[0].origin == AttackContext.Origin.REACTION and events[1] == context,
			"active hit or evade sends exactly one event and one counter")
		_check(context.reaction_messages.size() == 2 and "recovers" in context.reaction_messages[1], "reaction attacks allow healing without another counter")
		_check(defender.has_acted and defender.ap == 0 and attacker.ap == 30, "reaction leaves AP and action state unchanged")
		attacker.hp = 30
		events.clear()
	_seed_chance(false)
	var failed := attacks.notify_attacked(attacker, defender, false, 0, AttackContext.Origin.ACTIVE)
	_check(events.size() == 1 and failed.reaction_messages.size() == 1 and "did not trigger" in failed.reaction_messages[0],
		"a failed 50% roll cannot retry via the second trigger")
	defender.equipped_passive_skill_ids.clear()
	events.clear()
	var attack := await attacks.execute_attack(attacker, defender)
	_check(events.size() == 1 and events[0].hit == attack.hit and events[0].damage == attack.damage, "normal attack publishes its resolved result")
	events.clear()
	var elements := ElementSystem.new()
	var system := SkillSystem.new()
	system.setup(grid, manager, attacks, elements, null)
	var skill_result := system.execute_skill(attacker, skills.get_skill("power_slash"), Vector2i(11, 10))
	_check(skill_result.success and events.size() == 1 and events[0].origin == AttackContext.Origin.ACTIVE, "attack skill publishes an active attack event")
	defender.take_damage(defender.hp)
	defender.equipped_passive_skill_ids.append("test_counter")
	events.clear()
	attacks.notify_attacked(attacker, defender, true, 999, AttackContext.Origin.ACTIVE)
	_check(events.size() == 1, "dead defenders cannot react")
	for node: Node in [system, elements, attacks, manager, grid, attacker, defender]:
		node.free()

func _seed_chance(success: bool) -> void:
	for value in range(100):
		seed(value)
		if (randf() < 0.5) == success:
			seed(value)
			return

func _check_stat_modifiers(jobs: JobDatabase, skills: SkillDatabase, equipment: EquipmentDatabase) -> void:
	var effects := [
		{"type": "stat_bonus", "stat": "str", "mode": "flat", "value": 6},
		{"type": "stat_bonus", "stat": "str", "mode": "percent", "value": 50},
		{"type": "stat_bonus", "stat": "accuracy", "mode": "flat", "value": 8},
		{"type": "stat_bonus", "stat": "max_ap", "mode": "percent", "value": 50},
		{"type": "stat_bonus", "stat": "max_hp", "mode": "flat", "value": 20},
		{"type": "stat_bonus", "stat": "fire_resistance", "mode": "flat", "value": 15},
		{"type": "stat_bonus", "stat": "evasion", "mode": "flat", "value": 100, "condition": "unknown"},
	]
	var skill := GameDataLoader._make_skill({"id": "test_stats", "name": "Stats", "type": "passive", "activationMode": "equipped", "effects": effects})
	_check(skill.passive_effects.size() == 6, "unsupported conditional modifier is omitted")
	skills.skills[skill.skill_id] = skill
	var calculator := StatusCalculator.new()
	calculator.setup(jobs, equipment, skills)
	var unlocks := SkillUnlockSystem.new()
	unlocks.setup(jobs, skills)
	var unit := BattleUnit.new()
	unit.main_job_id = "swordsman"
	unit.equipped_weapon_id = "iron_sword"
	unit.learned_skill_ids.append(skill.skill_id)
	unit.refresh_build_stats(calculator)
	var accuracy := unit.accuracy
	var evasion := unit.evasion
	var hp := unit.max_hp
	_check(unit.strength == 14 and unit.max_ap == 30, "unequipped passive leaves job and weapon stats unchanged")
	_check(unlocks.equip_passive_skill(unit, skill.skill_id), "equip stat passive")
	for i in range(2):
		unit.refresh_build_stats(calculator)
		_check(unit.strength == 30 and unit.accuracy == accuracy + 8 and unit.evasion == evasion, "flat and percentage modifiers apply once")
		_check(unit.max_hp == hp + 20 and unit.max_ap == 45 and unit.build_stats.elemental_resistances.fire == 15, "HP, AP and elemental modifiers apply")
	_check(UnitProgressData.from_unit(unit).to_dict().max_ap == 30, "save records base AP without passive bonus")
	unlocks.unequip_passive_skill(unit, skill.skill_id)
	unit.refresh_build_stats(calculator)
	_check(unit.max_hp == hp and unit.max_ap == 30 and unit.accuracy == accuracy and unit.strength == 14, "unequipping restores base values")
	for node: Node in [unit, unlocks, calculator]:
		node.free()

func _check_skill_icons() -> void:
	var skill := SkillData.new()
	var fallback := skill.get_icon()
	_check(fallback != null, "missing icon uses shared placeholder")
	_check(GameDataLoader._skill_icon_path("/skill-icons/power_slash.webp") == "res://admin/public/skill-icons/power_slash.webp", "admin icon path maps to shared image")
	_check(GameDataLoader._skill_icon_path("/skill-icons/../icon.png").is_empty(), "invalid icon path is ignored")
	skill.icon_path = "res://admin/public/skill-icons/nonexistent_smoke.png"
	_check(skill.get_icon() == fallback, "missing image falls back")
	var path := "user://skill-icon-smoke-%d.png" % Time.get_ticks_usec()
	var sample := Image.create_empty(12, 12, false, Image.FORMAT_RGBA8)
	sample.fill(Color.CYAN)
	_check(sample.save_png(path) == OK, "write test icon")
	skill.icon_path = path
	var texture := skill.get_icon()
	_check(texture != null and texture != fallback and texture.get_width() == 12, "uploaded image can load before importing")
	DirAccess.remove_absolute(path)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("Master data smoke: " + label)
