class_name GridCell
extends RefCounted

var x: int
var z: int
var height: int
var terrain: String
var walkable: bool
var move_cost: int
var occupied_unit: BattleUnit


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
