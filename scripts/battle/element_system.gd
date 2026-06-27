class_name ElementSystem
extends Node

func apply_element_modifiers(base_damage: int, attack_element: BattleUnit.ElementType, target: BattleUnit) -> int:
	var affinity := get_damage_multiplier(attack_element, target.element)
	var resistance := 0
	if target.build_stats:
		var names := ["none", "earth", "water", "wind", "fire", "thunder", "ice", "light", "dark"]
		resistance = clampi(int(target.build_stats.elemental_resistances.get(names[int(attack_element)], 0)), -100, 100)
	return maxi(1, int(base_damage * affinity * (1.0 - resistance / 100.0)))

const STRONG_AGAINST := {BattleUnit.ElementType.FIRE: BattleUnit.ElementType.ICE, BattleUnit.ElementType.ICE: BattleUnit.ElementType.WIND, BattleUnit.ElementType.WIND: BattleUnit.ElementType.EARTH, BattleUnit.ElementType.EARTH: BattleUnit.ElementType.THUNDER, BattleUnit.ElementType.THUNDER: BattleUnit.ElementType.WATER, BattleUnit.ElementType.WATER: BattleUnit.ElementType.FIRE, BattleUnit.ElementType.LIGHT: BattleUnit.ElementType.DARK, BattleUnit.ElementType.DARK: BattleUnit.ElementType.LIGHT}

func get_damage_multiplier(attack: BattleUnit.ElementType, target: BattleUnit.ElementType) -> float:
	if attack == BattleUnit.ElementType.NONE: return 1.0
	if STRONG_AGAINST.get(attack) == target: return 1.25
	if STRONG_AGAINST.get(target) == attack: return 0.75
	return 1.0
func get_hit_modifier(attack: BattleUnit.ElementType, target: BattleUnit.ElementType) -> int:
	var multiplier := get_damage_multiplier(attack, target)
	return 5 if multiplier > 1.0 else (-5 if multiplier < 1.0 else 0)
