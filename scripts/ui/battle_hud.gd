class_name BattleHUD
extends VBoxContainer

@onready var turn_label: Label = $TurnLabel
@onready var phase_label: Label = $PhaseLabel
@onready var status_label: Label = $StatusLabel


func update_turn(turn_count: int, phase: TurnManager.TurnPhase) -> void:
	turn_label.text = "Turn %d" % turn_count
	phase_label.text = (
		"Player Turn"
		if phase == TurnManager.TurnPhase.PLAYER_TURN
		else "Enemy Turn"
	)


func set_status(message: String) -> void:
	status_label.text = message

func update_current_actor(actor: BattleUnit) -> void:
	turn_label.text = "CT Battle"
	phase_label.text = "Current Actor: %s" % (actor.unit_name if actor else "---")
