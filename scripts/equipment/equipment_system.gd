class_name EquipmentSystem
extends Node

var equipment_database: Node
var job_database: JobDatabase
var status_calculator: Node

func setup(equipment_db: Node, job_db: JobDatabase, calculator: Node) -> void:
	equipment_database = equipment_db; job_database = job_db; status_calculator = calculator

func get_allowed_weapon_types(unit: BattleUnit) -> Array[int]:
	var result: Array[int] = []
	for job_id: String in [unit.main_job_id, unit.sub_job_id]:
		var job := job_database.get_job(job_id)
		if not job: continue
		for type: int in job.allowed_weapon_types:
			if type not in result: result.append(type)
	return result

func can_equip_weapon(unit: BattleUnit, weapon: WeaponData) -> bool:
	return weapon != null and int(weapon.weapon_type) in get_allowed_weapon_types(unit)

func equip_weapon(unit: BattleUnit, weapon_id: String) -> bool:
	var weapon: WeaponData = equipment_database.get_weapon(weapon_id)
	if not can_equip_weapon(unit, weapon): return false
	unit.equipped_weapon_id = weapon_id
	refresh_weapon_visual(unit)
	unit.refresh_build_stats(status_calculator)
	return true

func refresh_weapon_visual(unit: BattleUnit) -> void:
	var weapon: WeaponData = equipment_database.get_weapon(unit.equipped_weapon_id)
	if not weapon:
		unit.equip_weapon_visual("")
		return
	unit.equip_weapon_visual(
		weapon.visual_model_path,
		"hand_right_te",
		weapon.visual_rotation_degrees,
		weapon.visual_scale
	)

func equip_armor(unit: BattleUnit, armor_id: String) -> bool:
	var equipment: EquipmentData = equipment_database.get_equipment(armor_id)
	if not equipment or equipment.equipment_type != EquipmentData.EquipmentType.ARMOR: return false
	unit.equipped_armor_id = armor_id; unit.refresh_build_stats(status_calculator); return true

func equip_accessory(unit: BattleUnit, accessory_id: String) -> bool:
	var equipment: EquipmentData = equipment_database.get_equipment(accessory_id)
	if not equipment or equipment.equipment_type != EquipmentData.EquipmentType.ACCESSORY: return false
	unit.equipped_accessory_id = accessory_id; unit.refresh_build_stats(status_calculator); return true
