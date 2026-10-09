extends RefCounted
## Low-poly, anime-style JRPG trees for JRPGWorldSample2, built procedurally (no GLB).
## Broadleaf crowns are a few puffy icosphere "bubbles" with sphere normals, so the cel
## shader (open_field_toon_tree.gdshader) paints each one as a round, sunlit ball;
## conifers are stacked, jagged cones. Everything is opaque and static (no wind), and the
## LOD meshes drop from ~500 to ~50 triangles.
## Vertex COLOR: rgb = painted sRGB color, a = 1 foliage / 0 bark.
const TRUNK_DARK := Color("6b4a33")
const TRUNK_LIGHT := Color("9a7150")
## Per species: [crown bottom (shade side), crown top (sunlit side)].
const PALETTES := {
	"leaf": [Color("3a7a47"), Color("8cc061")],
	"oak": [Color("30663e"), Color("7cb058")],
	"needle": [Color("23584a"), Color("5f9e5c")],
	"blossom": [Color("d67fa6"), Color("ffd3e2")],
}

## LOD meshes of a toon tree asset, finest first, all using `material`.
static func build(asset: String, material: Material) -> Array[Mesh]:
	var list: Array[Mesh] = []
	for lod in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(asset)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_shape(st, rng, asset, lod)
		# Puffs share their smooth vertices; indexing welds them for the vertex cache.
		st.index()
		st.set_material(material)
		var mesh := st.commit()
		mesh.resource_name = "%s_LOD%d" % [asset, lod]
		list.append(mesh)
	return list

static func _shape(st: SurfaceTool, rng: RandomNumberGenerator, asset: String, lod: int) -> void:
	match asset:
		"toon_round":
			_trunk(st, Vector3.ZERO, Vector3(0, 3.4, 0), 0.34, 0.2, lod)
			_crown(st, rng, lod, "leaf", [[Vector3(0, 4.3, 0), 2.1], [Vector3(0, 5.7, 0), 1.45]], 5, 1.75, 3.9, 1.3)
		"toon_tall":
			_trunk(st, Vector3.ZERO, Vector3(0, 3.6, 0), 0.3, 0.17, lod)
			_crown(st, rng, lod, "leaf", [[Vector3(0, 3.8, 0), 1.6], [Vector3(0, 5.2, 0), 1.5], [Vector3(0, 6.5, 0), 1.1]], 3, 1.25, 4.4, 1.2)
		"toon_lean":
			var top := Vector3(1.2, 3.8, 0.4)
			_trunk(st, Vector3.ZERO, top, 0.30, 0.16, lod, Vector3(0.5, 0, 0.1))
			_crown(st, rng, lod, "leaf", [[top + Vector3(0, 0.7, 0), 1.95], [top + Vector3(0.5, 2.0, 0.2), 1.3]], 4, 1.55, top.y + 0.4, 1.2)
		"toon_oak":
			_trunk(st, Vector3.ZERO, Vector3(0, 3.0, 0), 0.52, 0.3, lod)
			_crown(st, rng, lod, "oak", [[Vector3(0, 4.2, 0), 2.4], [Vector3(0, 5.6, 0), 1.65]], 6, 2.5, 3.7, 1.5)
		"toon_umbrella":
			_trunk(st, Vector3.ZERO, Vector3(0, 3.8, 0), 0.42, 0.24, lod)
			_crown(st, rng, lod, "oak", [[Vector3(0, 5.2, 0), 2.3]], 7, 2.7, 4.9, 1.35, 0.62)
		"toon_spruce":
			_trunk(st, Vector3.ZERO, Vector3(0, 2.0, 0), 0.3, 0.2, lod)
			_cones(st, rng, lod, [[1.4, 2.9, 2.3], [3.1, 2.6, 1.8], [4.7, 2.4, 1.3], [6.2, 2.4, 0.85]])
		"toon_fir":
			_trunk(st, Vector3.ZERO, Vector3(0, 1.8, 0), 0.34, 0.22, lod)
			_cones(st, rng, lod, [[1.2, 2.6, 2.9], [2.9, 2.4, 2.3], [4.5, 2.2, 1.7], [6.0, 2.3, 1.05]])
		"toon_blossom":
			_trunk(st, Vector3.ZERO, Vector3(0, 3.0, 0), 0.34, 0.2, lod, Vector3(-0.3, 0, 0.2))
			_crown(st, rng, lod, "blossom", [[Vector3(-0.2, 3.8, 0.1), 2.0], [Vector3(-0.1, 5.0, 0.1), 1.35]], 5, 1.75, 3.5, 1.25)
		_:
			assert(false, "Unknown toon tree '%s'" % asset)

