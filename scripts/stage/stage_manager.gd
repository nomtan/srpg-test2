class_name StageManager
extends Node3D

signal stage_message(message: String)
signal stage_finished(result: String)

var data: StageData
var grid: GridSystem
var units: UnitManager
var triggers: TriggerManager
var events: EventManager
var objects: Dictionary = {}
var finished := false


func setup(stage_data: StageData, source_grid: GridSystem, unit_manager: UnitManager, trigger_manager: TriggerManager, event_manager: EventManager) -> void:
	data = stage_data
	grid = source_grid
	units = unit_manager
	triggers = trigger_manager
	events = event_manager
	_spawn_object("chest_1", StageObject.ObjectType.CHEST, Vector2i(2, 4))
	_spawn_object("lever_1", StageObject.ObjectType.LEVER, Vector2i(0, 6))
	_spawn_object("door_1", StageObject.ObjectType.DOOR, Vector2i(4, 5))
	_set_door_blocked(true)
	stage_message.emit("Mission Start: %s" % data.stage_name)


func _spawn_object(id: String, type: StageObject.ObjectType, grid_pos: Vector2i) -> void:
	var object := StageObject.new()
	object.configure(id, type, grid_pos, grid)
	add_child(object)
	objects[grid_pos] = object


func interact_at(grid_pos: Vector2i) -> bool:
	var object: StageObject = objects.get(grid_pos)
	if not object or object.activated: return false
	match object.object_type:
		StageObject.ObjectType.CHEST:
			object.activate()
			stage_message.emit("Treasure acquired: Ancient Emblem")
		StageObject.ObjectType.LEVER:
			object.activate()
			_set_door_blocked(false)
			stage_message.emit("Lever activated — Door opened")
		StageObject.ObjectType.DOOR:
			stage_message.emit("The door is locked. Find the lever.")
	return true


func _set_door_blocked(blocked: bool) -> void:
	var cell := grid.get_cell(Vector2i(4, 5))
	cell.walkable = not blocked
	cell.blocks_movement = blocked
	cell.blocks_line_of_sight = blocked
	var door: StageObject = objects.get(Vector2i(4, 5))
	if door:
		door.visible = blocked
		if not blocked: door.activated = true


func on_turn_started(turn_count: int) -> void:
	if triggers.should_fire("reinforcement", turn_count >= data.reinforcement_turn):
		units.spawn_reinforcement("bandit_c", "Bandit C", Vector2i(7, 4), BattleUnit.EnemyType.GUARD)
		events.fire_event("Reinforcement")
		stage_message.emit("Reinforcement!")


func check_result(turn_count: int) -> String:
	if finished: return ""
	if units.are_all_enemies_defeated(): return _finish("Victory")
	var main_unit := units.get_unit_by_id(data.main_character_id)
	if not main_unit or not main_unit.is_alive(): return _finish("Defeat")
	if data.defeat_condition == StageData.DefeatCondition.TURN_LIMIT and turn_count > data.turn_limit:
		return _finish("Defeat")
	return ""


func _finish(result: String) -> String:
	finished = true
	stage_finished.emit(result)
	return result
