class_name PlayerProfileData
extends Node

var player_name := "Player"
var current_stage_id := "stage_001"
var play_time_seconds := 0.0
var gold := 0

func create_default_profile() -> void:
	player_name = "Player"
	current_stage_id = "stage_001"
	play_time_seconds = 0.0
	gold = 0

func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"current_stage_id": current_stage_id,
		"play_time_seconds": play_time_seconds,
		"gold": gold,
	}

func from_dict(data: Dictionary) -> void:
	player_name = str(data.get("player_name", "Player"))
	current_stage_id = str(data.get("current_stage_id", "stage_001"))
	play_time_seconds = float(data.get("play_time_seconds", 0.0))
	gold = int(data.get("gold", 0))
