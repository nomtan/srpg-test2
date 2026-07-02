class_name PreBattleSetupPanel
extends PanelContainer

signal battle_started

var units: Array[BattleUnit]
var jobs: JobDatabase
var skills: SkillDatabase
var unlocks: SkillUnlockSystem
var job_unlocks: JobUnlockSystem
var status_calculator: Node
var equipment_database: Node
var equipment_system: Node
var selected_unit: BattleUnit
var refreshing := false

@onready var unit_list: VBoxContainer = $Layout/UnitList
@onready var name_label: Label = $Layout/Detail/Name
@onready var main_selector: OptionButton = $Layout/Detail/MainJob
@onready var sub_selector: OptionButton = $Layout/Detail/SubJob
@onready var equipped_list: VBoxContainer = $Layout/Detail/Skills/Equipped
@onready var available_list: VBoxContainer = $Layout/Detail/Skills/Available
@onready var message_label: Label = $Layout/Detail/Message
@onready var weapon_selector: OptionButton = $Layout/Detail/Weapon
@onready var armor_selector: OptionButton = $Layout/Detail/Armor
@onready var accessory_selector: OptionButton = $Layout/Detail/Accessory

func _ready() -> void:
	main_selector.item_selected.connect(func(_index: int) -> void: _change_job(true))
	sub_selector.item_selected.connect(func(_index: int) -> void: _change_job(false))
	weapon_selector.item_selected.connect(func(_index: int) -> void: _change_equipment(EquipmentData.EquipmentType.WEAPON))
	armor_selector.item_selected.connect(func(_index: int) -> void: _change_equipment(EquipmentData.EquipmentType.ARMOR))
	accessory_selector.item_selected.connect(func(_index: int) -> void: _change_equipment(EquipmentData.EquipmentType.ACCESSORY))
	$Layout/Detail/StartBattle.pressed.connect(_start_battle)

func setup(player_units: Array[BattleUnit], job_database: JobDatabase, skill_database: SkillDatabase, unlock_system: SkillUnlockSystem, job_unlock_system: JobUnlockSystem = null, calculator: Node = null, equipment_db: Node = null, equip_system: Node = null) -> void:
	units = player_units; jobs = job_database; skills = skill_database; unlocks = unlock_system
	job_unlocks = job_unlock_system; status_calculator = calculator
	equipment_database = equipment_db; equipment_system = equip_system
	for child in unit_list.get_children(): child.queue_free()
	for unit in units:
		if job_unlocks: job_unlocks.unlock_available_jobs(unit)
		_ensure_distinct_jobs(unit)
		var button := Button.new(); button.text = unit.unit_name
		button.pressed.connect(func() -> void: _select_unit(unit))
		unit_list.add_child(button)
	if not units.is_empty(): _select_unit(units[0])
	visible = true

func _select_unit(unit: BattleUnit) -> void:
	selected_unit = unit; refreshing = true
	unlocks.validate_equipped_skills(unit)
	_ensure_distinct_jobs(unit)
	_validate_equipped_weapon()
	if status_calculator: unit.refresh_build_stats(status_calculator)
	name_label.text = "%s  Lv %d" % [unit.unit_name, unit.level]
	_populate_jobs(main_selector, unit.main_job_id)
	_populate_jobs(sub_selector, unit.sub_job_id, unit.main_job_id)
	_populate_equipment_selectors()
	refreshing = false
	_refresh_skills()

func _populate_jobs(selector: OptionButton, selected_id: String, excluded_id: String = "") -> void:
	selector.clear()
	for job_id in selected_unit.unlocked_job_ids:
		if job_id == excluded_id: continue
		var job := jobs.get_job(job_id)
		if not job or not job.player_selectable: continue
		selector.add_item(job.job_name)
		selector.set_item_metadata(selector.item_count - 1, job_id)
		if job_id == selected_id: selector.select(selector.item_count - 1)

func _change_job(is_main: bool) -> void:
	if refreshing or not selected_unit: return
	var selector := main_selector if is_main else sub_selector
	if selector.selected < 0: return
	var job_id: String = selector.get_item_metadata(selector.selected)
	var job := jobs.get_job(job_id)
	if is_main:
		selected_unit.main_job_id = job_id; selected_unit.main_job_name = job.job_name
		selected_unit.job_id = job_id; selected_unit.job_name = job.job_name
		selected_unit.job_level = selected_unit.get_job_level_for(job_id)
		selected_unit.job_exp = selected_unit.get_job_exp_for(job_id)
		_ensure_distinct_jobs(selected_unit)
		refreshing = true
		_populate_jobs(sub_selector, selected_unit.sub_job_id, selected_unit.main_job_id)
		refreshing = false
	else:
		if job_id == selected_unit.main_job_id: return
		selected_unit.sub_job_id = job_id; selected_unit.sub_job_name = job.job_name
	if job_unlocks: job_unlocks.unlock_available_jobs(selected_unit)
	unlocks.validate_equipped_skills(selected_unit)
	if status_calculator: selected_unit.refresh_build_stats(status_calculator)
	_validate_equipped_weapon()
	_populate_equipment_selectors()
	_refresh_skills()

