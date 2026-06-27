class_name ThreatArrowManager
extends Node3D

func show_threat_arrows(enemies: Array[BattleUnit], target: BattleUnit) -> void:
	clear_threat_arrows()
	for enemy in enemies: _create_arrow(enemy.global_position, target.global_position)

func clear_threat_arrows() -> void:
	for child in get_children(): child.queue_free()

func _create_arrow(from_pos: Vector3, to_pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	for index in 12:
		var t := float(index) / 11.0
		var point := from_pos.lerp(to_pos, t)
		point.y += 1.0 + sin(t * PI) * 1.5
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.11
		marker.mesh = sphere
		marker.position = point
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1, 0.08, 0.08, 0.9)
		material.emission_enabled = true
		material.emission = Color.RED
		marker.material_override = material
		root.add_child(marker)
