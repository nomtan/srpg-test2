class_name UnitManager
extends Node3D

var grid: GridSystem
var units: Array[BattleUnit] = []
var selected_unit: BattleUnit


func setup(source_grid: GridSystem) -> void:
	grid = source_grid
	spawn_initial_units()


func spawn_initial_units() -> void:
	_spawn_unit("vain", "Vain", Vector2i(1, 1), "player", 120, 30, 8)
	_spawn_unit("acrea", "Acrea", Vector2i(2, 1), "player", 90, 24, 5)
	_spawn_unit("glen", "Glen", Vector2i(1, 2), "player", 110, 28, 7)
	_spawn_unit("bandit_a", "Bandit A", Vector2i(6, 6), "enemy", 80, 22, 4)
	_spawn_unit("bandit_b", "Bandit B", Vector2i(5, 6), "enemy", 80, 22, 4)


func _spawn_unit(
	unit_id: String,
	display_name: String,
	grid_pos: Vector2i,
	team: String,
	max_hp: int,
	power: int,
	armor: int
) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.configure(unit_id, display_name, grid_pos, team)
	unit.set_combat_stats(max_hp, power, armor)
	unit.setup_visual()
	add_child(unit)
	units.append(unit)
	grid.set_occupied_unit(grid_pos, unit)
	unit.snap_to_grid(grid)
	return unit


func unit_at(grid_pos: Vector2i) -> BattleUnit:
	var cell := grid.get_cell(grid_pos)
	return cell.occupied_unit if cell else null


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
	grid.move_occupied_unit(old_position, destination, unit)
	unit.grid_x = destination.x
	unit.grid_z = destination.y
	unit.snap_to_grid(grid)
