extends RefCounted
## Stylized open-field meshes for JRPGWorldSample2: conifers, broadleaf trees,
## boulders, grass tufts and wildflowers. Low-poly enough to instance thousands.
const FOLIAGE_SHADER = preload("res://scripts/world_jrpg/open_field_foliage.gdshader")
const ROCK_SHADER = preload("res://scripts/world_jrpg/open_field_rock.gdshader")
static var meshes: Dictionary = {}
static var materials: Dictionary = {}

static func foliage_material() -> ShaderMaterial:
	if not materials.has("foliage"):
		var material := ShaderMaterial.new()
		material.shader = FOLIAGE_SHADER
		materials["foliage"] = material
	return materials["foliage"]

static func rock_material(stone: Color, moss := 0.7) -> ShaderMaterial:
	var key := "rock_%s_%.2f" % [stone.to_html(), moss]
	if not materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = ROCK_SHADER
		material.set_shader_parameter("stone", stone)
		material.set_shader_parameter("moss", moss)
		materials[key] = material
	return materials[key]

static func flat(color: Color, roughness := 0.9, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%s" % [color.to_html(), roughness, emission.to_html()]
	if not materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		if emission != Color.BLACK:
			material.emission_enabled = true
			material.emission = emission
		materials[key] = material
	return materials[key]

## Every ShaderMaterial built here, for weather (wetness/snow) updates.
static func shader_materials() -> Array[ShaderMaterial]:
	var list: Array[ShaderMaterial] = []
	for material in materials.values():
		if material is ShaderMaterial: list.append(material)
	return list

static func mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "%s_%d" % [kind, variant]
	if not meshes.has(key):
		var built: ArrayMesh
		match kind:
			"conifer": built = _conifer(variant)
			"broadleaf": built = _broadleaf(variant)
			"rock": built = _rock(variant)
			"grass": built = _grass(variant)
			"flower": built = _flower(variant)
		meshes[key] = built
	return meshes[key]

static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, color: Color, wind: float, own_color := true) -> void:
	st.set_color(color)
	st.set_uv(Vector2(wind, 1.0 if own_color else 0.0))
	st.set_normal(normal)
	st.add_vertex(point)

static func _trunk(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, color: Color, height: float) -> void:
	for i in 6:
		var u0 := Vector3(cos(i * TAU / 6.0), 0, sin(i * TAU / 6.0))
		var u1 := Vector3(cos((i + 1) * TAU / 6.0), 0, sin((i + 1) * TAU / 6.0))
		var shade := color.darkened(0.12 * float(i % 2))
		var wa := a.y / height * 0.5
		var wb := b.y / height * 0.5
		_vertex(st, a + u0 * r0, u0, shade, wa)
		_vertex(st, b + u0 * r1, u0, shade, wb)
		_vertex(st, b + u1 * r1, u1, shade, wb)
		_vertex(st, a + u0 * r0, u0, shade, wa)
		_vertex(st, b + u1 * r1, u1, shade, wb)
		_vertex(st, a + u1 * r0, u1, shade, wa)

