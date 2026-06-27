class_name BattleUnit
extends Node3D

var unit_name := "Vain"
var grid_x := 1
var grid_z := 1
var move_range := 4
var jump_height := 1
var team := "player"

var body_material: StandardMaterial3D


func setup_visual() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 0.9
	body.mesh = capsule
	body.position.y = 0.45
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color("#4ba3ff")
	body_material.metallic = 0.15
	body.material_override = body_material
	add_child(body)

	var marker := MeshInstance3D.new()
	var cone := PrismMesh.new()
	cone.size = Vector3(0.22, 0.25, 0.22)
	marker.mesh = cone
	marker.position = Vector3(0, 1.05, -0.05)
	marker.material_override = body_material
	add_child(marker)


func set_selected(selected: bool) -> void:
	if body_material:
		body_material.emission_enabled = selected
		body_material.emission = Color("#66d9ff")
		body_material.emission_energy_multiplier = 0.7


func snap_to_grid(grid: GridSystem) -> void:
	position = grid.grid_to_world(Vector2i(grid_x, grid_z), 0.05)
