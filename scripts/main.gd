extends Node3D

const PLAYER_START_WEST_LOG_COLUMN := 2
const PLAYER_START_NORTH_LOG_ROW := 2
const JUNGLE_LOG_COLUMN_POSITION := Vector2i(
	PLAYER_START_WEST_LOG_COLUMN,
	PLAYER_START_NORTH_LOG_ROW
)
const OAK_LOG_COLUMN_POSITION := Vector2i(
	PLAYER_START_WEST_LOG_COLUMN,
	PLAYER_START_NORTH_LOG_ROW + 3
)
const ACACIA_LOG_COLUMN_POSITION := Vector2i(
	PLAYER_START_WEST_LOG_COLUMN,
	PLAYER_START_NORTH_LOG_ROW + 6
)
const MASONRY_SHOWCASE: Array[Dictionary] = [
	{"kind": "stone_brick", "position": Vector2i(12, 2)},
	{"kind": "infested_cracked_stone_bricks", "position": Vector2i(12, 5)},
	{"kind": "chiseled_stone_brick", "position": Vector2i(12, 8)},
	{"kind": "stone_brick_stairs", "position": Vector2i(12, 11)},
	{"kind": "bricks", "position": Vector2i(15, 2)},
	{"kind": "brick_stairs", "position": Vector2i(15, 5)},
	{"kind": "cobblestone", "position": Vector2i(15, 8)},
	{"kind": "cobblestone_stairs", "position": Vector2i(15, 11)},
]

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
@onready var threat_system = $ThreatSystem
@onready var threat_arrows: ThreatArrowManager = $ThreatArrowManager
@onready var unit_mover: UnitMover = $UnitMover
@onready var combat_confirm: CombatConfirmPanel = $UI/CombatConfirmPanel
@onready var skill_database: SkillDatabase = $SkillDatabase
@onready var element_system: ElementSystem = $ElementSystem
@onready var skill_system: SkillSystem = $SkillSystem
@onready var skill_menu: SkillMenu = $UI/SkillMenu
@onready var skill_confirm: SkillConfirmPanel = $UI/SkillConfirmPanel
@onready var floating_numbers: FloatingNumberManager = $FloatingNumberManager
@onready var job_database: JobDatabase = $JobDatabase
@onready var job_system: JobSystem = $JobSystem
@onready var experience_system: ExperienceSystem = $ExperienceSystem
@onready var growth_panel: GrowthResultPanel = $UI/GrowthResultPanel
@onready var skill_unlock_system: SkillUnlockSystem = $SkillUnlockSystem
@onready var pre_battle_setup: PreBattleSetupPanel = $UI/PreBattleSetupPanel
@onready var save_manager: SaveManager = $SaveManager
@onready var player_profile: PlayerProfileData = $PlayerProfileData
@onready var unit_progress: UnitProgressManager = $UnitProgressManager
@onready var stage_progress: StageProgressManager = $StageProgressManager
@onready var status_calculator: Node = $StatusCalculator
@onready var job_unlock_system: JobUnlockSystem = $JobUnlockSystem
@onready var turn_order_panel: TurnOrderPanel = $UI/TurnOrderPanel
@onready var equipment_database: Node = $EquipmentDatabase
@onready var equipment_system: Node = $EquipmentSystem
@onready var weapon_power_calculator: Node = $WeaponPowerCalculator
@onready var direction_compass: DirectionCompass = $UI/DirectionCompass

var reachable: Dictionary = {}
var original_grid_pos := Vector2i.ZERO
var original_facing: BattleUnit.FacingDirection = BattleUnit.FacingDirection.SOUTH
var is_battle_finished := false
var selected_attack_target: BattleUnit
var selected_skill: SkillData
var selected_skill_target := Vector2i.ZERO
var pending_wait_action := false
var pending_move_path: Array[Vector2i] = []
var is_move_destination_provisional := false
var battle_result := ""


