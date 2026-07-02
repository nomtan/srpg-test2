class_name ArmorData
extends EquipmentData

var armor_category := "light"

static func create_armor(id: String, display_name: String, category: String, stats: Dictionary, builds: Dictionary = {}) -> ArmorData:
	var armor := ArmorData.new()
	armor.configure(id, display_name, EquipmentType.ARMOR, stats, builds)
	armor.armor_category = category
	return armor
