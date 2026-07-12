class_name TreeLeafCanopy
extends Node3D

@export var leaf_scene: PackedScene


func _ready() -> void:
	if not leaf_scene:
		push_warning("TreeLeafCanopy requires a leaf_scene")
		return
	for leaf_position: Vector3 in _canopy_positions():
		var leaf := leaf_scene.instantiate() as Node3D
		if not leaf:
			continue
		leaf.position = leaf_position
		add_child(leaf)


func _canopy_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	# Broad lower crown around the highest trunk block. Corners are removed so
	# the silhouette reads as organic instead of a solid 5x5 square.
	for z in range(-2, 3):
		for x in range(-2, 3):
			if absi(x) == 2 and absi(z) == 2:
				continue
			if x == 0 and z == 0:
				continue # The sixth log already occupies this volume.
			positions.append(Vector3(x, 5, z))
	# Dense 3x3 middle crown directly above the trunk.
	for z in range(-1, 2):
		for x in range(-1, 2):
			positions.append(Vector3(x, 6, z))
	# Small stepped cap: center plus four cardinal leaf blocks.
	for offset: Vector2i in [
		Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
	]:
		positions.append(Vector3(offset.x, 7, offset.y))
	return positions
