class_name SaveManager
extends Node

signal status_message(message: String)

const SAVE_VERSION := 1
const SAVE_PATH := "user://save_data.json"

var player_profile: PlayerProfileData
var unit_progress: UnitProgressManager
var stage_progress: StageProgressManager

func setup(profile: PlayerProfileData, units: UnitProgressManager, stages: StageProgressManager) -> void:
	player_profile = profile
	unit_progress = units
	stage_progress = stages

func load_or_create(player_units: Array[BattleUnit]) -> bool:
	if FileAccess.file_exists(SAVE_PATH) and load_game():
		return true
	player_profile.create_default_profile()
	stage_progress.create_default_progress()
	unit_progress.create_default_units(player_units)
	_emit_status("New game data created.")
	return false

func save_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save game: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(build_save_data(), "  "))
	file.close()
	_emit_status("Game saved.")
	return true

func load_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Failed to load save data. Starting new game.")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("Save data is invalid. Starting new game.")
		return false
	var data: Dictionary = migrate_save_data(parsed)
	if not data.get("profile", {}) is Dictionary or not data.get("units", {}) is Dictionary or not data.get("stages", {}) is Dictionary:
		push_warning("Save data is invalid. Starting new game.")
		return false
	player_profile.from_dict(data["profile"])
	unit_progress.from_dict(data["units"])
	stage_progress.from_dict(data["stages"])
	_emit_status("Game loaded.")
	return true

func build_save_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"profile": player_profile.to_dict(),
		"units": unit_progress.to_dict(),
		"stages": stage_progress.to_dict(),
	}

func migrate_save_data(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	if int(migrated.get("save_version", 0)) < SAVE_VERSION:
		migrated["save_version"] = SAVE_VERSION
	return migrated

func get_save_path() -> String:
	return SAVE_PATH

func _emit_status(message: String) -> void:
	print(message)
	status_message.emit(message)
