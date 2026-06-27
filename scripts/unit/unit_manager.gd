class_name UnitManager
extends Node3D

var grid: GridSystem
var units: Array[BattleUnit] = []
var selected_unit: BattleUnit


func setup(source_grid: GridSystem) -> void:
	grid = source_grid
	spawn_initial_units()


func spawn_initial_units() -> void:
	_spawn_unit("vain", "Vain", Vector2i(1, 1), "player", 120, 30, 8, 90, 10)
	_spawn_unit("acrea", "Acrea", Vector2i(2, 1), "player", 90, 24, 5, 92, 15)
	_spawn_unit("glen", "Glen", Vector2i(1, 2), "player", 100, 22, 5, 85, 12, BattleUnit.AttackType.RANGED, 2, 3)
	var boss := _spawn_unit("bandit_a", "Bandit A", Vector2i(6, 6), "enemy", 80, 22, 4, 85, 8)
	boss.enemy_type = BattleUnit.EnemyType.BOSS
	var sniper := _spawn_unit("bandit_b", "Bandit B", Vector2i(5, 6), "enemy", 70, 18, 3, 80, 10, BattleUnit.AttackType.RANGED, 2, 3)
	sniper.enemy_type = BattleUnit.EnemyType.SNIPER


func _spawn_unit(
	unit_id: String,
	display_name: String,
	grid_pos: Vector2i,
	team: String,
	max_hp: int,
	power: int,
	armor: int,
	accuracy: int,
	evasion: int,
	attack_type: BattleUnit.AttackType = BattleUnit.AttackType.MELEE,
	min_range: int = 1,
	max_range: int = 1
) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.configure(unit_id, display_name, grid_pos, team)
	unit.set_combat_stats(max_hp, power, armor, accuracy, evasion, attack_type, min_range, max_range)
	unit.setup_visual()
	add_child(unit)
	units.append(unit)
	grid.set_occupied_unit(grid_pos, unit)
	unit.snap_to_grid(grid)
	return unit


func unit_at(grid_pos: Vector2i) -> BattleUnit:
	var cell := grid.get_cell(grid_pos)
	return cell.occupied_unit if cell else null


func get_unit_by_id(id: String) -> BattleUnit:
	for unit in units:
		if unit.unit_id == id: return unit
	return null


func spawn_reinforcement(id: String, display_name: String, grid_pos: Vector2i, ai_type: BattleUnit.EnemyType) -> BattleUnit:
	if not grid.get_cell(grid_pos).walkable or grid.get_cell(grid_pos).occupied_unit:
		for candidate: Vector2i in grid.cells:
			var cell := grid.get_cell(candidate)
			if cell.walkable and not cell.blocks_movement and not cell.occupied_unit:
				grid_pos = candidate
				break
	var unit := _spawn_unit(id, display_name, grid_pos, "enemy", 85, 23, 5, 86, 9)
	unit.enemy_type = ai_type
	return unit


func select_unit(unit: BattleUnit) -> void:
	if selected_unit:
		selected_unit.set_selected(false)
	selected_unit = unit
	if selected_unit:
		selected_unit.set_selected(true)


func clear_selection() -> void:
	select_unit(null)


func get_units_for_team(team: String) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in units:
		if unit.team == team and unit.is_alive():
			result.append(unit)
	return result


func get_player_units() -> Array[BattleUnit]:
	return get_units_for_team("player")


func get_enemy_units() -> Array[BattleUnit]:
	return get_units_for_team("enemy")


func are_all_player_units_acted() -> bool:
	for unit in get_player_units():
		if not unit.has_acted:
			return false
	return true


func reset_player_units_action_state() -> void:
	for unit in get_player_units():
		unit.reset_action_state()


func mark_unit_acted(unit: BattleUnit, moved: bool = true) -> void:
	unit.mark_acted(moved)


func remove_unit(unit: BattleUnit) -> void:
	grid.clear_occupied_unit(Vector2i(unit.grid_x, unit.grid_z))
	unit.die()


func are_all_enemies_defeated() -> bool:
	return get_enemy_units().is_empty()


func are_all_players_defeated() -> bool:
	return get_player_units().is_empty()


func move_selected_to(destination: Vector2i) -> void:
	if not selected_unit:
		return
	move_unit_to_grid(selected_unit, destination)


func move_unit_to_grid(unit: BattleUnit, destination: Vector2i) -> void:
	var old_position := Vector2i(unit.grid_x, unit.grid_z)
	unit.face_toward(destination)
	grid.move_occupied_unit(old_position, destination, unit)
	unit.grid_x = destination.x
	unit.grid_z = destination.y
	unit.snap_to_grid(grid)
