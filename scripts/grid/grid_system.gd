class_name GridSystem
extends Node

const WIDTH := 8
const DEPTH := 8
const CELL_SIZE := 1.0

var cells: Dictionary = {}


func generate_grid() -> void:
	cells.clear()
	for z in DEPTH:
		for x in WIDTH:
			var height := 1
			var terrain := "grass"
			var walkable := true
			var move_cost := 1

			# 中央の丘、北東の崖、泥地、岩を持つ小さなテスト盤面。
			if x in [3, 4] and z in [3, 4]:
				height = 2
				terrain = "dirt"
			if x >= 5 and z <= 2:
				height = 3
				terrain = "stone"
			if Vector2i(x, z) in [Vector2i(1, 5), Vector2i(2, 5), Vector2i(2, 6)]:
				terrain = "dirt"
				move_cost = 2
			if Vector2i(x, z) in [Vector2i(4, 1), Vector2i(6, 4), Vector2i(5, 6)]:
				terrain = "rock"
				walkable = false

			cells[Vector2i(x, z)] = GridCell.new(
				x, z, height, terrain, walkable, move_cost
			)


func is_in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < WIDTH and position.y >= 0 and position.y < DEPTH


func get_cell(position: Vector2i) -> GridCell:
	return cells.get(position) as GridCell


func grid_to_world(position: Vector2i, extra_height: float = 0.0) -> Vector3:
	var cell := get_cell(position)
	var surface_height := float(cell.height) if cell else 0.0
	return Vector3(
		(float(position.x) + 0.5) * CELL_SIZE,
		surface_height + extra_height,
		(float(position.y) + 0.5) * CELL_SIZE
	)


func world_to_grid(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL_SIZE), floori(world_position.z / CELL_SIZE))
