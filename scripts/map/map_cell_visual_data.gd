class_name MapCellVisualData
extends Resource

const MICRO_GRID_SIZE := 3
const MICRO_LEVEL_COUNT := 3
const MICRO_CELL_COUNT := MICRO_GRID_SIZE * MICRO_GRID_SIZE

@export var position := Vector2i.ZERO
@export var height := 1
@export var terrain := "grass"
@export var props: Array[MapDecorationData] = []
# Optional row-major 3x3 visual height profile. Empty keeps the legacy
# one-block renderer. Values 0/1/2 divide the cell's top logical level into
# lower, middle, and upper thirds without changing gameplay occupancy.
@export var micro_heights := PackedInt32Array()


func has_micro_height_profile() -> bool:
	return micro_heights.size() == MICRO_CELL_COUNT


func set_micro_height_profile(values: PackedInt32Array) -> void:
	if values.size() != MICRO_CELL_COUNT:
		push_error("A micro height profile must contain exactly 9 values")
		micro_heights = PackedInt32Array()
		return
	micro_heights = PackedInt32Array()
	micro_heights.resize(MICRO_CELL_COUNT)
	for index in MICRO_CELL_COUNT:
		micro_heights[index] = clampi(values[index], 0, MICRO_LEVEL_COUNT - 1)


func clear_micro_height_profile() -> void:
	micro_heights = PackedInt32Array()


func micro_height_at(x: int, z: int) -> int:
	if not has_micro_height_profile():
		return MICRO_LEVEL_COUNT - 1
	var safe_x := clampi(x, 0, MICRO_GRID_SIZE - 1)
	var safe_z := clampi(z, 0, MICRO_GRID_SIZE - 1)
	return clampi(
		micro_heights[safe_z * MICRO_GRID_SIZE + safe_x],
		0,
		MICRO_LEVEL_COUNT - 1
	)


func micro_surface_height(x: int, z: int) -> float:
	# `height` remains the upper walkable level. Stage 0/1/2 surfaces are
	# respectively 1/3, 2/3, and 3/3 above the base of that logical level.
	return (
		float(height - 1)
		+ float(micro_height_at(x, z) + 1) / float(MICRO_LEVEL_COUNT)
	)
