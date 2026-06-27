class_name StageObject
extends Node3D

enum ObjectType { CHEST, LEVER, DOOR }
var object_id: String
var object_type: ObjectType
var grid_pos: Vector2i
var activated := false


func configure(id: String, type: ObjectType, position_on_grid: Vector2i, grid: GridSystem) -> void:
	object_id = id
	object_type = type
	grid_pos = position_on_grid
	name = id
	position = grid.grid_to_world(grid_pos, 0.05)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5 if type != ObjectType.DOOR else 1.5, 0.5)
	mesh.mesh = box
	mesh.position.y = box.size.y * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color("#d6a43a"), Color("#9d67d5"), Color("#70513b")][int(type)]
	mesh.material_override = material
	add_child(mesh)


func activate() -> void:
	activated = true
	visible = false
