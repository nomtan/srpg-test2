class_name BattlePathfinding
extends Node

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]


func find_reachable(
	grid: GridSystem,
	start: Vector2i,
	move_range: int,
	jump_height: int
) -> Dictionary:
	var costs: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]

	# 盤面が小さいため、最小コストの要素を都度選ぶ単純な Dijkstra で十分。
	while not frontier.is_empty():
		var current_index := _lowest_cost_index(frontier, costs)
		var current: Vector2i = frontier.pop_at(current_index)
		var current_cell: GridCell = grid.get_cell(current)

		for direction: Vector2i in DIRECTIONS:
			var next_pos: Vector2i = current + direction
			if not grid.is_in_bounds(next_pos):
				continue
			var next_cell: GridCell = grid.get_cell(next_pos)
			if not next_cell.walkable or next_cell.blocks_movement or next_cell.occupied_unit != null:
				continue
			if absi(next_cell.height - current_cell.height) > jump_height:
				continue

			var new_cost: int = costs[current] + next_cell.move_cost
			if new_cost > move_range:
				continue
			if not costs.has(next_pos) or new_cost < costs[next_pos]:
				costs[next_pos] = new_cost
				if next_pos not in frontier:
					frontier.append(next_pos)

	return costs


func _lowest_cost_index(frontier: Array[Vector2i], costs: Dictionary) -> int:
	var best_index := 0
	for index in range(1, frontier.size()):
		if costs[frontier[index]] < costs[frontier[best_index]]:
			best_index = index
	return best_index

func find_path(grid: GridSystem, unit: BattleUnit, destination: Vector2i) -> Array[Vector2i]:
	return find_path_from(grid, unit, Vector2i(unit.grid_x, unit.grid_z), destination)

func find_path_from(grid: GridSystem, unit: BattleUnit, start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == destination: break
		for direction in DIRECTIONS:
			var next_pos := current + direction
			if not grid.is_in_bounds(next_pos) or came_from.has(next_pos): continue
			var cell := grid.get_cell(next_pos)
			if not cell.walkable or cell.blocks_movement: continue
			if cell.occupied_unit and cell.occupied_unit != unit and next_pos != destination: continue
			if absi(cell.height - grid.get_cell(current).height) > unit.jump_height: continue
			came_from[next_pos] = current
			frontier.append(next_pos)
	if not came_from.has(destination): return []
	var path: Array[Vector2i] = []
	var step := destination
	while step != start:
		path.push_front(step)
		step = came_from[step]
	return path