func _ready() -> void:
	grid.generate_grid()
	_add_jungle_log_column_near_player_start()
	_add_oak_log_column_near_player_start()
	_add_acacia_log_column_near_player_start()
	_apply_masonry_showcase_to_grid()
	voxel_map.build_from_grid(grid)
	unit_manager.setup(grid)
	unit_progress.setup(job_database)
	save_manager.setup(player_profile, unit_progress, stage_progress)
	save_manager.status_message.connect(_on_save_status)
	save_manager.load_or_create(unit_manager.get_player_units())
	unit_progress.apply_progress_to_units(unit_manager.get_player_units())
	status_calculator.setup(job_database, equipment_database)
	equipment_system.setup(equipment_database, job_database, status_calculator)
	weapon_power_calculator.setup(status_calculator)
	job_unlock_system.setup(job_database)
	skill_database.configure_phase_11_5_scaling()
	for unit: BattleUnit in unit_manager.units:
		if unit.team == "player": job_unlock_system.unlock_available_jobs(unit)
		unit.refresh_build_stats(status_calculator)
	line_of_sight.setup(grid)
	attack_system.setup(grid, line_of_sight, equipment_database, weapon_power_calculator)
	skill_system.setup(grid, unit_manager, attack_system, element_system, line_of_sight, status_calculator, equipment_database, weapon_power_calculator)
	job_system.setup(job_database)
	experience_system.setup(job_database)
	skill_unlock_system.setup(job_database)
	threat_system.setup(unit_manager, attack_system, pathfinding, grid, skill_database, skill_system)
	unit_mover.setup(grid)
	enemy_ai.setup(grid, unit_manager, pathfinding, attack_system, unit_mover, skill_database, skill_system)
	enemy_ai.floating_result.connect(_show_floating_result)
	var stage_data := StageData.new()
	stage_manager.stage_message.connect(_on_stage_message)
	stage_manager.stage_finished.connect(_on_battle_ended)
	stage_manager.setup(stage_data, grid, unit_manager, trigger_manager, event_manager)
	mission_ui.setup(stage_data.stage_name)
	unit_info.setup(equipment_database)
	cursor.setup(grid, camera_controller.setup(), camera_controller)
	direction_compass.setup(camera_controller)
	cursor.confirm_pressed.connect(_on_confirm)
	cursor.cancel_pressed.connect(_on_cancel)
	cursor.grid_position_changed.connect(_on_cursor_grid_position_changed)
	action_menu.attack_selected.connect(_on_attack_selected)
	action_menu.wait_selected.connect(_on_wait_selected)
	action_menu.cancel_selected.connect(_cancel_after_move)
	action_menu.skill_selected.connect(_on_skill_menu_requested)
	action_menu.move_selected.connect(_on_move_selected)
	facing_selector.direction_selected.connect(_on_facing_selected)
	facing_selector.cancelled.connect(_on_facing_cancelled)
	combat_confirm.confirmed.connect(_on_combat_confirmed)
	combat_confirm.cancelled.connect(_on_combat_cancelled)
	skill_menu.skill_selected.connect(_on_skill_selected)
	skill_menu.cancelled.connect(_on_skill_menu_cancelled)
	skill_confirm.confirmed.connect(_on_skill_confirmed)
	skill_confirm.cancelled.connect(_on_skill_confirm_cancelled)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.combat_message.connect(_on_combat_message)
	turn_manager.battle_ended.connect(_on_battle_ended)
	turn_manager.actor_ready.connect(_on_ct_actor_ready)
	turn_manager.turn_order_changed.connect(_on_turn_order_changed)
	turn_manager.setup(unit_manager)
	pre_battle_setup.battle_started.connect(_on_pre_battle_started)
	pre_battle_setup.setup(unit_manager.get_player_units(), job_database, skill_database, skill_unlock_system, job_unlock_system, status_calculator, equipment_database, equipment_system)
	cursor.input_enabled = false
	_update_unit_info(cursor.grid_position)


