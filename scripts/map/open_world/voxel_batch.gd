extends RefCounted
## Cuboids grouped by material, with one MultiMesh per color per chunk.

var groups: Dictionary = {}
var palette: Dictionary

func _init() -> void:
	palette = JSON.parse_string(FileAccess.get_file_as_string("res://assets/open_world/palette.json"))

func box(center: Vector3, size: Vector3, color: String) -> void:
	if not groups.has(color):
		groups[color] = []
	groups[color].append(Transform3D(Basis.from_scale(size), center))

func commit(parent: Node3D) -> void:
	for color: String in groups:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(palette[color])
		material.roughness = 1.0
		var cube := BoxMesh.new()
		cube.material = material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cube
		multi.instance_count = groups[color].size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, groups[color][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = color
		instance.multimesh = multi
		parent.add_child(instance)
	groups.clear()
