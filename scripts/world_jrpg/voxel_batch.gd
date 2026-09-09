extends RefCounted
## Cuboids grouped by material, with one MultiMesh per color per chunk.

var groups: Dictionary = {}
var palette: Dictionary
const SURFACE = preload("res://scripts/world_jrpg/surface.gdshader")
const WATER_SHADER = preload("res://scripts/world_jrpg/water.gdshader")
static var meshes: Dictionary = {}

static func field_conditions(wet: float, snow: float, night: float) -> void:
	for mesh: BoxMesh in meshes.values():
		if mesh.material.shader == SURFACE:
			mesh.material.set_shader_parameter("wetness", wet)
			mesh.material.set_shader_parameter("snow_cover", snow)
			mesh.material.set_shader_parameter("night_light", night)

static func tactical_cutaway(center: Vector3, radius: float) -> void:
	for mesh: BoxMesh in meshes.values():
		if mesh.material.shader == SURFACE:
			mesh.material.set_shader_parameter("tactical_center", center)
			mesh.material.set_shader_parameter("tactical_radius", radius)

func _init() -> void:
	palette = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world_jrpg/palette.json"))

func box(center: Vector3, size: Vector3, color: String) -> void:
	if not groups.has(color):
		groups[color] = []
	groups[color].append(Transform3D(Basis.from_scale(size), center))

func commit(parent: Node3D) -> void:
	for color: String in groups:
		var key := color + str(palette[color])
		if not meshes.has(key):
			var material := ShaderMaterial.new()
			material.shader = WATER_SHADER if color in ["water", "sea"] else SURFACE
			material.set_shader_parameter("base_color", Color(palette[color]))
			if color not in ["water", "sea"]:
				material.set_shader_parameter("lamp", color in ["window", "gold"])
				var kind := 0
				if color in ["rock", "rock_light", "basalt"]: kind = 1
				elif color in ["wood", "trunk"]: kind = 2
				elif color in ["leaf", "leaf_light", "pine", "pine_light"]: kind = 3
				elif color in ["roof", "roof_light"]: kind = 4
				elif color in ["cliff", "cliff_light"]: kind = 5
				material.set_shader_parameter("kind", kind)
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE
			cube.material = material
			meshes[key] = cube
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = meshes[key]
		multi.instance_count = groups[color].size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, groups[color][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = color
		instance.multimesh = multi
		parent.add_child(instance)
	groups.clear()