func _ensure_distinct_jobs(unit: BattleUnit) -> void:
	if unit.sub_job_id != unit.main_job_id: return
	for candidate in unit.unlocked_job_ids:
		if candidate == unit.main_job_id: continue
		var job := jobs.get_job(candidate)
		if not job or not job.player_selectable: continue
		unit.sub_job_id = candidate; unit.sub_job_name = job.job_name
		return
	unit.sub_job_id = ""; unit.sub_job_name = "None"

func _populate_equipment_selectors() -> void:
	if not equipment_database or not equipment_system: return
	refreshing = true
	_populate_equipment_selector(weapon_selector, EquipmentData.EquipmentType.WEAPON, selected_unit.equipped_weapon_id)
	_populate_equipment_selector(armor_selector, EquipmentData.EquipmentType.ARMOR, selected_unit.equipped_armor_id)
	_populate_equipment_selector(accessory_selector, EquipmentData.EquipmentType.ACCESSORY, selected_unit.equipped_accessory_id)
	refreshing = false

func _populate_equipment_selector(selector: OptionButton, type: EquipmentData.EquipmentType, selected_id: String) -> void:
	selector.clear()
	for equipment: EquipmentData in equipment_database.get_by_type(type):
		if equipment is WeaponData and not equipment_system.can_equip_weapon(selected_unit, equipment): continue
		selector.add_item(equipment.equipment_name)
		selector.set_item_metadata(selector.item_count - 1, equipment.equipment_id)
		if equipment.equipment_id == selected_id: selector.select(selector.item_count - 1)

func _change_equipment(type: EquipmentData.EquipmentType) -> void:
	if refreshing or not selected_unit: return
	var selector := weapon_selector if type == EquipmentData.EquipmentType.WEAPON else (armor_selector if type == EquipmentData.EquipmentType.ARMOR else accessory_selector)
	if selector.selected < 0: return
	var equipment_id := str(selector.get_item_metadata(selector.selected))
	if type == EquipmentData.EquipmentType.WEAPON: equipment_system.equip_weapon(selected_unit, equipment_id)
	elif type == EquipmentData.EquipmentType.ARMOR: equipment_system.equip_armor(selected_unit, equipment_id)
	else: equipment_system.equip_accessory(selected_unit, equipment_id)
	_refresh_skills()

func _validate_equipped_weapon() -> void:
	if not equipment_system or selected_unit.equipped_weapon_id.is_empty(): return
	var weapon: WeaponData = equipment_database.get_weapon(selected_unit.equipped_weapon_id)
	if equipment_system.can_equip_weapon(selected_unit, weapon): return
	selected_unit.equipped_weapon_id = ""
	for candidate: WeaponData in equipment_database.get_all_weapons():
		if equipment_system.equip_weapon(selected_unit, candidate.equipment_id): break

func _refresh_skills() -> void:
	for container in [equipped_list, available_list]:
		for child in container.get_children(): child.queue_free()
	for skill_id in selected_unit.equipped_skill_ids:
		var skill := skills.get_skill(skill_id)
		var button := Button.new(); button.text = skill.skill_name if skill else skill_id
		button.pressed.connect(func() -> void: selected_unit.unequip_skill(skill_id); _refresh_skills())
		equipped_list.add_child(button)
	for skill_id in unlocks.get_available_skill_ids_for_unit(selected_unit):
		if skill_id in selected_unit.equipped_skill_ids: continue
		var skill := skills.get_skill(skill_id)
		var button := Button.new(); button.text = "%s  AP %d  Range %d-%d" % [skill.skill_name, skill.ap_cost, skill.min_range, skill.max_range]
		button.pressed.connect(func() -> void:
			if selected_unit.equip_skill(skill_id): _refresh_skills()
			else: message_label.text = "Max 6 skills can be equipped")
		available_list.add_child(button)
	var build_text := ""
	if selected_unit.build_stats:
		var b := selected_unit.build_stats
		build_text = "\nSTR %d  DEX %d  VIT %d  MND %d  INT %d  AGI %d\nATK %d  MATK %d  DEF %d  MDEF %d  ACC %d  CRIT %d%%  EVA %d%%  SPD %d  MOVE %d  JUMP %d" % [selected_unit.strength, selected_unit.dexterity, selected_unit.vitality, selected_unit.mind, selected_unit.intelligence, selected_unit.agility, b.attack_power, b.magic_attack_power, b.defense, b.magic_defense, b.accuracy, b.critical_rate, b.evasion, b.speed, b.move_range, b.jump_height]
	message_label.text = "Equipped Skills %d / %d%s" % [selected_unit.equipped_skill_ids.size(), BattleUnit.MAX_EQUIPPED_SKILLS, build_text]

func _start_battle() -> void:
	for unit in units:
		_ensure_distinct_jobs(unit)
		unlocks.validate_equipped_skills(unit)
		if status_calculator: unit.refresh_build_stats(status_calculator)
	visible = false
	battle_started.emit()
