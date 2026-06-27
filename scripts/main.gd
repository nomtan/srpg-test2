extends Node3D

@onready var grid: GridSystem = $GridSystem
@onready var voxel_map: VoxelMap = $VoxelMap
@onready var unit_manager: UnitManager = $UnitManager
@onready var cursor: BattleCursor = $BattleCursor
@onready var pathfinding: BattlePathfinding = $Pathfinding
@onready var attack_system: AttackSystem = $AttackSystem
@onready var line_of_sight: LineOfSight = $LineOfSight
@onready var enemy_ai: EnemyAI = $EnemyAI
@onready var turn_manager: TurnManager = $TurnManager
@onready var camera_controller: CameraController = $CameraController
@onready var battle_hud: BattleHUD = $UI/MarginContainer/BattleHUD
@onready var action_menu: ActionMenu = $UI/ActionMenu
@onready var unit_info: UnitInfoPanel = $UI/UnitInfoPanel
@onready var battle_log: BattleLog = $UI/BattleLog
@onready var facing_selector: FacingSelector = $UI/FacingSelector
@onready var stage_manager: StageManager = $StageManager
@onready var trigger_manager: TriggerManager = $TriggerManager
@onready var event_manager: EventManager = $EventManager
@onready var mission_ui: MissionUI = $UI/MissionUI
@onready var battle_message: BattleMessage = $UI/BattleMessage
@onready var threat_system: ThreatSystem = $ThreatSystem
@onready var threat_arrows: ThreatArrowManager = $ThreatArrowManager
@onready var unit_mover: UnitMover = $UnitMover
@onready var combat_confirm: CombatConfirmPanel = $UI/CombatConfirmPanel

var reachable: Dictionary = {}
var original_grid_pos := Vector2i.ZERO
var original_facing: BattleUnit.FacingDirection = BattleUnit.FacingDirection.SOUTH
var is_battle_finished := false
var selected_attack_target: BattleUnit


func _ready() -> void:
	grid.generate_grid()
	voxel_map.build_from_grid(grid)
	unit_manager.setup(grid)
	line_of_sight.setup(grid)
	attack_system.setup(grid, line_of_sight)
	threat_system.setup(unit_manager, attack_system, pathfinding, grid)
	unit_mover.setup(grid)
	enemy_ai.setup(grid, unit_manager, pathfinding, attack_system, unit_mover)
	var stage_data := StageData.new()
	stage_manager.stage_message.connect(_on_stage_message)
	stage_manager.stage_finished.connect(_on_battle_ended)
	stage_manager.setup(stage_data, grid, unit_manager, trigger_manager, event_manager)
	mission_ui.setup(stage_data.stage_name)
	cursor.setup(grid, camera_controller.setup())
	cursor.confirm_pressed.connect(_on_confirm)
	cursor.cancel_pressed.connect(_on_cancel)
	cursor.grid_position_changed.connect(_update_unit_info)
	action_menu.attack_selected.connect(_on_attack_selected)
	action_menu.wait_selected.connect(_on_wait_selected)
	action_menu.cancel_selected.connect(_cancel_after_move)
	action_menu.facing_selected.connect(_open_facing_selector)
	facing_selector.direction_selected.connect(_on_facing_selected)
	facing_selector.cancelled.connect(_close_facing_selector)
	combat_confirm.confirmed.connect(_on_combat_confirmed)
	combat_confirm.cancelled.connect(_on_combat_cancelled)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.combat_message.connect(_on_combat_message)
	turn_manager.battle_ended.connect(_on_battle_ended)
	turn_manager.start_battle()
	_update_unit_info(cursor.grid_position)


func _on_confirm() -> void:
	if is_battle_finished or not turn_manager.is_player_turn(): return
	var grid_pos := cursor.grid_position
	if cursor.current_mode == BattleCursor.CursorMode.IDLE:
		if stage_manager.interact_at(grid_pos): return
		_select_unit(grid_pos)
	elif cursor.current_mode == BattleCursor.CursorMode.MOVE_TARGETING:
		_confirm_move(grid_pos)
	elif cursor.current_mode == BattleCursor.CursorMode.ATTACK_TARGETING:
		_confirm_attack(grid_pos)


