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
var visual_model_path := ""
var visual_rotation_degrees := Vector3(0.0, 0.0, 180.0)
var visual_scale := 0.78

static func create_weapon(id: String, display_name: String, type: WeaponType, power: int, accuracy: int, critical: int, ranges: Vector2i, stats: Dictionary = {}, los: bool = false, model_path: String = "", model_scale: float = 0.78) -> WeaponData:
	var weapon := WeaponData.new()
	weapon.configure(id, display_name, EquipmentType.WEAPON, stats)
	weapon.weapon_type = type; weapon.weapon_power = power
	weapon.weapon_accuracy_modifier = accuracy; weapon.weapon_critical_modifier = critical
	weapon.min_range = ranges.x; weapon.max_range = ranges.y; weapon.requires_line_of_sight = los
	weapon.visual_model_path = model_path; weapon.visual_scale = model_scale
	return weapon
