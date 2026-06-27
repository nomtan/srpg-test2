class_name StageProgressData
extends RefCounted

var cleared := false
var clear_count := 0
var best_turn_count := 0

func to_dict() -> Dictionary:
	return {"cleared": cleared, "clear_count": clear_count, "best_turn_count": best_turn_count}
