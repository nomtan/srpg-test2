class_name VoxelMap
extends Node3D

var grid: GridSystem

var terrain_colors := {
	"grass": Color("#5d9b45"),
	"dirt": Color("#8c6239"),
	"stone": Color("#747b86"),
	"rock": Color("#3d4249"),
}


func build_from_grid(source_grid: GridSystem) -> void:
	grid = source_grid
	for child in get_children():
		child.queue_free()

	for grid_pos: Vector2i in grid.cells:
		var cell := grid.get_cell(grid_pos)
		for level in cell.height:
			_create_block(grid_pos, level, cell)


func _create_block(grid_pos: Vector2i, level: int, cell: GridCell) -> void:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 0.96
	mesh_instance.mesh = cube
	mesh_instance.position = Vector3(grid_pos.x + 0.5, level + 0.5, grid_pos.y + 0.5)

	var material := StandardMaterial3D.new()
	var color: Color = terrain_colors.get(cell.terrain, Color.WHITE)
	material.albedo_color = color.darkened(float(cell.height - level - 1) * 0.08)
	material.roughness = 0.9
	mesh_instance.material_override = material
	add_child(mesh_instance)
