class_name WeaponPowerCalculator
extends Node

var status_calculator: Node
func setup(calculator: Node) -> void: status_calculator = calculator

func calculate_weapon_attack_power(unit: BattleUnit, weapon: WeaponData) -> int:
	var stats: Dictionary = status_calculator.calculate_final_base_stats(unit)
	var power: int
	match weapon.weapon_type:
		WeaponData.WeaponType.SWORD: power = floori(stats.str * 0.8) + floori(stats.dex * 0.2) + weapon.weapon_power
		WeaponData.WeaponType.AXE: power = int(stats.str) + weapon.weapon_power
		WeaponData.WeaponType.SPEAR: power = floori(stats.str * 0.8) + floori(stats.agi * 0.2) + weapon.weapon_power
		WeaponData.WeaponType.BOW: power = floori(stats.dex * 0.7) + floori(stats.str * 0.3) + weapon.weapon_power
		WeaponData.WeaponType.DAGGER: power = floori(stats.dex * 0.6) + floori(stats.agi * 0.4) + weapon.weapon_power
		WeaponData.WeaponType.DUAL_BLADE: power = floori(stats.agi * 0.6) + floori(stats.dex * 0.4) + weapon.weapon_power
		WeaponData.WeaponType.STAFF: power = floori(stats.int * 0.7) + floori(stats.mnd * 0.3) + weapon.weapon_power
		WeaponData.WeaponType.MACE: power = floori(stats.str * 0.7) + floori(stats.mnd * 0.3) + weapon.weapon_power
		WeaponData.WeaponType.FIST: power = floori(stats.str * 0.7) + floori(stats.agi * 0.3) + weapon.weapon_power
		_: return unit.build_stats.attack_power if unit.build_stats else unit.attack_power
	return status_calculator.apply_passive_modifier(unit, "attack_power", power)
