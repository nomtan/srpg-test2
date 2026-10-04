extends RefCounted
## Cuboids grouped by material, with one MultiMesh per color per chunk.
## Terrain faces known to be exposed are merged into a single vertex-colored mesh.

const Vegetation = preload("res://scripts/world_jrpg/natural_vegetation.gd")
var vegetation := Vegetation.new()
var groups: Dictionary = {}
var faces: Array = []
var palette: Dictionary
const SURFACE = preload("res://scripts/world_jrpg/surface.gdshader")
const WATER_SHADER = preload("res://scripts/world_jrpg/water.gdshader")
static var meshes: Dictionary = {}
static var face_material: ShaderMaterial

static func _surface_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for mesh: BoxMesh in meshes.values():
		if mesh.material.shader == SURFACE: materials.append(mesh.material)
	if face_material: materials.append(face_material)
	return materials

static func field_conditions(wet: float, snow: float, night: float) -> void:
	Vegetation.field_conditions(wet, snow)
	for material in _surface_materials():
		material.set_shader_parameter("wetness", wet)
		material.set_shader_parameter("snow_cover", snow)
		material.set_shader_parameter("night_light", night)

static func tactical_cutaway(center: Vector3, radius: float) -> void:
	Vegetation.tactical_cutaway(center, radius)
	for material in _surface_materials():
		material.set_shader_parameter("tactical_center", center)
		material.set_shader_parameter("tactical_radius", radius)

static func _kind(color: String) -> int:
	if color in ["rock", "rock_light", "basalt"]: return 1
	if color in ["wood", "trunk"]: return 2
	if color in ["leaf", "leaf_light", "pine", "pine_light"]: return 3
	if color in ["roof", "roof_light"]: return 4
	if color in ["cliff", "cliff_light"]: return 5
	return 0

func _init() -> void:
	palette = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world_jrpg/palette.json"))

func box(center: Vector3, size: Vector3, color: String) -> void:
	if not groups.has(color):
		groups[color] = []
	groups[color].append(Transform3D(Basis.from_scale(size), center))

## Axis-aligned rectangle facing `normal`, spanning `u` and `v` from `corner`.
## Only opaque surface colors are supported; they share one draw per batch.
func quad(corner: Vector3, u: Vector3, v: Vector3, normal: Vector3, color: String) -> void:
	# Godot treats clockwise triangles as front faces.
	if u.cross(v).dot(normal) > 0:
		var swap := u
		u = v
		v = swap
	faces.append_array([corner, corner + u, corner + u + v, corner, corner + u + v, corner + v, normal, color])

func commit(parent: Node3D) -> void:
	vegetation.commit(parent)
	if not faces.is_empty():
		_commit_faces(parent)
	for color: String in groups:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _cube(color)
		multi.instance_count = groups[color].size()
		for i in multi.instance_count:
			multi.set_instance_transform(i, groups[color][i])
		var instance := MultiMeshInstance3D.new()
		instance.name = color
		instance.multimesh = multi
		parent.add_child(instance)
	groups.clear()

func _commit_faces(parent: Node3D) -> void:
	# Each quad is stored as six vertices, its normal and its palette name.
	var count := faces.size() / 8
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var kinds := PackedVector2Array()
	vertices.resize(count * 6)
	normals.resize(count * 6)
	colors.resize(count * 6)
	kinds.resize(count * 6)
	for q in count:
		var color_name: String = faces[q * 8 + 7]
		# Godot linearizes vertex colors, matching the source_color uniform path.
		var color := Color(palette[color_name])
		var kind := Vector2(_kind(color_name), 0)
		for i in 6:
			vertices[q * 6 + i] = faces[q * 8 + i]
			normals[q * 6 + i] = faces[q * 8 + 6]
			colors[q * 6 + i] = color
			kinds[q * 6 + i] = kind
	faces.clear()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = kinds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if face_material == null:
		face_material = ShaderMaterial.new()
		face_material.shader = SURFACE
		face_material.set_shader_parameter("vertex_palette", true)
	mesh.surface_set_material(0, face_material)
	var surface := MeshInstance3D.new()
	surface.name = "Faces"
	surface.mesh = mesh
	parent.add_child(surface)

func _cube(color: String) -> BoxMesh:
	var key := color + str(palette[color])
	if not meshes.has(key):
		var material := ShaderMaterial.new()
		material.shader = WATER_SHADER if color in ["water", "sea"] else SURFACE
		material.set_shader_parameter("base_color", Color(palette[color]))
		if color not in ["water", "sea"]:
			material.set_shader_parameter("lamp", color in ["window", "gold"])
			material.set_shader_parameter("kind", _kind(color))
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		cube.material = material
		meshes[key] = cube
	return meshes[key]
