class_name GridCell
extends RefCounted

var x: int
var z: int
var height: int
var terrain: String
var walkable: bool
var move_cost: int
var occupied_unit: BattleUnit
var evasion_bonus: int = 0
var defense_bonus: int = 0
var blocks_line_of_sight: bool = false
var blocks_movement: bool = false


func _init(
	cell_x: int,
	cell_z: int,
	cell_height: int = 1,
	cell_terrain: String = "grass",
	cell_walkable: bool = true,
	cell_move_cost: int = 1
) -> void:
	x = cell_x
	z = cell_z
	height = cell_height
	terrain = cell_terrain
	walkable = cell_walkable
	move_cost = cell_move_cost
	_apply_terrain_effects()


func _apply_terrain_effects() -> void:
	match terrain:
		"stone": defense_bonus = 1
		"forest":
			move_cost = 2
			evasion_bonus = 15
		"water":
			move_cost = 2
			evasion_bonus = -10
		"high_ground":
			evasion_bonus = 5
			defense_bonus = 1
		"rock", "wall":
			walkable = false
			blocks_movement = true
			blocks_line_of_sight = true
