@tool
extends RefCounted
## Shared, seeded botanical meshes. One MultiMesh per variant and terrain chunk.
const SHADER = preload("res://scripts/world_jrpg/natural_vegetation.gdshader")
const GRASS_SHADER = preload("res://scripts/world_jrpg/natural_grass.gdshader")
const TREE_DISTANCES := [0.0, 45.0, 110.0, 0.0]
const GRASS_DISTANCES := [0.0, 30.0, 55.0]
static var meshes: Dictionary = {}
static var material: ShaderMaterial
static var grass_material: ShaderMaterial
var groups: Dictionary = {}

static func field_conditions(wet: float, snow: float) -> void:
	_get_material().set_shader_parameter("wetness", wet)
	_get_material().set_shader_parameter("snow_cover", snow)
	_get_grass_material().set_shader_parameter("wetness", wet)
	_get_grass_material().set_shader_parameter("snow_cover", snow)

static func tactical_cutaway(center: Vector3, radius: float) -> void:
	_get_material().set_shader_parameter("tactical_center", center)
	_get_material().set_shader_parameter("tactical_radius", radius)

static func _get_material() -> ShaderMaterial:
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
	return material

static func _get_grass_material() -> ShaderMaterial:
	if grass_material == null:
		grass_material = ShaderMaterial.new()
		grass_material.shader = GRASS_SHADER
	return grass_material

func plant(kind: String, position: Vector3, size: float, angle: float, variant: int) -> void:
	var key := "%s_%d" % [kind, posmod(variant, 3)]
	if not meshes.has(key):
		meshes[key] = _build(kind, posmod(variant, 3))
	if not groups.has(key): groups[key] = []
	groups[key].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * size), position))

func commit(parent: Node3D) -> void:
	for key: String in groups:
		var kind := key.get_slice("_", 0)
		var variant := int(key.get_slice("_", 1))
		var is_grass := kind in ["grass", "reed"]
		var transforms: Array = groups[key]
		var level_keys: Array[String] = []
		var local_bounds: AABB = meshes[key].get_aabb()
		for lod in (2 if is_grass else 3):
			var lod_key := key if lod == 0 else key + "_lod%d" % lod
			if not meshes.has(lod_key): meshes[lod_key] = _build(kind, variant, lod)
			level_keys.append(lod_key)
			local_bounds = local_bounds.merge(meshes[lod_key].get_aabb())
		# All levels must use the same bounds: reduced grass density must not
		# move the AABB center used by Godot's visibility distance checks.
		var bounds: AABB = transforms[0] * local_bounds
		for transform: Transform3D in transforms:
			bounds = bounds.merge(transform * local_bounds)
		bounds = bounds.grow(0.15)
		for lod in level_keys.size():
			_commit_level(parent, level_keys[lod], transforms, bounds, lod, is_grass)
	groups.clear()

func _commit_level(parent: Node3D, key: String, transforms: Array, bounds: AABB, lod: int, is_grass: bool) -> void:
	var stride := 2 if is_grass and lod > 0 else 1
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = meshes[key]
	multi.instance_count = ceili(float(transforms.size()) / stride)
	multi.custom_aabb = bounds
	for i in multi.instance_count: multi.set_instance_transform(i, transforms[i * stride])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Natural_" + key
	instance.multimesh = multi
	var distances: Array = GRASS_DISTANCES if is_grass else TREE_DISTANCES
	instance.visibility_range_begin = distances[lod]
	instance.visibility_range_end = distances[lod + 1]
	# Hard range switches work in Compatibility without transparent passes.
	if is_grass or lod > 0:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

static func _build(kind: String, variant: int, lod: int = 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9241 + variant * 719 + (100 if kind == "pine" else 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind in ["grass", "reed"]:
		_grass(st, rng, kind == "reed", lod)
	else:
		_tree(st, rng, kind == "pine", variant, lod)
	st.set_material(_get_grass_material() if kind in ["grass", "reed"] else _get_material())
	return st.commit()

static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, color: Color, canopy: float) -> void:
	st.set_color(color)
	st.set_uv2(Vector2(canopy, 0))
	st.set_normal(normal)
	st.add_vertex(point)

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, canopy: float, normal: Vector3 = Vector3.ZERO) -> void:
	var n := normal if normal != Vector3.ZERO else (c - a).cross(b - a).normalized()
	_vertex(st, a, n, color, canopy)
	_vertex(st, b, n, color, canopy)
	_vertex(st, c, n, color, canopy)

