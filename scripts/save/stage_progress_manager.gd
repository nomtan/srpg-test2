class_name StageProgressManager
extends Node

var stages: Dictionary = {}

func create_default_progress() -> void:
	stages.clear()

func mark_stage_cleared(stage_id: String, turn_count: int = 0) -> void:
	var progress: Dictionary = stages.get(stage_id, {})
	progress["cleared"] = true
	progress["clear_count"] = int(progress.get("clear_count", 0)) + 1
	if turn_count > 0:
		var previous_best := int(progress.get("best_turn_count", 0))
		progress["best_turn_count"] = turn_count if previous_best <= 0 else mini(previous_best, turn_count)
	stages[stage_id] = progress

func is_stage_cleared(stage_id: String) -> bool:
	var progress: Dictionary = stages.get(stage_id, {})
	return bool(progress.get("cleared", false))

func to_dict() -> Dictionary:
	return stages.duplicate(true)

func from_dict(data: Dictionary) -> void:
	stages = data.duplicate(true)
