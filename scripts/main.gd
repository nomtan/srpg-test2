extends Node3D

@onready var grid: GridSystem = $GridSystem
@onready var voxel_map: VoxelMap = $VoxelMap
@onready var unit_manager: UnitManager = $UnitManager
@onready var cursor: BattleCursor = $BattleCursor
@onready var pathfinding: BattlePathfinding = $Pathfinding
@onready var attack_system: AttackSystem = $AttackSystem
@onready var enemy_ai: EnemyAI = $EnemyAI
@onready var turn_manager: TurnManager = $TurnManager
@onready var camera_controller: CameraController = $CameraController
@onready var battle_hud: BattleHUD = $UI/MarginContainer/BattleHUD
@onready var action_menu: ActionMenu = $UI/ActionMenu
@onready var unit_info: UnitInfoPanel = $UI/UnitInfoPanel

var reachable: Dictionary = {}
var original_grid_pos := Vector2i.ZERO
var is_battle_finished := false


func _ready() -> void:
	grid.generate_grid()
	voxel_map.build_from_grid(grid)
	unit_manager.setup(grid)
	attack_system.setup(grid)
	enemy_ai.setup(grid, unit_manager, pathfinding, attack_system)
	cursor.setup(grid, camera_controller.setup())
	cursor.confirm_pressed.connect(_on_confirm)
	cursor.cancel_pressed.connect(_on_cancel)
	cursor.grid_position_changed.connect(_update_unit_info)
	action_menu.attack_selected.connect(_on_attack_selected)
	action_menu.wait_selected.connect(_on_wait_selected)
	action_menu.cancel_selected.connect(_cancel_after_move)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.combat_message.connect(_update_status)
	turn_manager.battle_ended.connect(_on_battle_ended)
	turn_manager.start_battle()
	_update_unit_info(cursor.grid_position)


func _on_confirm() -> void:
	if is_battle_finished or not turn_manager.is_player_turn(): return
	var grid_pos := cursor.grid_position
	if cursor.current_mode == BattleCursor.CursorMode.IDLE:
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
	reachable = pathfinding.find_reachable(grid, grid_pos, unit.move_range, unit.jump_height)
	cursor.show_reachable(reachable, grid_pos)
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
	var damage := attack_system.execute_attack(attacker, target)
	_update_status("%sが%sに%dダメージ" % [attacker.unit_name, target.unit_name, damage])
	if not target.is_alive(): unit_manager.remove_unit(target)
	_finish_action()


func _on_wait_selected() -> void:
	action_menu.close()
	_update_status("%sは待機しました" % unit_manager.selected_unit.unit_name)
	_finish_action()


func _finish_action() -> void:
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


func _cancel_after_move() -> void:
	action_menu.close()
	var unit := unit_manager.selected_unit
	if not unit: return
	if Vector2i(unit.grid_x, unit.grid_z) != original_grid_pos:
		unit_manager.move_unit_to_grid(unit, original_grid_pos)
	unit.has_moved = false
	reachable = pathfinding.find_reachable(grid, original_grid_pos, unit.move_range, unit.jump_height)
	cursor.show_reachable(reachable, original_grid_pos)
	cursor.set_grid_position(original_grid_pos)
	cursor.current_mode = BattleCursor.CursorMode.MOVE_TARGETING
	cursor.input_enabled = true
	_update_status("移動を取り消しました")


func _on_phase_changed(turn_count: int, phase: TurnManager.TurnPhase) -> void:
	battle_hud.update_turn(turn_count, phase)
	var player_turn := phase == TurnManager.TurnPhase.PLAYER_TURN
	cursor.input_enabled = player_turn
	if player_turn:
		cursor.current_mode = BattleCursor.CursorMode.IDLE
		_update_status("行動する味方ユニットを選択してください")
	else:
		_update_status("Enemy Turn")


func _update_unit_info(grid_pos: Vector2i) -> void:
	var unit := unit_manager.unit_at(grid_pos)
	var damage := -1
	if unit and unit_manager.selected_unit and cursor.current_mode == BattleCursor.CursorMode.ATTACK_TARGETING:
		if attack_system.can_attack(unit_manager.selected_unit, unit):
			damage = attack_system.calculate_damage(unit_manager.selected_unit, unit)
			unit_info.show_damage_preview(unit_manager.selected_unit, unit, damage)
			return
	unit_info.show_unit(unit, damage)


func _check_battle_result() -> bool:
	if unit_manager.are_all_enemies_defeated():
		_on_battle_ended("Victory")
		return true
	if unit_manager.are_all_players_defeated():
		_on_battle_ended("Defeat")
		return true
	return false


func _on_battle_ended(result: String) -> void:
	is_battle_finished = true
	cursor.input_enabled = false
	action_menu.close()
	_update_status(result)


func _update_status(message: String) -> void:
	battle_hud.set_status(message)
