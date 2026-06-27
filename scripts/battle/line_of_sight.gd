class_name LineOfSight
extends Node

var grid: GridSystem


func setup(source_grid: GridSystem) -> void: grid = source_grid


func has_line_of_sight(attacker: BattleUnit, target: BattleUnit) -> bool:
	return has_line_between(Vector2i(attacker.grid_x, attacker.grid_z), Vector2i(target.grid_x, target.grid_z))


func has_line_between(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	var low_height := mini(grid.get_cell(from_pos).height, grid.get_cell(to_pos).height)
	for grid_pos in get_cells_between(from_pos, to_pos):
		var cell := grid.get_cell(grid_pos)
		if cell.blocks_line_of_sight and cell.height > low_height: return false
	return true


func get_cells_between(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var steps := maxi(absi(to_pos.x - from_pos.x), absi(to_pos.y - from_pos.y))
	for step in range(1, steps):
		var ratio := float(step) / float(steps)
		var grid_pos := Vector2i(roundi(lerpf(from_pos.x, to_pos.x, ratio)), roundi(lerpf(from_pos.y, to_pos.y, ratio)))
		if grid_pos not in result: result.append(grid_pos)
	return result
