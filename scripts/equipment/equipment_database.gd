class_name EquipmentDatabase
extends Node

var equipments: Dictionary = {}

func _ready() -> void:
	_register(WeaponData.create_weapon("iron_sword", "Iron Sword", WeaponData.WeaponType.SWORD, 5, 0, 0, Vector2i(1, 1), {"str": 1, "dex": 1}))
	_register(WeaponData.create_weapon("iron_axe", "Iron Axe", WeaponData.WeaponType.AXE, 8, -10, 0, Vector2i(1, 1), {"str": 2, "agi": -1}))
	_register(WeaponData.create_weapon("iron_spear", "Iron Spear", WeaponData.WeaponType.SPEAR, 5, 0, 0, Vector2i(1, 2), {"str": 1, "agi": 1}))
	_register(WeaponData.create_weapon("short_bow", "Short Bow", WeaponData.WeaponType.BOW, 4, 5, 5, Vector2i(2, 4), {"dex": 2}, true))
	_register(WeaponData.create_weapon("dagger", "Dagger", WeaponData.WeaponType.DAGGER, 3, 5, 10, Vector2i(1, 1), {"dex": 1, "agi": 1}))
	_register(WeaponData.create_weapon("twin_blades", "Twin Blades", WeaponData.WeaponType.DUAL_BLADE, 4, 0, 8, Vector2i(1, 1), {"dex": 1, "agi": 2}))
	_register(WeaponData.create_weapon("wooden_staff", "Wooden Staff", WeaponData.WeaponType.STAFF, 3, 0, 0, Vector2i(1, 2), {"int": 2, "mnd": 1}))
	_register(WeaponData.create_weapon("iron_mace", "Iron Mace", WeaponData.WeaponType.MACE, 5, -5, 0, Vector2i(1, 1), {"str": 1, "mnd": 1}))
	_register(WeaponData.create_weapon("leather_glove", "Leather Glove", WeaponData.WeaponType.FIST, 4, 0, 5, Vector2i(1, 1), {"str": 1, "agi": 1}))
	_register(ArmorData.create_armor("leather_armor", "Leather Armor", "light", {"vit": 1, "agi": 1}))
	_register(ArmorData.create_armor("chain_mail", "Chain Mail", "medium", {"vit": 3, "agi": -1}))
	_register(ArmorData.create_armor("plate_armor", "Plate Armor", "heavy", {"vit": 5, "agi": -2}, {"evasion": -5}))
	_register(ArmorData.create_armor("mage_robe", "Mage Robe", "robe", {"int": 2, "mnd": 2, "vit": 1}))
	_register(AccessoryData.create_accessory("power_ring", "Power Ring", {"str": 2}))
	_register(AccessoryData.create_accessory("mind_charm", "Mind Charm", {"mnd": 2}))
	_register(AccessoryData.create_accessory("speed_boots", "Speed Boots", {"agi": 2}, {"move_range": 1}))
	_register(AccessoryData.create_accessory("accuracy_lens", "Accuracy Lens", {"dex": 2}, {"accuracy": 5}))

func _register(equipment: EquipmentData) -> void: equipments[equipment.equipment_id] = equipment
func get_equipment(id: String) -> EquipmentData: return equipments.get(id)
func get_weapon(id: String) -> WeaponData:
	var equipment := get_equipment(id)
	return equipment as WeaponData if equipment is WeaponData else null
func get_all_weapons() -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for equipment: EquipmentData in equipments.values():
		if equipment is WeaponData: result.append(equipment)
	return result
func get_by_type(type: EquipmentData.EquipmentType) -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	for equipment: EquipmentData in equipments.values():
		if equipment.equipment_type == type: result.append(equipment)
	return result
