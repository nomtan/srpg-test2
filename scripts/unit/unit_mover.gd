class_name UnitMover
extends Node

var grid: GridSystem

func setup(source_grid: GridSystem) -> void: grid = source_grid

func move_unit_along_path(unit: BattleUnit, path: Array[Vector2i]) -> void:
	for grid_pos in path:
		unit.face_toward(grid_pos)
		var destination := grid.grid_to_world(grid_pos, 0.05)
		var start := unit.position
		var tween := create_tween()
		tween.tween_method(func(t: float) -> void:
			var point := start.lerp(destination, t)
			point.y += sin(t * PI) * 0.22
			unit.position = point, 0.0, 1.0, 0.18)
		await tween.finished
	unit.position = grid.grid_to_world(path[-1], 0.05) if not path.is_empty() else unit.position