func _add_jungle_log_column_near_player_start() -> void:
	var decoration := MapDecorationData.new()
	decoration.kind = "jungle_log_column"
	decoration.grid_position = JUNGLE_LOG_COLUMN_POSITION
	voxel_map.decorations.append(decoration)


func _add_oak_log_column_near_player_start() -> void:
	var decoration := MapDecorationData.new()
	decoration.kind = "oak_log_column"
	decoration.grid_position = OAK_LOG_COLUMN_POSITION
	voxel_map.decorations.append(decoration)


func _add_acacia_log_column_near_player_start() -> void:
	var decoration := MapDecorationData.new()
	decoration.kind = "acacia_log_column"
	decoration.grid_position = ACACIA_LOG_COLUMN_POSITION
	voxel_map.decorations.append(decoration)


func _apply_masonry_showcase_to_grid() -> void:
	for entry: Dictionary in MASONRY_SHOWCASE:
		var grid_position: Vector2i = entry.position
		var cell: GridCell = grid.get_cell(grid_position)
		if cell:
			var approach_cell: GridCell = grid.get_cell(grid_position + Vector2i.LEFT)
			var surface_height := approach_cell.height + 1 if approach_cell else cell.height + 1
			cell.set_surface(entry.kind, surface_height)

func _on_pre_battle_started() -> void:
	unit_progress.update_progress_from_units(unit_manager.get_player_units())
	save_manager.save_game()
	cursor.input_enabled = false
	battle_message.show_message("Battle Start")
	battle_log.add_message("Battle started")
	turn_manager.start_battle()


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
	elif cursor.current_mode == BattleCursor.CursorMode.SKILL_TARGETING:
		_confirm_skill_target(grid_pos)
	elif cursor.current_mode == BattleCursor.CursorMode.ACTION_MENU:
		var selected := unit_manager.selected_unit
		if selected and is_move_destination_provisional and reachable.has(grid_pos):
			action_menu.close()
			_confirm_move(grid_pos)


func _select_unit(grid_pos: Vector2i) -> void:
	var unit := unit_manager.unit_at(grid_pos)
	if not unit or unit.team != "player" or unit != turn_manager.current_actor:
		_update_status("未行動の味方ユニットを選択してください")
		return
	unit_manager.select_unit(unit)
	original_grid_pos = grid_pos
	original_facing = unit.facing
	unit.has_moved = false
	unit.has_used_action = false
	pending_wait_action = false
	pending_move_path.clear()
	is_move_destination_provisional = false
	reachable.clear()
	cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
	cursor.input_enabled = false
	action_menu.open(unit)
	_update_status("%sの行動を選択" % unit.unit_name)


func _on_move_selected() -> void:
	action_menu.close()
	var unit := unit_manager.selected_unit
	if reachable.is_empty():
		reachable = pathfinding.find_reachable(grid, original_grid_pos, unit.move_range, unit.jump_height)
	_show_move_range(unit, original_grid_pos)
	cursor.current_mode = BattleCursor.CursorMode.MOVE_TARGETING
	cursor.input_enabled = true
	_update_move_threat_preview(cursor.grid_position)
	_update_status("%sの移動先を選択" % unit.unit_name)


func _confirm_move(grid_pos: Vector2i) -> void:
	if not reachable.has(grid_pos):
		_update_status("そこへは移動できません")
		return
	var unit := unit_manager.selected_unit
	var current_position := Vector2i(unit.grid_x, unit.grid_z)
	pending_move_path = pathfinding.find_path_from(grid, unit, original_grid_pos, grid_pos) if grid_pos != original_grid_pos else []
	if grid_pos != current_position:
		unit_manager.move_selected_to(grid_pos)
	unit.has_moved = grid_pos != original_grid_pos
	is_move_destination_provisional = true
	if unit.has_used_action:
		threat_arrows.clear_threat_arrows()
		cursor.clear_reachable()
		_request_final_facing("移動後の向きを選択してください")
	else:
		cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
		cursor.input_enabled = true
		action_menu.open(unit, true)
		_update_move_threat_preview(grid_pos)
		_update_status("移動先は再選択できます / 攻撃・スキル・待機で確定")


