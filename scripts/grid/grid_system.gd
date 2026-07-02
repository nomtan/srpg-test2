class_name GridSystem
extends Node

const WIDTH := 16
const DEPTH := 16
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

			if z >= 14:
				# Enemy base: fortified high ground with wall structures
				height = 2
				terrain = "high_ground"
				if x in [4, 11]:
					terrain = "rock"; height = 3; walkable = false
				elif x in [0, 1, 14, 15]:
					terrain = "wall"; height = 3; walkable = false
				elif x == 7 and z == 15:
					terrain = "stone"

			elif z == 13:
				# Enemy advance: elevated stone/high-ground plateau
				if x in [0, 15]:
					terrain = "forest"
				elif x in [6, 7, 8, 9]:
					terrain = "stone"; height = 2
				else:
					terrain = "high_ground"; height = 2

			elif z == 12:
				# Enemy approach: scattered rocks, edge forest
				if x in [5, 10]:
					terrain = "rock"; height = 2; walkable = false
				elif x in [0, 15]:
					terrain = "forest"

			elif z >= 8:
				# Mid-map contested zone
				if x == 7 and z == 8:
					terrain = "rock"; height = 2; walkable = false
				elif x == 9 and z == 8:
					terrain = "rock"; height = 2; walkable = false
				elif x in [1, 2] and z == 9:
					terrain = "forest"
				elif x in [13, 14] and z == 9:
					terrain = "forest"
				elif x == 6 and z == 10:
					terrain = "stone"; height = 2
				elif x == 9 and z == 10:
					terrain = "stone"; height = 2
				elif x in [3, 4] and z == 11:
					terrain = "forest"
				elif x in [11, 12] and z == 11:
					terrain = "forest"
				elif x in [0, 15]:
					terrain = "forest"

			elif z == 7:
				# River: water with grass fords at x=4 and x=11
				if x in [4, 11]:
					terrain = "grass"
				else:
					terrain = "water"; move_cost = 2

			elif z >= 4:
				# Transitional zone: hills, forest, river-approach rocks
				if x in [2, 3] and z in [4, 5]:
					height = 2; terrain = "high_ground"
				elif x in [12, 13] and z in [4, 5]:
					height = 2; terrain = "high_ground"
				elif x == 6 and z == 5:
					terrain = "forest"
				elif x == 9 and z == 5:
					terrain = "forest"
				elif x == 5 and z == 6:
					terrain = "rock"; height = 2; walkable = false
				elif x == 10 and z == 6:
					terrain = "rock"; height = 2; walkable = false
				elif x in [0, 15]:
					terrain = "forest"

			else:
				# Player start zone (z=0-3): flat grass with minor features
				if x in [0, 15]:
					terrain = "forest"
				elif x == 4 and z == 2:
					terrain = "forest"
				elif x == 10 and z == 2:
					terrain = "forest"
				elif x == 7 and z == 1:
					terrain = "rock"; height = 2; walkable = false

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


func set_occupied_unit(grid_pos: Vector2i, unit: BattleUnit) -> void:
	var cell := get_cell(grid_pos)
	if cell:
		cell.occupied_unit = unit


func clear_occupied_unit(grid_pos: Vector2i) -> void:
	set_occupied_unit(grid_pos, null)


func move_occupied_unit(from_pos: Vector2i, to_pos: Vector2i, unit: BattleUnit) -> void:
	clear_occupied_unit(from_pos)
	set_occupied_unit(to_pos, unit)
