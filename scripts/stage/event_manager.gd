class_name EventManager
extends Node

signal event_fired(event_name: String)
var completed_events: Dictionary = {}

func fire_event(event_name: String) -> void:
	if completed_events.has(event_name): return
	completed_events[event_name] = true
	event_fired.emit(event_name)
