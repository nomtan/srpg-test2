class_name ThreatArrowManager
extends Node3D

const TRAVEL_SPEED := 0.35

var animated_orbs: Array[Dictionary] = []


func show_threat_arrows(enemies: Array[BattleUnit], target: BattleUnit) -> void:
	clear_threat_arrows()
	for enemy in enemies: _create_arrow(enemy.global_position, target.global_position)
	set_process(not animated_orbs.is_empty())

func clear_threat_arrows() -> void:
	animated_orbs.clear()
	set_process(false)
	for child in get_children(): child.queue_free()


func _process(delta: float) -> void:
	for orb_data in animated_orbs:
		var progress := fmod(float(orb_data.progress) + delta * TRAVEL_SPEED, 1.0)
		orb_data.progress = progress
		orb_data.orb.position = _get_arc_point(orb_data.from_pos, orb_data.to_pos, progress)

func _create_arrow(from_pos: Vector3, to_pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	for index in 12:
		var progress := float(index) / 12.0
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.075
		sphere.height = 0.15
		marker.mesh = sphere
		marker.position = _get_arc_point(from_pos, to_pos, progress)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1, 0.08, 0.08, 0.9)
		material.emission_enabled = true
		material.emission = Color.RED
		material.emission_energy_multiplier = 2.2
		marker.material_override = material
		root.add_child(marker)
		animated_orbs.append({
			"orb": marker,
			"from_pos": from_pos,
			"to_pos": to_pos,
			"progress": progress,
		})


func _get_arc_point(from_pos: Vector3, to_pos: Vector3, progress: float) -> Vector3:
	var point := from_pos.lerp(to_pos, progress)
	point.y += 1.0 + sin(progress * PI) * 1.5
	return point
