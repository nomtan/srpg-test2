class_name BattleUnit
extends Node3D

enum AttackType { MELEE, RANGED }
enum FacingDirection { NORTH, EAST, SOUTH, WEST }
enum EnemyType { AGGRESSIVE, DEFENSIVE, SNIPER, GUARD, BOSS }

var unit_id: String
var unit_name: String
var grid_x: int
var grid_z: int
var move_range: int = 4
var jump_height: int = 1
var team: String
var has_acted: bool = false
var has_moved: bool = false
var max_hp: int = 100
var hp: int = 100
var attack_power: int = 30
var defense: int = 5
var attack_type: AttackType = AttackType.MELEE
var accuracy: int = 90
var evasion: int = 10
var min_attack_range: int = 1
var max_attack_range: int = 1
var is_dead: bool = false
var facing: FacingDirection = FacingDirection.SOUTH
var enemy_type: EnemyType = EnemyType.AGGRESSIVE

var body_material: StandardMaterial3D
var base_color: Color
var direction_marker: MeshInstance3D


func configure(
	id: String,
	display_name: String,
	grid_pos: Vector2i,
	unit_team: String,
	movement: int = 4,
	jump: int = 1
) -> void:
	unit_id = id
	unit_name = display_name
	grid_x = grid_pos.x
	grid_z = grid_pos.y
	team = unit_team
	move_range = movement
	jump_height = jump
	name = unit_id


func setup_visual() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 0.9
	body.mesh = capsule
	body.position.y = 0.45
	body_material = StandardMaterial3D.new()
	if attack_type == AttackType.RANGED:
		base_color = Color("#65c8a0") if team == "player" else Color("#d47a42")
	else:
		base_color = Color("#4ba3ff") if team == "player" else Color("#dc4c4c")
	body_material.albedo_color = base_color
	body_material.metallic = 0.15
	body.material_override = body_material
	add_child(body)

	var marker := MeshInstance3D.new()
	direction_marker = marker
	var cone := PrismMesh.new()
	cone.size = Vector3(0.22, 0.25, 0.22)
	marker.mesh = cone
	marker.position = Vector3(0, 1.05, -0.05)
	marker.material_override = body_material
	add_child(marker)
	update_visual_state()
	update_facing_visual()


func face_toward(target_pos: Vector2i) -> void:
	var delta := target_pos - Vector2i(grid_x, grid_z)
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		facing = FacingDirection.EAST if delta.x > 0 else FacingDirection.WEST
	elif delta.y != 0:
		facing = FacingDirection.SOUTH if delta.y > 0 else FacingDirection.NORTH
	update_facing_visual()


func set_facing(direction: FacingDirection) -> void:
	facing = direction
	update_facing_visual()


func update_facing_visual() -> void:
	if not direction_marker: return
	var offsets := [Vector3(0, 1.05, -0.28), Vector3(0.28, 1.05, 0), Vector3(0, 1.05, 0.28), Vector3(-0.28, 1.05, 0)]
	direction_marker.position = offsets[int(facing)]


func set_selected(selected: bool) -> void:
	if body_material:
		body_material.emission_enabled = selected
		body_material.emission = Color("#66d9ff") if team == "player" else Color("#ff7777")
		body_material.emission_energy_multiplier = 0.7


func mark_acted(moved: bool = true) -> void:
	has_moved = moved
	has_acted = true
	update_visual_state()


func set_combat_stats(
	new_max_hp: int, power: int, armor: int, hit: int, dodge: int,
	type: AttackType = AttackType.MELEE, min_range: int = 1, max_range: int = 1
) -> void:
	max_hp = new_max_hp
	hp = max_hp
	attack_power = power
	defense = armor
	accuracy = hit
	evasion = dodge
	attack_type = type
	min_attack_range = min_range
	max_attack_range = max_range


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		die()
	update_visual_state()


func die() -> void:
	is_dead = true
	visible = false


func is_alive() -> bool:
	return not is_dead and hp > 0


func get_status_name() -> String:
	if is_dead: return "Defeated"
	return "Acted" if has_acted else "Ready"


func reset_action_state() -> void:
	has_acted = false
	has_moved = false
	update_visual_state()


func update_visual_state() -> void:
	if not body_material:
		return
	visible = not is_dead
	body_material.albedo_color = base_color.darkened(0.55) if has_acted else base_color


func snap_to_grid(grid: GridSystem) -> void:
	position = grid.grid_to_world(Vector2i(grid_x, grid_z), 0.05)