static func _branch(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, rng: RandomNumberGenerator) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.1: side = Vector3.RIGHT
	var other := axis.cross(side).normalized()
	for i in 7:
		var u := side * cos(i * TAU / 7) + other * sin(i * TAU / 7)
		var v := side * cos((i + 1) * TAU / 7) + other * sin((i + 1) * TAU / 7)
		var color := Color("746047").lerp(Color("403b29"), rng.randf_range(0.0, 0.55))
		color.a = 0.0
		_triangle(st, a + u * r0, b + u * r1, b + v * r1, color, 0.0)
		_triangle(st, a + u * r0, b + v * r1, a + v * r0, color, 0.0)

static func _leaf(st: SurfaceTool, p: Vector3, direction: Vector3, width: float, color: Color, canopy: float) -> void:
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.1: side = Vector3.RIGHT
	var middle := p + direction * 0.48
	var ridge := middle + Vector3.UP * width * 0.24
	var left := middle - side * width
	var right := middle + side * width
	# Tilted soft normals keep small leaves readable from the grazing game camera.
	var n := (Vector3.UP + direction.normalized() * 0.45).normalized()
	_triangle(st, p, left, ridge, color, canopy, n)
	_triangle(st, left, p + direction, ridge, color, canopy, n)
	_triangle(st, p + direction, right, ridge, color, canopy, n)
	_triangle(st, right, p, ridge, color, canopy, n)

static func _tree(st: SurfaceTool, rng: RandomNumberGenerator, pine: bool, variant: int, lod: int = 0) -> void:
	var height := 5.8 if pine else 4.9
	var bend := Vector3(rng.randf_range(-0.32, 0.32), 0, rng.randf_range(-0.25, 0.25))
	var previous := Vector3.ZERO
	for i in 7:
		var t := float(i + 1) / 7.0
		var point := Vector3(0, height * t, 0) + bend * t * t
		_branch(st, previous, point, lerpf(0.24, 0.025, float(i) / 7.0), lerpf(0.24, 0.025, t), rng)
		previous = point
	for i in 5:
		var angle := i * TAU / 5.0 + rng.randf() * 0.4
		_branch(st, Vector3(0, 0.34, 0), Vector3(cos(angle) * 0.55, 0.015, sin(angle) * 0.55), 0.13, 0.025, rng)
	if pine:
		for tier in 9:
			var y := 1.65 + tier * 0.48
			var radius := 1.8 * (1.0 - float(tier) / 9.0)
			for arm in 7:
				var angle := arm * TAU / 7.0 + tier * 1.9 + rng.randf_range(-0.2, 0.2)
				var start := Vector3(0, y + rng.randf_range(-0.14, 0.14), 0) + bend * (y / height)
				var radial := Vector3(cos(angle), 0, sin(angle))
				var end := start + radial * radius * rng.randf_range(0.85, 1.15) + Vector3(0, rng.randf_range(-0.12, 0.28), 0)
				_branch(st, start, end, 0.055 * (1.0 - tier * 0.09), 0.009, rng)
				if lod == 2:
					_crown(st, start.lerp(end, 0.6), Vector3(radius * 0.6, 0.3, radius * 0.6), Color("416a4f"))
					continue
				for twig in 9:
					var t := float(twig + 1) / 10.0
					var p := start.lerp(end, t) + Vector3(0, rng.randf_range(-0.19, 0.24), 0)
					var lateral := Vector3(-radial.z, 0, radial.x)
					for sign_value: int in [-1, 1]:
						var spray := (radial * 0.3 + lateral * sign_value * 0.8).normalized() * radius * (1.0 - t * 0.68) * 0.5
						for needle in 4:
							var root := p + spray * (float(needle) / 4.0)
							var direction := (spray.normalized() + radial * rng.randf_range(-0.6, 0.8) + Vector3.UP * rng.randf_range(-0.4, 1.2)).normalized()
							var color := Color("285348").lerp(Color("63845b"), rng.randf() * 0.85)
							color.a = 0.6
							var length := rng.randf_range(0.28, 0.48)
							if lod == 0 or needle == 0:
								_leaf(st, root, direction * length, 0.04 if lod == 0 else 0.10, color, 1.0)
	else:
		var dark := Color("31562b") if variant != 1 else Color("4c6329")
		var light := Color("759943") if variant != 1 else Color("98a54c")
		for arm in 13:
			var angle := arm * 2.399 + rng.randf_range(-0.25, 0.25)
			var tier := float(arm) / 12.0
			var start := Vector3(0, 1.65 + tier * 2.3, 0) + bend * tier
			var end := Vector3(cos(angle) * (1.6 - tier * 0.65), 3.0 + tier * 1.85, sin(angle) * (1.5 - tier * 0.6)) + bend
			var fork := start.lerp(end, 0.55) - Vector3(0, 0.18, 0)
			_branch(st, start, fork, 0.105 * (1.0 - tier * 0.5), 0.05, rng)
			_branch(st, fork, end, 0.05, 0.015, rng)
			if lod == 2:
				_crown(st, end, Vector3(0.95, 0.75, 0.95), dark.lerp(light, 0.5))
				continue
			for cluster in 6:
				var center := end + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.25, 0.6), rng.randf_range(-0.6, 0.6))
				_branch(st, end, center, 0.014, 0.004, rng)
				for leaf in 19:
					var offset := Vector3(rng.randf_range(-0.58, 0.58), rng.randf_range(-0.38, 0.38), rng.randf_range(-0.58, 0.58))
					var direction := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.45, 0.7), rng.randf_range(-1, 1)).normalized()
					var color := dark.lerp(light, rng.randf_range(0.05, 0.95))
					color.a = 0.8
					var length := rng.randf_range(0.19, 0.35)
					var width := rng.randf_range(0.06, 0.10)
					if lod == 0 or leaf % 4 == 0:
						_leaf(st, center + offset, direction * length * (1.0 if lod == 0 else 1.5), width * (1.0 if lod == 0 else 1.8), color, 1.0)

