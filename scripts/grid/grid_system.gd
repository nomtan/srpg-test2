class_name GridSystem
extends Node

const WIDTH := 40
const DEPTH := 40
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

			# ── PLAYER START ZONE (z=0–6) ──────────────────────────────────
			if z <= 6:
				if x == 0 or x == 39:
					terrain = "forest"
				elif x == 4 and z == 3:
					terrain = "forest"
				elif x == 35 and z == 3:
					terrain = "forest"
				elif x == 12 and z == 2:
					terrain = "rock"; height = 2; walkable = false
				elif x == 27 and z == 2:
					terrain = "rock"; height = 2; walkable = false
				elif x in [17, 18, 21, 22] and z == 5:
					terrain = "stone"; height = 2
				elif x in [9, 10] and z == 6:
					terrain = "forest"
				elif x in [29, 30] and z == 6:
					terrain = "forest"

			# ── APPROACH (z=7–13) ──────────────────────────────────────────
			elif z <= 13:
				if x == 0 or x == 39:
					terrain = "forest"
				elif x in [5, 6] and z in [7, 8]:
					terrain = "forest"
				elif x in [33, 34] and z in [7, 8]:
					terrain = "forest"
				elif x in [13, 14] and z == 9:
					terrain = "high_ground"; height = 2
				elif x in [25, 26] and z == 9:
					terrain = "high_ground"; height = 2
				elif x == 19 and z == 11:
					terrain = "rock"; height = 2; walkable = false
				elif x == 20 and z == 11:
					terrain = "rock"; height = 2; walkable = false
				elif x in [8, 9] and z == 12:
					terrain = "forest"
				elif x in [30, 31] and z == 12:
					terrain = "forest"
				elif x == 15 and z == 10:
					terrain = "stone"; height = 2
				elif x == 24 and z == 10:
					terrain = "stone"; height = 2
				elif x in [11, 12] and z == 13:
					terrain = "high_ground"; height = 2
				elif x in [27, 28] and z == 13:
					terrain = "high_ground"; height = 2

			# ── RIVER (z=14) ───────────────────────────────────────────────
			elif z == 14:
				if x in [6, 19, 33]:
					terrain = "grass"
				else:
					terrain = "water"; move_cost = 2

			# ── MID-MAP CONTESTED (z=15–21) ────────────────────────────────
			elif z <= 21:
				if x == 0 or x == 39:
					terrain = "forest"
				elif x in [3, 4] and z == 15:
					terrain = "forest"
				elif x in [35, 36] and z == 15:
					terrain = "forest"
				elif x == 10 and z == 16:
					terrain = "rock"; height = 2; walkable = false
				elif x == 29 and z == 16:
					terrain = "rock"; height = 2; walkable = false
				elif x in [16, 17] and z == 17:
					terrain = "stone"; height = 2
				elif x in [22, 23] and z == 17:
					terrain = "stone"; height = 2
				elif x in [7, 8] and z == 18:
					terrain = "forest"
				elif x in [31, 32] and z == 18:
					terrain = "forest"
				elif x in [13, 14] and z == 20:
					terrain = "high_ground"; height = 2
				elif x in [25, 26] and z == 20:
					terrain = "high_ground"; height = 2
				elif x == 19 and z == 21:
					terrain = "stone"; height = 2
				elif x == 20 and z == 21:
					terrain = "stone"; height = 2

			# ── LAVA ZONE (z=22–27) ────────────────────────────────────────
			# 3 crossing paths: left flank (x=0-6), center bridge (x=17-22),
			# right flank (x=33-39). Two lava pools between them.
			elif z <= 27:
				if x in [7, 16, 23, 32] and z == 22:
					# Rock sentinels marking the lava zone entrance
					terrain = "rock"; height = 2; walkable = false
				elif z >= 23 and z <= 25 and x >= 8 and x <= 15:
					# Left lava pool
					terrain = "lava"
				elif z >= 23 and z <= 25 and x >= 24 and x <= 31:
					# Right lava pool
					terrain = "lava"
				elif z == 24 and x >= 16 and x <= 23:
					# Elevated stone bridge over center (only middle row)
					terrain = "stone"; height = 2
				elif x == 7 and z in [23, 24, 25]:
					terrain = "rock"; height = 2; walkable = false
				elif x == 16 and z in [23, 25]:
					terrain = "rock"; height = 2; walkable = false
				elif x == 23 and z in [23, 25]:
					terrain = "rock"; height = 2; walkable = false
				elif x == 32 and z in [23, 24, 25]:
					terrain = "rock"; height = 2; walkable = false
				elif z in [23, 24, 25] and x in [4, 5]:
					# Left flank stone path (slightly elevated)
					terrain = "stone"; height = 2
				elif z in [23, 24, 25] and x in [34, 35]:
					# Right flank stone path
					terrain = "stone"; height = 2
				elif z in [22, 26]:
					if x == 0 or x == 39:
						terrain = "forest"
				elif z == 27:
					if x == 0 or x == 39:
						terrain = "forest"
					elif x in [10, 11] and z == 27:
						terrain = "high_ground"; height = 2
					elif x in [28, 29] and z == 27:
						terrain = "high_ground"; height = 2

			# ── ENEMY HIGHLAND (z=28–33) ───────────────────────────────────
			elif z <= 33:
				if x == 0 or x == 39:
					terrain = "forest"
				elif x in [16, 17, 22, 23] and z == 28:
					terrain = "high_ground"; height = 2
				elif x in [12, 13] and z == 29:
					terrain = "rock"; height = 2; walkable = false
				elif x in [26, 27] and z == 29:
					terrain = "rock"; height = 2; walkable = false
				elif x in [18, 19, 20, 21] and z == 30:
					terrain = "stone"; height = 2
				elif x in [8, 9] and z == 31:
					terrain = "forest"
				elif x in [30, 31] and z == 31:
					terrain = "forest"
				elif z == 32 and x in [5, 6, 7]:
					terrain = "high_ground"; height = 2
				elif z == 32 and x in [32, 33, 34]:
					terrain = "high_ground"; height = 2
				elif z == 32 and x in [15, 16, 23, 24]:
					terrain = "stone"

			# ── ENEMY ADVANCE (z=34–37) ────────────────────────────────────
			elif z <= 37:
				if x in [0, 1, 38, 39]:
					terrain = "wall"; height = 3; walkable = false
				elif x in [5, 6] and z == 34:
					terrain = "forest"
				elif x in [33, 34] and z == 34:
					terrain = "forest"
				elif x in [11, 12] and z == 35:
					terrain = "high_ground"; height = 2
				elif x in [27, 28] and z == 35:
					terrain = "high_ground"; height = 2
				elif x in [17, 18, 21, 22] and z == 36:
					terrain = "stone"; height = 2
				elif x == 14 and z in [36, 37]:
					terrain = "rock"; height = 3; walkable = false
				elif x == 25 and z in [36, 37]:
					terrain = "rock"; height = 3; walkable = false
				elif x in [8, 9, 10] and z == 37:
					terrain = "forest"
				elif x in [29, 30, 31] and z == 37:
					terrain = "forest"

			# ── ENEMY BASE (z=38–39) ───────────────────────────────────────
			else:
				if x in [0, 1, 2, 37, 38, 39]:
					terrain = "wall"; height = 3; walkable = false
				elif x in [7, 8, 31, 32] and z == 38:
					terrain = "rock"; height = 3; walkable = false
				elif x in [15, 16, 23, 24] and z == 38:
					terrain = "wall"; height = 3; walkable = false
				elif x in [19, 20] and z in [38, 39]:
					terrain = "stone"; height = 2
				else:
					height = 2; terrain = "high_ground"
					if x in [17, 18, 21, 22] and z == 38:
						terrain = "stone"

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
