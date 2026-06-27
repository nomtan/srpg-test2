class_name BattleMessage
extends Label

var message_version := 0

func show_message(message: String, duration: float = 1.5) -> void:
	message_version += 1
	var version := message_version
	text = message
	visible = true
	await get_tree().create_timer(duration).timeout
	if version == message_version: visible = false