static func _crown(st: SurfaceTool, center: Vector3, radius: Vector3, color: Color) -> void:
	# Opaque low-poly foliage avoids alpha overdraw and retains weather/cutaway.
	color.a = 0.6
	for side in 8:
		var a := Vector3(cos(side * TAU / 8), 0, sin(side * TAU / 8)) * radius
		var b := Vector3(cos((side + 1) * TAU / 8), 0, sin((side + 1) * TAU / 8)) * radius
		# Match the upward soft normals of individual leaves so distant crowns
		# do not become dark solid silhouettes when the LOD changes.
		var normal := (Vector3.UP + (a + b).normalized() * 0.35).normalized()
		_triangle(st, center + b, center + Vector3.UP * radius.y, center + a, color, 1.0, normal)
		_triangle(st, center + a, center - Vector3.UP * radius.y, center + b, color, 1.0, normal)

static func _grass(st: SurfaceTool, rng: RandomNumberGenerator, reed: bool, lod: int = 0) -> void:
	for blade in ((15 if reed else 19) if lod == 0 else 6):
		var angle := rng.randf() * TAU
		var radial := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-radial.z, 0, radial.x)
		var base := radial * rng.randf_range(0.015, 0.21)
		var height := rng.randf_range(0.35, 0.80) if reed else rng.randf_range(0.19, 0.52)
		var lean := rng.randf_range(0.16, 0.36)
		var width := rng.randf_range(0.017, 0.030) if reed else rng.randf_range(0.022, 0.040)
		var shade := rng.randf()
		var root_color := Color("344b25").lerp(Color("53652d"), shade)
		var tip_color := Color("739449").lerp(Color("a8b65b"), shade)
		for segment in 3:
			var t0 := float(segment) / 3.0
			var t1 := float(segment + 1) / 3.0
			var a := base + Vector3.UP * height * t0 + radial * lean * t0 * t0
			var b := base + Vector3.UP * height * t1 + radial * lean * t1 * t1
			var c0 := root_color.lerp(tip_color, t0)
			var c1 := root_color.lerp(tip_color, t1)
			c0.a = t0 * t0
			c1.a = t1 * t1
			var n := (Vector3.UP * 0.65 + radial * 0.35).normalized()
			_vertex(st, a - side * width * (1.0 - t0), n, c0, 0.0)
			_vertex(st, b - side * width * (1.0 - t1), n, c1, 0.0)
			_vertex(st, a + side * width * (1.0 - t0), n, c0, 0.0)
			if segment < 2:
				_vertex(st, a + side * width * (1.0 - t0), n, c0, 0.0)
				_vertex(st, b - side * width * (1.0 - t1), n, c1, 0.0)
				_vertex(st, b + side * width * (1.0 - t1), n, c1, 0.0)
