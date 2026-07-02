class_name WeaponData
extends EquipmentData

enum WeaponType { NONE, SWORD, AXE, SPEAR, BOW, DAGGER, DUAL_BLADE, STAFF, MACE, FIST }

var weapon_type: WeaponType = WeaponType.NONE
var weapon_power := 0
var weapon_accuracy_modifier := 0
var weapon_critical_modifier := 0
var min_range := 1
var max_range := 1
var attack_element: BattleUnit.ElementType = BattleUnit.ElementType.NONE
var requires_line_of_sight := false

static func create_weapon(id: String, display_name: String, type: WeaponType, power: int, accuracy: int, critical: int, ranges: Vector2i, stats: Dictionary = {}, los: bool = false) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.configure(id, display_name, EquipmentType.WEAPON, stats)
	weapon.weapon_type = type; weapon.weapon_power = power
	weapon.weapon_accuracy_modifier = accuracy; weapon.weapon_critical_modifier = critical
	weapon.min_range = ranges.x; weapon.max_range = ranges.y; weapon.requires_line_of_sight = los
	return weapon
