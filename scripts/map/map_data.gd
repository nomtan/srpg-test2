class_name MapData
extends Resource

@export var width := 0
@export var depth := 0
@export var cells: Array[MapCellVisualData] = []

var _cell_lookup: Dictionary = {}


static func from_grid(grid: GridSystem, decorations: Array[MapDecorationData] = []) -> MapData:
	var data := MapData.new()
	data.width = GridSystem.WIDTH
	data.depth = GridSystem.DEPTH
	for grid_position: Vector2i in grid.cells:
		var source := grid.get_cell(grid_position)
		var visual_cell := MapCellVisualData.new()
		visual_cell.position = grid_position
		visual_cell.height = source.height
		visual_cell.terrain = source.terrain
		for decoration: MapDecorationData in decorations:
			if decoration.grid_position == grid_position:
				visual_cell.props.append(decoration)
		data.cells.append(visual_cell)
	data.rebuild_lookup()
	return data


func rebuild_lookup() -> void:
	_cell_lookup.clear()
	for cell: MapCellVisualData in cells:
		_cell_lookup[cell.position] = cell


func get_cell(position: Vector2i) -> MapCellVisualData:
	if _cell_lookup.is_empty() and not cells.is_empty():
		rebuild_lookup()
	return _cell_lookup.get(position) as MapCellVisualData


func is_in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < width and position.y >= 0 and position.y < depth

