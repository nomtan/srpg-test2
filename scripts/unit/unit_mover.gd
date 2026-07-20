class_name UnitMover
extends Node

var grid: GridSystem

func setup(source_grid: GridSystem) -> void: grid = source_grid

func move_unit_along_path(
	unit: BattleUnit,
	path: Array[Vector2i],
	start_grid_pos: Vector2i = Vector2i(-1, -1)
) -> void:
	if path.is_empty():
		return
	var current_grid_pos := start_grid_pos
	if not grid.is_in_bounds(current_grid_pos):
		current_grid_pos = Vector2i(unit.grid_x, unit.grid_z)
	unit.position = grid.grid_to_world(current_grid_pos, 0.05)
	unit.play_walk_animation()
	for grid_pos in path:
		unit.face_along_grid_delta(grid_pos - current_grid_pos)
		var destination := grid.grid_to_world(grid_pos, 0.05)
		var start := unit.position
		var tween := create_tween()
		var update_position := func(t: float) -> void:
			var point := start.lerp(destination, t)
			unit.position = point
		tween.tween_method(update_position, 0.0, 1.0, 0.18)
		await tween.finished
		current_grid_pos = grid_pos
	unit.stop_walk_animation()
	unit.position = grid.grid_to_world(path[-1], 0.05)
