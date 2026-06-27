class_name UnitManager
extends Node3D

var grid: GridSystem
var units: Array[BattleUnit] = []
var selected_unit: BattleUnit


func setup(source_grid: GridSystem) -> void:
	grid = source_grid
	var unit := BattleUnit.new()
	unit.name = "Vain"
	unit.setup_visual()
	add_child(unit)
	units.append(unit)
	grid.get_cell(Vector2i(unit.grid_x, unit.grid_z)).occupied_unit = unit
	unit.snap_to_grid(grid)


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


func move_selected_to(destination: Vector2i) -> void:
	if not selected_unit:
		return
	var old_position := Vector2i(selected_unit.grid_x, selected_unit.grid_z)
	grid.get_cell(old_position).occupied_unit = null
	selected_unit.grid_x = destination.x
	selected_unit.grid_z = destination.y
	grid.get_cell(destination).occupied_unit = selected_unit
	selected_unit.snap_to_grid(grid)
