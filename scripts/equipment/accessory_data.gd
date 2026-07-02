class_name AccessoryData
extends EquipmentData

var accessory_category := "general"

static func create_accessory(id: String, display_name: String, stats: Dictionary, builds: Dictionary = {}) -> AccessoryData:
	var accessory := AccessoryData.new()
	accessory.configure(id, display_name, EquipmentType.ACCESSORY, stats, builds)
	return accessory