## Painterly fir: stacked drooping star-shaped tiers, soft upward normals.
static func _conifer(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4100 + variant * 37
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 11.0 + variant * 1.3
	_trunk(st, Vector3.ZERO, Vector3(0, height * 0.5, 0), 0.4, 0.2, Color("5a4231"), height)
	var tiers := 6
	for t in tiers:
		var f := float(t) / float(tiers - 1)
		var base_y := lerpf(2.2, height * 0.8, f)
		var radius := lerpf(3.2, 0.9, f) * rng.randf_range(0.92, 1.08)
		var apex := Vector3(rng.randf_range(-0.1, 0.1), base_y + lerpf(3.3, 2.7, f), rng.randf_range(-0.1, 0.1))
		var under := Vector3(0, base_y + 0.7, 0)
		var segments := 11
		var offset := rng.randf() * TAU
		var ring: Array[Vector3] = []
		for i in segments:
			var angle := offset + i * TAU / segments
			var tip := i % 2 == 0
			var r := radius * (1.0 if tip else rng.randf_range(0.66, 0.8))
			var droop := (0.6 if tip else 0.1) * (1.0 - f * 0.4)
			ring.append(Vector3(cos(angle) * r, base_y - droop + rng.randf_range(-0.12, 0.12), sin(angle) * r))
		var light := Color("4f8657").lerp(Color("6a9c62"), rng.randf())
		var mid := Color("2f5f47").lerp(Color("3b6c4c"), rng.randf())
		var dark := Color("1f4236")
		for i in segments:
			var a := ring[i]
			var b := ring[(i + 1) % segments]
			var na := (Vector3(a.x, 0, a.z).normalized() * 0.75 + Vector3.UP * 0.65).normalized()
			var nb := (Vector3(b.x, 0, b.z).normalized() * 0.75 + Vector3.UP * 0.65).normalized()
			_vertex(st, apex, Vector3.UP, light, apex.y / height * 0.6)
			_vertex(st, b, nb, mid, b.y / height * 0.6)
			_vertex(st, a, na, mid, a.y / height * 0.6)
			_vertex(st, under, Vector3.DOWN, dark, under.y / height * 0.6)
			_vertex(st, a, -na, dark, a.y / height * 0.6)
			_vertex(st, b, -nb, dark, b.y / height * 0.6)
	return st.commit()

## Rounded broadleaf crown built from jittered blobs; variant 2 is a blossom tree.
static func _broadleaf(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + variant * 53
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 8.5
	var bend := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var bark := Color("6b4f37")
	_trunk(st, Vector3.ZERO, Vector3(0, 2.0, 0) + bend * 0.4, 0.45, 0.34, bark, height)
	_trunk(st, Vector3(0, 2.0, 0) + bend * 0.4, Vector3(0, 4.4, 0) + bend, 0.34, 0.2, bark, height)
	var palettes := [[Color("3d7a32"), Color("98cf55")], [Color("2f6a36"), Color("80bf5a")], [Color("b45f82"), Color("f6b6cb")]]
	var colors: Array = palettes[variant % palettes.size()]
	var crown := Vector3(0, 5.6, 0) + bend
	var clusters: Array = [[crown + Vector3(0, 0.5, 0), 2.6]]
	var count := 5
	for i in count:
		var angle := i * TAU / count + rng.randf_range(-0.3, 0.3)
		var center := crown + Vector3(cos(angle) * rng.randf_range(1.5, 2.0), rng.randf_range(-1.1, 0.8), sin(angle) * rng.randf_range(1.5, 2.0))
		clusters.append([center, rng.randf_range(1.5, 2.0)])
		_trunk(st, Vector3(0, 3.6, 0) + bend * 0.8, center.lerp(crown, 0.35), 0.16, 0.07, bark, height)
	for cluster: Array in clusters:
		_blob(st, rng, cluster[0], cluster[1], crown, colors[0], colors[1], height)
	return st.commit()

static func _blob(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, radius: float, crown: Vector3, dark: Color, light: Color, height: float) -> void:
	var rings := 5
	var segments := 8
	var grid: Array = []
	for ring in rings + 1:
		var phi := PI * float(ring) / rings
		var row: Array[Vector3] = []
		for s in segments:
			var theta := TAU * float(s) / segments + ring * 0.4
			var r := radius * (rng.randf_range(0.85, 1.1) if ring > 0 and ring < rings else 1.0)
			row.append(center + Vector3(sin(phi) * cos(theta) * r, cos(phi) * r * 0.85, sin(phi) * sin(theta) * r))
		grid.append(row)
	var tint := rng.randf_range(-0.06, 0.06)
	for ring in rings:
		for s in segments:
			var quad := [grid[ring][s], grid[ring][(s + 1) % segments], grid[ring + 1][(s + 1) % segments], grid[ring + 1][s]]
			for index in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = quad[index]
				var normal := ((p - center).normalized() * 0.6 + (p - crown).normalized() * 0.4).normalized()
				var color := dark.lerp(light, clampf(normal.y * 0.55 + 0.45 + tint, 0.0, 1.0))
				_vertex(st, p, normal, color, p.y / height * 0.55)

## Faceted boulder with a flattened base; origin at the base center.
static func _rock(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + variant * 91
	var rings := 6
	var segments := 9
	var grid: Array = []
	for ring in rings + 1:
		var phi := PI * float(ring) / rings
		var row: Array[Vector3] = []
		for s in segments:
			var theta := TAU * float(s) / segments + ring * 0.3
			var r := rng.randf_range(0.82, 1.16) if ring > 0 and ring < rings else 1.0
			var p := Vector3(sin(phi) * cos(theta) * r, cos(phi) * r * 0.78, sin(phi) * sin(theta) * r)
			p.y = maxf(p.y, -0.3)
			row.append(p + Vector3(0, 0.3, 0))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.4, 0)
	for ring in rings:
		for s in segments:
			var quad := [grid[ring][s], grid[ring][(s + 1) % segments], grid[ring + 1][(s + 1) % segments], grid[ring + 1][s]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = quad[tri[0]]
				var b: Vector3 = quad[tri[1]]
				var c: Vector3 = quad[tri[2]]
				var normal := (b - a).cross(c - a).normalized()
				if normal.dot((a + b + c) / 3.0 - center) < 0.0: normal = -normal
				if normal.is_zero_approx(): continue
				var ao := lerpf(0.55, 1.0, smoothstep(0.0, 0.8, (a.y + b.y + c.y) / 3.0))
				for p in [a, b, c]:
					st.set_color(Color(ao, ao, ao))
					st.set_normal(normal)
					st.add_vertex(p)
	return st.commit()

## Grass tuft; colored by the meadow tint in the shader, COLOR.r is root→tip shade.
static func _grass(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant * 17
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 16:
		_blade(st, rng, rng.randf_range(0.16, 0.42) * (1.35 if variant == 1 else 1.0))
	return st.commit()

static func _blade(st: SurfaceTool, rng: RandomNumberGenerator, height: float) -> Vector3:
	var angle := rng.randf() * TAU
	var radial := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-radial.z, 0, radial.x)
	var base := radial * rng.randf_range(0.0, 0.3)
	var width := rng.randf_range(0.035, 0.055)
	var tip := base + Vector3.UP * height + radial * height * rng.randf_range(0.15, 0.45)
	var shade := rng.randf_range(0.0, 0.15)
	_vertex(st, base - side * width, Vector3.UP, Color(shade, shade, shade), 0.0, false)
	_vertex(st, tip, Vector3.UP, Color(1, 1, 1), 0.45, false)
	_vertex(st, base + side * width, Vector3.UP, Color(shade, shade, shade), 0.0, false)
	return tip

## A small clump of wildflowers: meadow-tinted stems with colored heads.
static func _flower(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9900 + variant * 23
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palettes := [[Color("f4f1e6"), Color("f2d35b")], [Color("6f8fe0"), Color("b48ad8")]]
	var heads: Array = palettes[variant % palettes.size()]
	for stem in 6:
		var tip := _blade(st, rng, rng.randf_range(0.25, 0.42))
		var color: Color = heads[stem % 2]
		var s := rng.randf_range(0.07, 0.1)
		for corner in 4:
			var a := Vector3(cos(corner * TAU / 4.0), 0, sin(corner * TAU / 4.0)) * s
			var b := Vector3(cos((corner + 1) * TAU / 4.0), 0, sin((corner + 1) * TAU / 4.0)) * s
			_vertex(st, tip + Vector3(0, 0.04, 0), Vector3.UP, color.lightened(0.15), 0.45)
			_vertex(st, tip + a, Vector3.UP, color, 0.45)
			_vertex(st, tip + b, Vector3.UP, color, 0.45)
	return st.commit()
