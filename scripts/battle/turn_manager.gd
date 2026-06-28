class_name TurnManager
extends Node

signal phase_changed(turn_count: int, phase: TurnPhase)
signal combat_message(message: String)
signal battle_ended(result: String)
signal actor_ready(actor: BattleUnit)
signal turn_order_changed(order: Array[BattleUnit])

enum TurnPhase { PLAYER_TURN, ENEMY_TURN }
enum TurnMode { TEAM_PHASE, CT }
enum TurnState { INITIALIZING, CHARGING_CT, UNIT_READY, PLAYER_ACTING, ENEMY_ACTING, ACTION_RESOLVING, BATTLE_RESULT }

var turn_mode: TurnMode = TurnMode.CT
var current_phase: TurnPhase = TurnPhase.PLAYER_TURN
var current_turn_state: TurnState = TurnState.INITIALIZING
var current_actor: BattleUnit
var turn_count := 1
var is_transitioning := false
var is_battle_finished := false
var unit_manager: UnitManager

func setup(manager: UnitManager) -> void: unit_manager = manager

func start_battle() -> void:
	if turn_mode == TurnMode.CT: initialize_ct_battle()
	else: phase_changed.emit(turn_count, current_phase)

func initialize_ct_battle() -> void:
	current_turn_state = TurnState.INITIALIZING
	current_actor = null
	is_battle_finished = false
	turn_count = 1
	for unit in unit_manager.get_all_units():
		unit.ct = 0; unit.is_current_actor = false
	start_next_ct_turn()

func start_next_ct_turn() -> void:
	if is_battle_finished: return
	current_turn_state = TurnState.CHARGING_CT
	var actor := charge_ct_until_actor_ready()
	if not actor:
		push_error("No actor found in CT system")
		return
	_start_actor_turn(actor)

func charge_ct_until_actor_ready() -> BattleUnit:
	var safety_count := 0
	while safety_count < 1000:
		safety_count += 1
		var alive_units := unit_manager.get_alive_units()
		if alive_units.is_empty(): return null
		for unit in alive_units: unit.add_ct(get_ct_speed(unit))
		var ready_units := get_ready_units(alive_units)
		if not ready_units.is_empty():
			var actor := choose_next_actor(ready_units)
			turn_order_changed.emit(estimate_turn_order(5))
			return actor
	return null

func get_ct_speed(unit: BattleUnit) -> int:
	if unit.build_stats: return maxi(1, unit.build_stats.speed)
	return maxi(1, unit.agility if unit.agility > 0 else unit.base_agi)

func get_ready_units(source_units: Array[BattleUnit]) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in source_units:
		if unit.is_ready_to_act(): result.append(unit)
	return result

func choose_next_actor(ready_units: Array[BattleUnit]) -> BattleUnit:
	ready_units.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		if a.ct != b.ct: return a.ct > b.ct
		if get_ct_speed(a) != get_ct_speed(b): return get_ct_speed(a) > get_ct_speed(b)
		if a.team != b.team: return a.team == "player"
		return a.unit_id < b.unit_id)
	return ready_units[0]

func _start_actor_turn(actor: BattleUnit) -> void:
	current_actor = actor
	actor.is_current_actor = true
	actor.has_acted = false; actor.has_moved = false; actor.has_used_action = false
	actor.update_visual_state()
	current_phase = TurnPhase.PLAYER_TURN if actor.team == "player" else TurnPhase.ENEMY_TURN
	current_turn_state = TurnState.PLAYER_ACTING if actor.team == "player" else TurnState.ENEMY_ACTING
	combat_message.emit("%s is ready (CT %d)" % [actor.unit_name, actor.ct])
	actor_ready.emit(actor)

func finish_actor_turn(actor: BattleUnit, waited: bool = false) -> void:
	if not actor or actor != current_actor or is_battle_finished: return
	current_turn_state = TurnState.ACTION_RESOLVING
	actor.is_current_actor = false
	if waited: actor.reset_ct_after_wait()
	else: actor.reset_ct_after_action()
	actor.has_acted = true
	current_actor = null
	turn_count += 1
	turn_order_changed.emit(estimate_turn_order(5))
	call_deferred("start_next_ct_turn")

func estimate_turn_order(count: int = 5) -> Array[BattleUnit]:
	var simulated: Array[Dictionary] = []
	for unit in unit_manager.get_alive_units():
		var simulated_ct := 0 if unit == current_actor else unit.ct
		simulated.append({"unit": unit, "ct": simulated_ct, "speed": get_ct_speed(unit)})
	var order: Array[BattleUnit] = []
	var safety := 0
	while order.size() < count and not simulated.is_empty() and safety < 1000:
		safety += 1
		for entry in simulated: entry.ct = int(entry.ct) + int(entry.speed)
		simulated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.ct) != int(b.ct): return int(a.ct) > int(b.ct)
			if int(a.speed) != int(b.speed): return int(a.speed) > int(b.speed)
			var au: BattleUnit = a.unit; var bu: BattleUnit = b.unit
			if au.team != bu.team: return au.team == "player"
			return au.unit_id < bu.unit_id)
		var next: Dictionary = simulated[0]
		if int(next.ct) >= 100:
			order.append(next.unit)
			next.ct = 0
	return order

func stop_battle() -> void:
	is_battle_finished = true
	current_turn_state = TurnState.BATTLE_RESULT
	if current_actor: current_actor.is_current_actor = false
	current_actor = null

func is_player_turn() -> bool:
	if turn_mode == TurnMode.CT:
		return not is_battle_finished and current_actor != null and current_actor.team == "player" and current_turn_state == TurnState.PLAYER_ACTING
	return current_phase == TurnPhase.PLAYER_TURN and not is_transitioning

func finish_player_turn(manager: UnitManager, enemy_ai: EnemyAI) -> void:
	if turn_mode == TurnMode.CT: return
	if not is_player_turn(): return
	is_transitioning = true; current_phase = TurnPhase.ENEMY_TURN; phase_changed.emit(turn_count, current_phase)
	for enemy in manager.get_enemy_units():
		combat_message.emit(await enemy_ai.process_enemy_unit(enemy))
	manager.reset_player_units_action_state(); turn_count += 1
	current_phase = TurnPhase.PLAYER_TURN; is_transitioning = false; phase_changed.emit(turn_count, current_phase)
