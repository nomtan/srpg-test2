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
			if not next_cell.walkable or next_cell.occupied_unit != null:
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
