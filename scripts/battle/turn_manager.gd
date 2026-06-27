class_name TurnManager
extends Node

signal phase_changed(turn_count: int, phase: TurnPhase)
signal combat_message(message: String)
signal battle_ended(result: String)

enum TurnPhase { PLAYER_TURN, ENEMY_TURN }
var current_phase: TurnPhase = TurnPhase.PLAYER_TURN
var turn_count: int = 1
var is_transitioning := false


func start_battle() -> void: phase_changed.emit(turn_count, current_phase)


func finish_player_turn(unit_manager: UnitManager, enemy_ai: EnemyAI) -> void:
	if not is_player_turn(): return
	is_transitioning = true
	current_phase = TurnPhase.ENEMY_TURN
	phase_changed.emit(turn_count, current_phase)
	for enemy in unit_manager.get_enemy_units():
		combat_message.emit("%s acting..." % enemy.unit_name)
		await get_tree().create_timer(0.25).timeout
		combat_message.emit(enemy_ai.process_enemy_unit(enemy))
		await get_tree().create_timer(0.5).timeout
		if unit_manager.are_all_players_defeated():
			is_transitioning = false
			battle_ended.emit("Defeat")
			return
	unit_manager.reset_player_units_action_state()
	turn_count += 1
	current_phase = TurnPhase.PLAYER_TURN
	is_transitioning = false
	phase_changed.emit(turn_count, current_phase)


func is_player_turn() -> bool:
	return current_phase == TurnPhase.PLAYER_TURN and not is_transitioning