func _on_attack_selected() -> void:
	action_menu.close()
	threat_arrows.clear_threat_arrows()
	cursor.clear_reachable()
	var cells := attack_system.get_attackable_cells(unit_manager.selected_unit)
	cursor.show_attack_range(cells)
	cursor.current_mode = BattleCursor.CursorMode.ATTACK_TARGETING
	cursor.input_enabled = true
	_update_status("攻撃対象を選択 / Escで戻る")

func _on_skill_menu_requested() -> void:
	action_menu.close()
	threat_arrows.clear_threat_arrows()
	cursor.clear_reachable()
	skill_menu.open(unit_manager.selected_unit, skill_database.get_skills_for_unit(unit_manager.selected_unit))
	cursor.current_mode = BattleCursor.CursorMode.SKILL_MENU

func _on_skill_selected(skill: SkillData) -> void:
	selected_skill = skill
	skill_menu.close()
	var cells := skill_system.get_skill_range_cells(unit_manager.selected_unit, skill)
	cursor.show_skill_range(cells, skill.skill_type == SkillData.SkillType.HEAL)
	cursor.current_mode = BattleCursor.CursorMode.SKILL_TARGETING
	cursor.input_enabled = true
	_update_status("%sの対象を選択" % skill.skill_name)

func _confirm_skill_target(grid_pos: Vector2i) -> void:
	if not skill_system.can_target_skill(unit_manager.selected_unit, selected_skill, grid_pos):
		_update_status("そのマスは対象にできません")
		return
	selected_skill_target = grid_pos
	var preview := skill_system.calculate_preview(unit_manager.selected_unit, selected_skill, grid_pos)
	if selected_skill.area_radius > 0: cursor.show_skill_area(skill_system.get_skill_area_cells(grid_pos, selected_skill))
	skill_confirm.open(unit_manager.selected_unit, selected_skill, grid_pos, preview)
	cursor.current_mode = BattleCursor.CursorMode.SKILL_CONFIRM
	cursor.input_enabled = false

func _on_skill_confirmed() -> void:
	skill_confirm.close()
	await _play_pending_movement()
	var result := skill_system.execute_skill(unit_manager.selected_unit, selected_skill, selected_skill_target)
	var acting_unit := unit_manager.selected_unit
	var total_exp := 0
	var defeat_count := 0
	for target_result: Dictionary in result.results:
		var type: String = target_result.result_type
		var amount := int(target_result.heal) if type == "heal" else int(target_result.damage)
		_show_floating_result(target_result.target, "critical" if bool(target_result.get("critical", false)) else type, amount)
		if type == "damage" and amount > 0: total_exp += experience_system.calculate_action_exp(acting_unit, target_result.target, true)
		elif type == "heal" and amount > 0: total_exp += experience_system.calculate_action_exp(acting_unit, target_result.target, true)
		if bool(target_result.defeated): defeat_count += 1
	total_exp += defeat_count * 30
	_grant_growth(acting_unit, total_exp, 8 + defeat_count * 5)
	battle_log.add_message(result.message)
	_update_status(result.message.replace("\n", " / "))
	selected_skill = null
	unit_manager.selected_unit.has_used_action = true
	cursor.clear_reachable()
	_after_primary_action("スキルを使用しました")

func _on_skill_confirm_cancelled() -> void:
	skill_confirm.close()
	cursor.current_mode = BattleCursor.CursorMode.SKILL_TARGETING
	cursor.input_enabled = true
	cursor.show_skill_range(skill_system.get_skill_range_cells(unit_manager.selected_unit, selected_skill), selected_skill.skill_type == SkillData.SkillType.HEAL)

