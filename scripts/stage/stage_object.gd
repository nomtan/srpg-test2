class_name StageObject
extends Node3D

enum ObjectType { CHEST, LEVER, DOOR, OBSTACLE }
var object_id: String
var object_type: ObjectType
var grid_pos: Vector2i
var activated := false


func configure(id: String, type: ObjectType, position_on_grid: Vector2i, grid: GridSystem, model_path: String = "", model_scale: float = 1.0) -> void:
	object_id = id
	object_type = type
	grid_pos = position_on_grid
	name = id
	position = grid.grid_to_world(grid_pos, 0.05)
	if not model_path.is_empty():
		var packed: PackedScene = load(model_path)
		var model_instance: Node3D = packed.instantiate()
		model_instance.scale = Vector3.ONE * model_scale
		add_child(model_instance)
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5 if type != ObjectType.DOOR else 1.5, 0.5)
	mesh.mesh = box
	mesh.position.y = box.size.y * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = [Color("#d6a43a"), Color("#9d67d5"), Color("#70513b"), Color("#3a6b2f")][int(type)]
	mesh.material_override = material
	add_child(mesh)


func activate() -> void:
	activated = true
	visible = false