static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, color: Color) -> void:
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(point)

## A tapered bark column from `a` to `b`, curving through `bend` at mid height.
static func _trunk(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, lod: int, bend := Vector3.ZERO) -> void:
	var sides: int = [7, 5, 4][lod]
	var segments := 2 if bend != Vector3.ZERO and lod < 2 else 1
	a.y = -0.35
	for s in segments:
		var t0 := float(s) / segments
		var t1 := float(s + 1) / segments
		var p0 := a.lerp(b, t0) + bend * sin(t0 * PI)
		var p1 := a.lerp(b, t1) + bend * sin(t1 * PI)
		var q0 := lerpf(r0, r1, t0)
		var q1 := lerpf(r0, r1, t1)
		var c0 := TRUNK_DARK.lerp(TRUNK_LIGHT, t0 * 0.7)
		var c1 := TRUNK_DARK.lerp(TRUNK_LIGHT, t1 * 0.7)
		c0.a = 0.0
		c1.a = 0.0
		for i in sides:
			var u := Vector3(cos(i * TAU / sides), 0, sin(i * TAU / sides))
			var v := Vector3(cos((i + 1) * TAU / sides), 0, sin((i + 1) * TAU / sides))
			_vertex(st, p0 + u * q0, u, c0)
			_vertex(st, p0 + v * q0, v, c0)
			_vertex(st, p1 + v * q1, v, c1)
			_vertex(st, p0 + u * q0, u, c0)
			_vertex(st, p1 + v * q1, v, c1)
			_vertex(st, p1 + u * q1, u, c1)

## A puffy crown: `cores` ([center, radius] pairs) plus a ring of `ring` smaller puffs of
## radius `puff` at `ring_radius` from the axis around height `ring_y`. `squash` flattens
## every puff vertically (umbrella crowns). LOD1 drops the subdivision, LOD2 merges the
## crown into one or two coarse bubbles.
static func _crown(st: SurfaceTool, rng: RandomNumberGenerator, lod: int, palette: String, cores: Array, ring: int, ring_radius: float, ring_y: float, puff: float, squash := 0.85) -> void:
	var colors: Array = PALETTES[palette]
	var puffs: Array = []
	for core: Array in cores: puffs.append([core[0], core[1] as float])
	var start := rng.randf() * TAU
	for i in ring:
		var angle := start + i * TAU / ring + rng.randf_range(-0.25, 0.25)
		var center := Vector3(cos(angle) * ring_radius, ring_y + rng.randf_range(-0.3, 0.4), sin(angle) * ring_radius)
		puffs.append([center, puff * rng.randf_range(0.85, 1.1)])
	if lod == 2:
		# One bubble enclosing the whole crown (two for tall stacks).
		var bounds := AABB((puffs[0][0] as Vector3), Vector3.ZERO)
		for p: Array in puffs: bounds = bounds.merge(AABB((p[0] as Vector3) - Vector3.ONE * (p[1] as float) * 0.8, Vector3.ONE * (p[1] as float) * 1.6))
		var size := bounds.size * 0.5
		if size.y > size.x * 1.4:
			var half := Vector3(size.x, size.y * 0.55, size.z)
			_bubble(st, bounds.get_center() - Vector3(0, size.y * 0.45, 0), half, 0, colors, 0.0)
			_bubble(st, bounds.get_center() + Vector3(0, size.y * 0.45, 0), half * Vector3(0.75, 1, 0.75), 0, colors, 0.0)
		else:
			_bubble(st, bounds.get_center(), size, 0, colors, 0.0)
		return
	for p: Array in puffs:
		var r: float = p[1]
		_bubble(st, p[0], Vector3(r, r * squash, r), 1 if lod == 0 else 0, colors, rng.randf())