func _on_skill_menu_cancelled() -> void:
	skill_menu.close()
	_return_to_action_menu()


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
	await _play_pending_movement()
	camera_controller.pulse_focus()
	var result := attack_system.execute_attack(attacker, target)
	var gained_exp := experience_system.calculate_action_exp(attacker, target, bool(result.hit) and int(result.damage) > 0)
	if bool(result.defeated): gained_exp += 30
	_grant_growth(attacker, gained_exp, 5 + (5 if result.defeated else 0))
	_show_floating_result(target, "critical" if bool(result.get("critical", false)) else ("damage" if result.hit else "miss"), int(result.damage))
	battle_log.show_attack_result(attacker, target, result)
	_update_status(result.message)
	if not target.is_alive(): unit_manager.remove_unit(target)
	selected_attack_target = null
	attacker.has_used_action = true
	_after_primary_action("攻撃しました")


func _after_primary_action(message: String) -> void:
	var unit := unit_manager.selected_unit
	if unit.has_moved:
		_request_final_facing("%s。向きを選択してください" % message)
	else:
		cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
		cursor.input_enabled = false
		action_menu.open(unit)
		_update_status("%s。移動または待機を選択してください" % message)


func _on_combat_cancelled() -> void:
	combat_confirm.close()
	selected_attack_target = null
	cursor.current_mode = BattleCursor.CursorMode.ATTACK_TARGETING
	cursor.input_enabled = true
	cursor.show_attack_range(attack_system.get_attackable_cells(unit_manager.selected_unit))


func _on_wait_selected() -> void:
	action_menu.close()
	threat_arrows.clear_threat_arrows()
	cursor.clear_reachable()
	pending_wait_action = not unit_manager.selected_unit.has_used_action
	_request_final_facing("待機後の向きを選択してください")


func _request_final_facing(message: String) -> void:
	action_menu.close()
	cursor.input_enabled = false
	facing_selector.open()
	_update_status(message)


func _on_facing_selected(direction: BattleUnit.FacingDirection) -> void:
	facing_selector.close()
	await _play_pending_movement()
	unit_manager.selected_unit.set_facing(direction)
	_finish_action()


func _on_facing_cancelled() -> void:
	var direction := unit_manager.selected_unit.facing
	facing_selector.close()
	await _play_pending_movement()
	unit_manager.selected_unit.set_facing(direction)
	_finish_action()


func _play_pending_movement() -> void:
	if pending_move_path.is_empty():
		return
	var unit := unit_manager.selected_unit
	if not unit:
		pending_move_path.clear()
		return
	cursor.input_enabled = false
	unit.position = grid.grid_to_world(original_grid_pos, 0.05)
	await unit_mover.move_unit_along_path(unit, pending_move_path)
	pending_move_path.clear()


func _finish_action() -> void:
	threat_arrows.clear_threat_arrows()
	var finished_actor := unit_manager.selected_unit
	unit_manager.mark_unit_acted(finished_actor, finished_actor.has_moved)
	unit_manager.clear_selection()
	cursor.clear_reachable()
	reachable.clear()
	is_move_destination_provisional = false
	cursor.current_mode = BattleCursor.CursorMode.IDLE
	cursor.input_enabled = false
	_update_unit_info(cursor.grid_position)
	if _check_battle_result(): return
	battle_log.add_message(("%s waits" if pending_wait_action else "%s ends action") % finished_actor.unit_name)
	turn_manager.finish_actor_turn(finished_actor, pending_wait_action)
	pending_wait_action = false


func _on_cancel() -> void:
	if cursor.current_mode == BattleCursor.CursorMode.ATTACK_TARGETING:
		_return_to_action_menu()
	elif cursor.current_mode == BattleCursor.CursorMode.MOVE_TARGETING:
		if is_move_destination_provisional:
			_return_to_action_menu()
		else:
			threat_arrows.clear_threat_arrows()
			cursor.clear_reachable()
			cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
			cursor.input_enabled = false
			action_menu.open(unit_manager.selected_unit)
	elif cursor.current_mode == BattleCursor.CursorMode.ACTION_MENU:
		_cancel_after_move()
	elif cursor.current_mode == BattleCursor.CursorMode.COMBAT_CONFIRM:
		_on_combat_cancelled()
	elif cursor.current_mode == BattleCursor.CursorMode.SKILL_TARGETING:
		cursor.clear_reachable()
		_on_skill_menu_requested()
	elif cursor.current_mode == BattleCursor.CursorMode.SKILL_CONFIRM:
		_on_skill_confirm_cancelled()


