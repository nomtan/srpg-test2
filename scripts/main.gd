extends Node3D

@onready var grid: GridSystem = $GridSystem
@onready var voxel_map: VoxelMap = $VoxelMap
@onready var unit_manager: UnitManager = $UnitManager
@onready var cursor: BattleCursor = $BattleCursor
@onready var pathfinding: BattlePathfinding = $Pathfinding
@onready var camera_controller: CameraController = $CameraController
@onready var status_label: Label = $UI/MarginContainer/VBoxContainer/Status

var reachable: Dictionary = {}


func _ready() -> void:
	grid.generate_grid()
	voxel_map.build_from_grid(grid)
	unit_manager.setup(grid)
	var battle_camera := camera_controller.setup()
	cursor.setup(grid, battle_camera)
	cursor.confirm_pressed.connect(_on_confirm)
	cursor.cancel_pressed.connect(_on_cancel)
	_update_status("Vainを選択してください")


func _on_confirm() -> void:
	var grid_pos := cursor.grid_position
	if not unit_manager.selected_unit:
		var unit := unit_manager.unit_at(grid_pos)
		if not unit:
			_update_status("そのマスに味方はいません")
			return
		unit_manager.select_unit(unit)
		reachable = pathfinding.find_reachable(
			grid, grid_pos, unit.move_range, unit.jump_height
		)
		cursor.show_reachable(reachable, grid_pos)
		_update_status("移動先を選択（青いマス） / Escで解除")
		return

	if reachable.has(grid_pos) and grid_pos != Vector2i(
		unit_manager.selected_unit.grid_x, unit_manager.selected_unit.grid_z
	):
		unit_manager.move_selected_to(grid_pos)
		_finish_selection("移動しました。Vainをもう一度選択できます")
	else:
		_update_status("そこへは移動できません")


func _on_cancel() -> void:
	_finish_selection("選択を解除しました")


func _finish_selection(message: String) -> void:
	unit_manager.clear_selection()
	reachable.clear()
	cursor.clear_reachable()
	_update_status(message)


func _update_status(message: String) -> void:
	status_label.text = message
