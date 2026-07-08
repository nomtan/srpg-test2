class_name StageData
extends Resource

enum VictoryCondition { DEFEAT_ALL_ENEMIES, REACH_POINT, SURVIVE_TURNS, ESCORT, DEFEAT_BOSS }
enum DefeatCondition { ALL_PLAYER_DEAD, MAIN_CHARACTER_DEAD, TURN_LIMIT, NPC_DEAD }

@export var stage_name := "Ashen Pass"
@export var map_name := "Voxel Highlands"
@export var victory_condition := VictoryCondition.DEFEAT_ALL_ENEMIES
@export var defeat_condition := DefeatCondition.MAIN_CHARACTER_DEAD
@export var main_character_id := "vain"
@export var reinforcement_turn := 3
@export var turn_limit := 12
var player_spawn: Array[Vector2i] = [Vector2i(3, 3), Vector2i(6, 3), Vector2i(3, 6)]
var enemy_spawn: Array[Vector2i] = [Vector2i(18, 18), Vector2i(15, 18)]
var event_list: Array[Dictionary] = [{"type": "reinforcement", "turn": 3}]