func _cancel_after_move() -> void:
	action_menu.close()
	threat_arrows.clear_threat_arrows()
	var unit := unit_manager.selected_unit
	if not unit: return
	if unit.has_used_action:
		_request_final_facing("行動後の向きを選択してください")
		return
	if Vector2i(unit.grid_x, unit.grid_z) != original_grid_pos:
		unit_manager.move_unit_to_grid(unit, original_grid_pos)
	pending_move_path.clear()
	is_move_destination_provisional = false
	unit.has_moved = false
	unit.set_facing(original_facing)
	cursor.set_grid_position(original_grid_pos)
	unit_manager.clear_selection()
	cursor.clear_reachable()
	reachable.clear()
	cursor.current_mode = BattleCursor.CursorMode.IDLE
	cursor.input_enabled = true
	_update_status("行動選択を解除しました")


func _return_to_action_menu() -> void:
	var unit := unit_manager.selected_unit
	cursor.current_mode = BattleCursor.CursorMode.ACTION_MENU
	if unit and is_move_destination_provisional:
		_show_move_range(unit, original_grid_pos)
		_update_move_threat_preview(Vector2i(unit.grid_x, unit.grid_z))
		cursor.input_enabled = true
		action_menu.open(unit, true)
		_update_status("移動先は再選択できます / 攻撃・スキル・待機で確定")
	else:
		cursor.clear_reachable()
		cursor.input_enabled = false
		action_menu.open(unit)


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


func _on_ct_actor_ready(actor: BattleUnit) -> void:
	if is_battle_finished: return
	battle_hud.update_current_actor(actor)
	turn_order_panel.update_order(actor, turn_manager.estimate_turn_order(5))
	battle_message.show_message("%s Turn" % actor.unit_name)
	battle_log.add_message("%s is ready" % actor.unit_name)
	camera_controller.focus_on_unit(actor)
	stage_manager.on_turn_started(turn_manager.turn_count)
	if not stage_manager.check_result(turn_manager.turn_count).is_empty(): return
	cursor.set_grid_position(Vector2i(actor.grid_x, actor.grid_z))
	if actor.team == "player":
		cursor.input_enabled = true
		cursor.current_mode = BattleCursor.CursorMode.IDLE
		_select_unit(Vector2i(actor.grid_x, actor.grid_z))
	else:
		cursor.input_enabled = false
		unit_manager.clear_selection()
		action_menu.close()
		var result_message: String = await enemy_ai.process_enemy_unit(actor)
		_on_combat_message(result_message)
		if _check_battle_result(): return
		turn_manager.finish_actor_turn(actor, false)


func _on_turn_order_changed(order: Array[BattleUnit]) -> void:
	turn_order_panel.update_order(turn_manager.current_actor, order)


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


func _on_cursor_grid_position_changed(grid_pos: Vector2i) -> void:
	_update_unit_info(grid_pos)
	if cursor.current_mode == BattleCursor.CursorMode.MOVE_TARGETING:
		_update_move_threat_preview(grid_pos)
	elif cursor.current_mode == BattleCursor.CursorMode.ACTION_MENU and is_move_destination_provisional:
		# Keep showing the threat for the confirmed provisional destination.
		pass
	else:
		threat_arrows.clear_threat_arrows()


