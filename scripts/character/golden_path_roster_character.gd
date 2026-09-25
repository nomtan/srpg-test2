extends "res://scripts/character/tripo_roster_character.gd"

const FACE_CONTROLLER_SCRIPT = preload("res://scripts/character/face_controller.gd")

var face_controller: FaceController

func _ready() -> void:
	super._ready()
	var model := get_node("Model")
	face_controller = FACE_CONTROLLER_SCRIPT.new()
	model.add_child(face_controller)
	face_controller.bind_character(model, character_id.trim_prefix("golden_path_"))