## An icosphere ellipsoid with ellipsoid normals; the color runs from the palette's shade
## tone underneath to its sunlit tone on top, so each puff reads as a painted ball.
static func _bubble(st: SurfaceTool, center: Vector3, radius: Vector3, subdivisions: int, colors: Array, seed_value: float) -> void:
	var sphere := _icosphere(subdivisions)
	var points: PackedVector3Array = sphere[0]
	var faces: PackedInt32Array = sphere[1]
	var shade: Color = colors[0]
	var lit: Color = colors[1]
	for i in range(0, faces.size(), 3):
		for k in [0, 2, 1]:
			var n: Vector3 = points[faces[i + k]]
			# A small, seeded lumpiness so neighbouring puffs never look stamped.
			var lump := 1.0 + 0.07 * sin(n.x * 5.0 + seed_value * 13.0) * cos(n.z * 4.0 + n.y * 3.0)
			var p := center + n * radius * lump
			var normal := (n / radius).normalized()
			var color := shade.lerp(lit, smoothstep(-0.7, 0.9, n.y))
			color.a = 1.0
			_vertex(st, p, normal, color)

## Stacked conifer tiers: each [base y, height, radius] is a jagged cone whose skirt
## droops between points, with a shallow dark underside.
static func _cones(st: SurfaceTool, rng: RandomNumberGenerator, lod: int, tiers: Array) -> void:
	var colors: Array = PALETTES["needle"]
	var sides: int = [10, 7, 5][lod]
	if lod == 2: tiers = [[tiers[0][0], (tiers[-1][0] as float) + (tiers[-1][1] as float) - (tiers[0][0] as float), tiers[0][2]]]
	for index in tiers.size():
		var tier: Array = tiers[index]
		var y: float = tier[0]
		var h: float = tier[1]
		var r: float = tier[2]
		var apex := Vector3(0, y + h, 0)
		var twist := rng.randf() * TAU
		var slope := atan2(r, h)
		var tip_color: Color = colors[1].lerp(colors[0], 0.15)
		tip_color.a = 1.0
		var rim_color: Color = colors[0].lerp(colors[1], 0.35 + 0.1 * index)
		rim_color.a = 1.0
		var under: Color = colors[0].darkened(0.25)
		under.a = 1.0
		var ring: Array[Vector3] = []
		var normals: Array[Vector3] = []
		for i in sides * 2:
			# Points (even) stick out and droop; notches (odd) tuck in and lift.
			var angle := twist + i * TAU / (sides * 2)
			var radial := Vector3(cos(angle), 0, sin(angle))
			var point := i % 2 == 0
			ring.append(radial * r * (1.0 if point else 0.78) + Vector3(0, y - (0.25 if point else 0.0), 0))
			normals.append((radial * cos(slope) + Vector3.UP * sin(slope)).normalized())
		var count := ring.size()
		for i in count:
			var j := (i + 1) % count
			var mid := (normals[i] + normals[j]).normalized()
			_vertex(st, ring[i], normals[i], rim_color)
			_vertex(st, ring[j], normals[j], rim_color)
			_vertex(st, apex, (mid + Vector3.UP * 0.6).normalized(), tip_color)
			var hub := Vector3(0, y + h * 0.18, 0)
			_vertex(st, ring[i], Vector3.DOWN, under)
			_vertex(st, hub, Vector3.DOWN, under)
			_vertex(st, ring[j], Vector3.DOWN, under)

static var _spheres: Dictionary = {}

## Unit icosphere [points, triangle indices]; 0 = 20 faces, 1 = 80 faces.
static func _icosphere(subdivisions: int) -> Array:
	if _spheres.has(subdivisions): return _spheres[subdivisions]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var points := PackedVector3Array()
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		points.append(v.normalized())
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for level in subdivisions:
		var midpoints := {}
		var next := PackedInt32Array()
		for i in range(0, faces.size(), 3):
			var m: Array[int] = []
			for e in 3:
				var a := faces[i + e]
				var b := faces[i + (e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not midpoints.has(key):
					midpoints[key] = points.size()
					points.append(((points[a] + points[b]) * 0.5).normalized())
				m.append(midpoints[key])
			next.append_array([faces[i], m[0], m[2], faces[i + 1], m[1], m[0], faces[i + 2], m[2], m[1], m[0], m[1], m[2]])
		faces = next
	_spheres[subdivisions] = [points, faces]
	return _spheres[subdivisions]