func _update_move_threat_preview(grid_pos: Vector2i) -> void:
	var unit := unit_manager.selected_unit
	if not unit or not reachable.has(grid_pos):
		threat_arrows.clear_threat_arrows()
		return
	var enemies: Array[BattleUnit] = threat_system.get_threatening_enemies_for_cell(unit, grid_pos)
	if enemies.is_empty():
		threat_arrows.clear_threat_arrows()
		return
	threat_arrows.show_threat_arrows_to_position(enemies, grid.grid_to_world(grid_pos, 0.05))


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
	if is_battle_finished: return
	is_battle_finished = true
	battle_result = result
	turn_manager.stop_battle()
	cursor.input_enabled = false
	action_menu.close()
	facing_selector.close()
	combat_confirm.close()
	skill_menu.close()
	skill_confirm.close()
	threat_arrows.clear_threat_arrows()
	_update_status(result)
	battle_message.show_message("Mission Complete" if result == "Victory" else "Defeat", 4.0)
	if result == "Victory":
		unit_progress.update_progress_from_units(unit_manager.get_player_units())
		stage_progress.mark_stage_cleared(player_profile.current_stage_id, turn_manager.turn_count)
		var saved := save_manager.save_game()
		growth_panel.show_results(unit_manager.get_player_units(), saved)
	else:
		_update_status("Defeat - Enter / Space / Click to retry")


func _unhandled_input(event: InputEvent) -> void:
	if not is_battle_finished or battle_result != "Defeat": return
	var retry_requested := event.is_action_pressed("ui_accept")
	if event is InputEventMouseButton:
		retry_requested = retry_requested or (event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if retry_requested:
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


func _on_save_status(message: String) -> void:
	if battle_log:
		battle_log.add_message(message)


func _update_status(message: String) -> void:
	battle_hud.set_status(message)

func _show_floating_result(target: BattleUnit, result_type: String, amount: int) -> void:
	if result_type == "damage": floating_numbers.show_damage(target, amount)
	elif result_type == "critical": floating_numbers.show_critical(target, amount)
	elif result_type == "heal": floating_numbers.show_heal(target, amount)
	elif result_type == "miss": floating_numbers.show_miss(target)

func _grant_growth(unit: BattleUnit, exp_amount: int, job_exp_amount: int) -> void:
	if unit.team != "player": return
	if exp_amount > 0:
		var exp_result := experience_system.grant_exp(unit, exp_amount)
		battle_log.add_message("%s gains %d EXP" % [unit.unit_name, exp_amount])
		for level_up: Dictionary in exp_result.level_ups:
			var message := "LEVEL UP!\n%s Lv %d" % [unit.unit_name, level_up.new_level]
			battle_log.add_message(message)
			battle_message.show_message(message)
	var job_result := job_system.grant_job_exp(unit, job_exp_amount)
	battle_log.add_message("%s gains %d JobEXP" % [unit.unit_name, job_exp_amount])
	for job_up: Dictionary in job_result.level_ups:
		var message := "JOB LEVEL UP!\n%s %s Lv %d" % [unit.unit_name, unit.job_name, job_up.job_level]
		battle_log.add_message(message)
		battle_message.show_message(message)
	for skill_id: String in job_result.learned:
		var skill := skill_database.get_skill(skill_id)
		var message := "SKILL UNLOCKED!\n%s\nSet it before the next battle" % (skill.skill_name if skill else skill_id)
		battle_log.add_message(message)
		battle_message.show_message(message)
	var new_jobs := job_unlock_system.unlock_available_jobs(unit)
	for job_id: String in new_jobs:
		var unlocked_job := job_database.get_job(job_id)
		battle_log.add_message("JOB UNLOCKED! %s" % (unlocked_job.job_name if unlocked_job else job_id))
	unit.refresh_build_stats(status_calculator)


func _show_move_range(unit: BattleUnit, origin: Vector2i) -> void:
	var danger_cells: Dictionary = {}
	for grid_pos: Vector2i in reachable:
		if threat_system.is_cell_threatened(unit, grid_pos): danger_cells[grid_pos] = true
	cursor.show_move_range(reachable, origin, danger_cells)