func _select_unit(grid_pos: Vector2i) -> void:
	var unit := unit_manager.unit_at(grid_pos)
	if not unit or unit.team != "player" or unit.has_acted:
		_update_status("未行動の味方ユニットを選択してください")
		return
	unit_manager.select_unit(unit)
	original_grid_pos = grid_pos
	original_facing = unit.facing
	reachable = pathfinding.find_reachable(grid, grid_pos, unit.move_range, unit.jump_height)
	_show_move_range(unit, grid_pos)
	cursor.current_mode = BattleCursor.CursorMode.MOVE_TARGETING
	_update_status("%sの移動先を選択" % unit.unit_name)


func _confirm_move(grid_pos: Vector2i) -> void:
	if not reachable.has(grid_pos):
		_update_status("そこへは移動できません")
		return
	var unit := unit_manager.selected_unit
	var origin := Vector2i(unit.grid_x, unit.grid_z)
	if grid_pos != origin: unit_manager.move_selected_to(grid_pos)
	unit.has_moved = grid_pos != origin
	var enemies := threat_system.get_threatening_enemies_for_cell(unit, grid_pos)
	if not enemies.is_empty(): threat_arrows.show_threat_arrows(enemies, unit)
	else: threat_arrows.clear_threat_arrows()
	cursor.clear_reachable()
	cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
	cursor.input_enabled = false
	action_menu.open()
	_update_status("行動を選択してください")


func _on_attack_selected() -> void:
	action_menu.close()
	var cells := attack_system.get_attackable_cells(unit_manager.selected_unit)
	cursor.show_attack_range(cells)
	cursor.current_mode = BattleCursor.CursorMode.ATTACK_TARGETING
	cursor.input_enabled = true
	_update_status("攻撃対象を選択 / Escで戻る")


func _confirm_attack(grid_pos: Vector2i) -> void:
	var attacker := unit_manager.selected_unit
	var target := unit_manager.unit_at(grid_pos)
	if not attack_system.can_attack(attacker, target):
		_update_status("そのユニットは攻撃できません")
		return
	selected_attack_target = target
	combat_confirm.open(attacker, target, attack_system.get_battle_preview(attacker, target))
	cursor.current_mode = BattleCursor.CursorMode.COMBAT_CONFIRM
	cursor.input_enabled = false


func _on_combat_confirmed() -> void:
	var attacker := unit_manager.selected_unit
	var target := selected_attack_target
	combat_confirm.close()
	camera_controller.pulse_focus()
	var result := attack_system.execute_attack(attacker, target)
	battle_log.show_attack_result(attacker, target, result)
	_update_status(result.message)
	if not target.is_alive(): unit_manager.remove_unit(target)
	selected_attack_target = null
	_finish_action()


func _on_combat_cancelled() -> void:
	combat_confirm.close()
	selected_attack_target = null
	cursor.current_mode = BattleCursor.CursorMode.ATTACK_TARGETING
	cursor.input_enabled = true
	cursor.show_attack_range(attack_system.get_attackable_cells(unit_manager.selected_unit))


func _on_wait_selected() -> void:
	action_menu.close()
	_update_status("%sは待機しました" % unit_manager.selected_unit.unit_name)
	_finish_action()


func _open_facing_selector() -> void:
	action_menu.close()
	facing_selector.open()


func _on_facing_selected(direction: BattleUnit.FacingDirection) -> void:
	unit_manager.selected_unit.set_facing(direction)
	_close_facing_selector()


func _close_facing_selector() -> void:
	facing_selector.close()
	action_menu.open()


func _finish_action() -> void:
	threat_arrows.clear_threat_arrows()
	unit_manager.mark_unit_acted(unit_manager.selected_unit, unit_manager.selected_unit.has_moved)
	unit_manager.clear_selection()
	cursor.clear_reachable()
	cursor.current_mode = BattleCursor.CursorMode.IDLE
	cursor.input_enabled = true
	_update_unit_info(cursor.grid_position)
	if _check_battle_result(): return
	if unit_manager.are_all_player_units_acted():
		turn_manager.finish_player_turn(unit_manager, enemy_ai)


