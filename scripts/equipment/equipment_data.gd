class_name EquipmentData
extends Resource

enum EquipmentType { WEAPON, ARMOR, ACCESSORY }

var equipment_id := ""
var equipment_name := ""
var description := ""
var equipment_type: EquipmentType
var price := 0
var stat_bonus: Dictionary = {"str": 0, "dex": 0, "vit": 0, "mnd": 0, "int": 0, "agi": 0}
var build_bonus: Dictionary = {"accuracy": 0, "critical_rate": 0, "evasion": 0, "move_range": 0, "jump_height": 0}
var elemental_resistance_bonus: Dictionary = {"fire": 0, "earth": 0, "water": 0, "thunder": 0, "wind": 0, "ice": 0, "dark": 0, "light": 0}

func configure(id: String, display_name: String, type: EquipmentType, stats: Dictionary = {}, builds: Dictionary = {}) -> void:
	equipment_id = id; equipment_name = display_name; equipment_type = type
	for key: String in stat_bonus: stat_bonus[key] = int(stats.get(key, 0))
	for key: String in build_bonus: build_bonus[key] = int(builds.get(key, 0))
