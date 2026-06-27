class_name TriggerManager
extends Node

var fired_triggers: Dictionary = {}

func should_fire(id: String, condition: bool) -> bool:
	if not condition or fired_triggers.has(id): return false
	fired_triggers[id] = true
	return true