func _on_cancel() -> void:
	if cursor.current_mode == BattleCursor.CursorMode.ATTACK_TARGETING:
		cursor.clear_reachable()
		cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
		cursor.input_enabled = false
		action_menu.open()
	elif cursor.current_mode == BattleCursor.CursorMode.MOVE_TARGETING:
		unit_manager.clear_selection()
		cursor.clear_reachable()
		cursor.current_mode = BattleCursor.CursorMode.IDLE
	elif cursor.current_mode == BattleCursor.CursorMode.ACTION_MENU:
		_cancel_after_move()
	elif cursor.current_mode == BattleCursor.CursorMode.COMBAT_CONFIRM:
		_on_combat_cancelled()


func _cancel_after_move() -> void:
	action_menu.close()
	threat_arrows.clear_threat_arrows()
	var unit := unit_manager.selected_unit
	if not unit: return
	if Vector2i(unit.grid_x, unit.grid_z) != original_grid_pos:
		unit_manager.move_unit_to_grid(unit, original_grid_pos)
	unit.has_moved = false
	unit.set_facing(original_facing)
	reachable = pathfinding.find_reachable(grid, original_grid_pos, unit.move_range, unit.jump_height)
	_show_move_range(unit, original_grid_pos)
	cursor.set_grid_position(original_grid_pos)
	cursor.current_mode = BattleCursor.CursorMode.MOVE_TARGETING
	cursor.input_enabled = true
	_update_status("移動を取り消しました")


func _on_phase_changed(turn_count: int, phase: TurnManager.TurnPhase) -> void:
	battle_hud.update_turn(turn_count, phase)
	var player_turn := phase == TurnManager.TurnPhase.PLAYER_TURN
	cursor.input_enabled = player_turn
	if player_turn:
		stage_manager.on_turn_started(turn_count)
		if not stage_manager.check_result(turn_count).is_empty(): return
		battle_message.show_message("Player Phase")
		cursor.current_mode = BattleCursor.CursorMode.IDLE
		_update_status("行動する味方ユニットを選択してください")
	else:
		threat_arrows.clear_threat_arrows()
		battle_message.show_message("Enemy Phase")
		_update_status("Enemy Turn")


func _update_unit_info(grid_pos: Vector2i) -> void:
	var unit := unit_manager.unit_at(grid_pos)
	if unit and unit_manager.selected_unit and cursor.current_mode == BattleCursor.CursorMode.ATTACK_TARGETING:
		if attack_system.can_attack(unit_manager.selected_unit, unit):
			var preview := attack_system.get_battle_preview(unit_manager.selected_unit, unit)
			unit_info.show_battle_preview(unit_manager.selected_unit, unit, preview)
			return
		if unit_manager.selected_unit.attack_type == BattleUnit.AttackType.RANGED:
			var from_pos := Vector2i(unit_manager.selected_unit.grid_x, unit_manager.selected_unit.grid_z)
			var to_pos := Vector2i(unit.grid_x, unit.grid_z)
			if not line_of_sight.has_line_between(from_pos, to_pos):
				unit_info.show_blocked_target(unit)
				return
	unit_info.show_cell(grid.get_cell(grid_pos), unit)


func _on_combat_message(message: String) -> void:
	battle_log.add_message(message)
	_update_status(message.replace("\n", " / "))


func _check_battle_result() -> bool:
	return not stage_manager.check_result(turn_manager.turn_count).is_empty()


func _on_stage_message(message: String) -> void:
	battle_message.show_message(message)
	battle_log.add_message(message)
	camera_controller.pulse_focus()


func _on_battle_ended(result: String) -> void:
	is_battle_finished = true
	cursor.input_enabled = false
	action_menu.close()
	facing_selector.close()
	combat_confirm.close()
	threat_arrows.clear_threat_arrows()
	_update_status(result)
	battle_message.show_message("Mission Complete" if result == "Victory" else "Defeat", 4.0)


func _update_status(message: String) -> void:
	battle_hud.set_status(message)


func _show_move_range(unit: BattleUnit, origin: Vector2i) -> void:
	var danger_cells: Dictionary = {}
	for grid_pos: Vector2i in reachable:
		if threat_system.is_cell_threatened(unit, grid_pos): danger_cells[grid_pos] = true
	cursor.show_move_range(reachable, origin, danger_cells)
