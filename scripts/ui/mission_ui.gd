class_name MissionUI
extends PanelContainer

@onready var label: Label = $MissionLabel

func setup(stage_name: String) -> void:
	label.text = "%s\n\nVictory\n・Defeat all enemies\n\nDefeat\n・Vain is defeated" % stage_name
