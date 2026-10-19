extends "res://scripts/world_jrpg/open_field_world.gd"
## JRPGWorldSample3: 風翼の都 アウレリア, a walled castle city on an island in a lake.
## A long arched bridge crosses the lake to the twin-towered gate; inside, half-timbered
## streets with windmills climb in terraces past the knights' keep and a fountain plaza to
## the winged statue's plaza and the cathedral on the summit. JRPGWorldSample2's explorer,
## camera, HUD, weather, water and toon vegetation are reused; only the map is replaced.
const STONE_SHADER = preload("res://scripts/world_jrpg/castle_stone.gdshader")
## The lake basin (center, half extents); the island city stands in its middle.
const CITY_AT := Vector2(200, 180)
const LAKE_HALF := Vector2(165, 130)
## City wall, clockwise from the gate's west side; the gate sits in the middle of the first edge.
const WALL := [
	Vector2(178, 270), Vector2(222, 270), Vector2(254, 252), Vector2(270, 214), Vector2(272, 170),
	Vector2(258, 126), Vector2(230, 96), Vector2(200, 88), Vector2(170, 96), Vector2(142, 126),
	Vector2(128, 170), Vector2(130, 214), Vector2(146, 252),
]
## Wall walks stand this far above the highest street along each edge.
const WALL_RISE := 9.0
## The main street runs north from the gate along x = AXIS.
const AXIS := 200.0
const GATE_Z := 270.0
## Terraces are discs around APEX: the lower town (TIERS[0]), the knights' tier within R1
## and the summit within R2. Straight stairs climb each terrace face along the main street.
const APEX := Vector2(200, 100)
const TIERS := [16.0, 22.0, 29.0]
const R1 := 90.0
const R2 := 46.0
const STAIR_HALF := 4.5
const STAIR_RUN := 12.0
## The bridge deck (walkable half width) spans the lake from the gate to the south shore.
const DECK := 16.0
const BRIDGE_Z := Vector2(273, 316)
const BRIDGE_HALF := 3.4
const BRIDGE_PIERS := [281.0, 288.0, 295.0, 302.0, 309.0]
const STATUE_AT := Vector2(200, 128)
const FOUNTAIN_AT := Vector2(200, 168)
const CATHEDRAL_AT := Vector2(200, 103)
const KEEP_AT := Vector2(166, 162)
## Windmills: position, sail facing.
const MILLS := [[Vector2(152, 236), 0.9], [Vector2(250, 238), -0.9], [Vector2(244, 156), -1.2]]
## Windmill hub height and sail length; houses keep out of the sails' sweep.
const MILL_HUB := 22.0
const MILL_SAIL := 12.5
const PAVILIONS := [[Vector2(182, 124), PI / 2.0], [Vector2(218, 124), -PI / 2.0]]
const GATE_PLAZA := Rect2(184, 248, 32, 20)
const CROSS_Z := 232.0
## Garden trees inside the walls.
const CITY_TREES := [Vector2(186, 140), Vector2(214, 140), Vector2(186, 181), Vector2(214, 181), Vector2(226, 228), Vector2(174, 228)]
## Lanes running north between the house rows, as offsets from AXIS; the main street is wider.
const LANES := [-78.0, -52.0, -26.0, 0.0, 26.0, 52.0, 78.0]
const ROOFS := [Color("c65a32"), Color("d06c3a"), Color("b84e2e"), Color("d4804a"), Color("a9462c"), Color("c86238"), Color("4f8c78"), Color("5b6f86")]
const PLASTERS := [Color("f3e9d4"), Color("efe2c6"), Color("f7f1e4"), Color("eadcc0")]
const BUNTING := [Color("d24a3a"), Color("f0c04a"), Color("3f74b8"), Color("f4f1e8"), Color("5aa04a")]
## Dirt roads beyond the bridge: half width, control points.
const ROADS := [
	[2.2, [Vector2(200, 314), Vector2(200, 336), Vector2(198, 352), Vector2(186, 368), Vector2(160, 382), Vector2(130, 398)]],
	[1.8, [Vector2(198, 352), Vector2(222, 366), Vector2(256, 378), Vector2(300, 394)]],
	[1.4, [Vector2(200, 336), Vector2(170, 330), Vector2(130, 318), Vector2(80, 300), Vector2(50, 268)]],
	[1.4, [Vector2(200, 336), Vector2(236, 330), Vector2(280, 318), Vector2(330, 296), Vector2(356, 262)]],
]
const SPAWN := Vector2(200, 338)
## Distant ranges around the basin: position, height, radius.
const FAR_PEAKS := [
	[Vector2(220, -330), 150.0, 260.0], [Vector2(-260, 60), 115.0, 240.0], [Vector2(-180, -200), 130.0, 230.0],
	[Vector2(640, 120), 120.0, 250.0], [Vector2(520, -260), 160.0, 260.0], [Vector2(560, 560), 90.0, 240.0],
	[Vector2(-160, 520), 85.0, 240.0],
]
## Named viewpoints (from, look-at) for captures and the 1-5 keys; `from` heights are above
## the walkable surface.
const CITY_SHOTS := {
	"bridge": [Vector3(203, 1.8, 330), Vector3(197, 24, 268)],
	"gate": [Vector3(200, 1.7, 292), Vector3(200, 23, 268)],
	"overview": [Vector3(318, 62, 352), Vector3(200, 22, 178)],
	"street": [Vector3(201, 1.7, 258), Vector3(200, 24, 186)],
	"plaza": [Vector3(200, 1.7, 147), Vector3(200, 36, 120)],
	"statue": [Vector3(213, 6.0, 138), Vector3(200, 39, 126)],
	"cathedral": [Vector3(212, 1.7, 137), Vector3(200, 52, 104)],
	"keep": [Vector3(194, 1.7, 182), Vector3(166, 34, 162)],
	"lake": [Vector3(70, 3.0, 262), Vector3(200, 30, 170)],
}

## Static parts merged per material and CHUNK cell (see _part). Each part's arrays are
## queued and joined once in _flush_parts; growing one packed array per part copies it.
class PartBatch:
	var parts: Array = []
	var vertex_count := 0

var wall_polygon := PackedVector2Array(WALL)
var batching := false
var batches: Dictionary = {}
var shape_arrays: Dictionary = {}
var mat: Dictionary = {}
## Bush spots in the summit plaza's planters, planted with the trees.
var planter_bushes: Array[Vector2] = []

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	_cache_city()
	_build_city()
	_setup_view()
	field_weather.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	field_weather.sun.directional_shadow_max_distance = Vegetation.SHADOW_REACH
	# The city is shown under a clear midday sky (the time panel still changes it).
	field_weather.apply_conditions(1, 0)
	_setup_hud()
	_spawn_characters()
	_spawn_gate_guards()
	_focus_player()
	# Over the explorer's shoulder, up the bridge to the gate.
	yaw = 0.0
	pitch = 0.18
	distance = 14.0
	_update_camera()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--view=") and CITY_SHOTS.has(arg.get_slice("=", 1)): _city_shot(arg.get_slice("=", 1))
		if arg.begins_with("--spawn="):
			var at := arg.get_slice("=", 1).split_floats(",")
			player.position = Vector3(at[0], _surface(at[0], at[1]) + 0.05, at[1])
			_focus_player()
			_update_camera()
		if arg == "--hide-hud":
			hud.visible = false
			field_weather.controls.visible = false
		if arg.begins_with("--time="):
			field_weather.apply_conditions(maxi(0, ["morning", "day", "evening", "night"].find(arg.get_slice("=", 1))), field_weather.weather_index)
		if arg.begins_with("--weather="):
			field_weather.apply_conditions(field_weather.time_index, maxi(0, ["clear", "rain", "cloudy", "snow"].find(arg.get_slice("=", 1))))
		if arg.begins_with("--season="):
			field_weather.apply_conditions(field_weather.time_index, field_weather.weather_index, maxi(0, ["spring", "summer", "autumn", "winter"].find(arg.get_slice("=", 1))))
	if "--sample-capture" in args:
		mode = "capture"
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var capture_name := "spawn"
		var directory := "user://"
		for arg in args:
			if arg.begins_with("--view="): capture_name = arg.get_slice("=", 1)
			if arg.begins_with("--capture-dir="): directory = arg.get_slice("=", 1)
		for arg in args:
			if arg.begins_with("--time=") or arg.begins_with("--weather=") or arg.begins_with("--season="): capture_name += "_" + arg.get_slice("=", 1)
		get_viewport().get_texture().get_image().save_png(directory.path_join("castle_city_%s.png" % capture_name))
		get_tree().quit()

# --- Height field -----------------------------------------------------------

## One height field serves both gameplay and visuals; the only water is the lake.
func _cache_city() -> void:
	var started := Time.get_ticks_msec()
	_build_roads()
	var row := SIZE + 2
	height_cache.resize(row * row)
	for z in range(-1, SIZE + 1):
		for x in range(-1, SIZE + 1):
			height_cache[(z + 1) * row + x + 1] = _expanded_height(x, z)
	gameplay_cache = height_cache.duplicate()
	water_cache.resize((SIZE + 1) * (SIZE + 1))
	water_cache.fill(LAKE)
	print("[JRPGWorld3] Heights baked in ", Time.get_ticks_msec() - started, " ms")

func _expanded_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var e := _basin_e(p)
	var h := lerpf(LAKE + 0.8, _outer_ground(p), smoothstep(1.0, 1.22, e))
	if e < 1.0: h = lerpf(LAKE - 6.0, LAKE + 0.8, smoothstep(0.8, 1.0, e))
	return _apply_approach(p, _apply_island(p, h))

## Elliptical basin distance: < 1 is the lake, the shore meadow lies around 1.0-1.2.
func _basin_e(p: Vector2) -> float:
	return ((p - CITY_AT) / LAKE_HALF).length() + noise.get_noise_2d(p.x * 0.6 + 900.0, p.y * 0.6) * 0.06

## Meadows around the lake, ringed by terraced bluffs that step up in cliff bands, with the
## far ranges beyond the map.
func _outer_ground(p: Vector2) -> float:
	var h := 13.0 + noise.get_noise_2d(p.x * 0.3, p.y * 0.3) * 2.5 + noise.get_noise_2d(p.x * 1.3 + 500.0, p.y * 1.3 - 300.0) * 0.8
	var d := p.distance_to(CITY_AT) + noise.get_noise_2d(p.x * 0.5 + 90.0, p.y * 0.5 - 40.0) * 30.0
	var k := 38.0 * smoothstep(170.0, 255.0, d) / 7.0
	h += (floorf(k) + smoothstep(0.75, 1.0, k - floorf(k))) * 7.0
	return h + _far_peaks(p)

func _far_peaks(p: Vector2) -> float:
	var m := 0.0
	for peak: Array in FAR_PEAKS:
		var t: float = 1.0 - p.distance_to(peak[0]) / float(peak[2])
		if t > 0.0: m = maxf(m, float(peak[1]) * pow(t, 1.25))
	if m <= 0.0: return 0.0
	return m * (0.8 + 0.32 * (1.0 - absf(noise.get_noise_2d(p.x * 0.45 + 40.0, p.y * 0.45 - 90.0))))

## The island: terraced streets inside the walls, a ragged ledge outside them, then a short
## rock cliff down to the lake bed. A broad landing stays clear in front of the gate.
func _apply_island(p: Vector2, h: float) -> float:
	if p.x < 110.0 or p.x > 290.0 or p.y < 70.0 or p.y > 290.0: return h
	var sdf := _wall_sdf(p)
	var ledge := 1.6 + maxf(0.0, noise.get_noise_2d(p.x * 1.4 + 300.0, p.y * 1.4)) * 9.0
	if p.y > GATE_Z - 8.0: ledge = maxf(ledge, 5.0 * (1.0 - smoothstep(10.0, 16.0, absf(p.x - AXIS))))
	if sdf > ledge + 5.0: return h
	return lerpf(h, _city_height(p), 1.0 - smoothstep(ledge, ledge + 4.5, sdf))

func _city_height(p: Vector2) -> float:
	var r := p.distance_to(APEX)
	return _terrace(p, r, _terrace(p, r, TIERS[0], R1, TIERS[1]), R2, TIERS[2])

## A sheer terrace face at `radius`, except on the stairs along the main street where it
## becomes a STAIR_RUN-long ramp (the steps are drawn over it).
func _terrace(p: Vector2, r: float, lower: float, radius: float, upper: float) -> float:
	var cliff := 1.0 - smoothstep(radius - 0.5, radius + 0.5, r)
	var ramp := clampf((radius + STAIR_RUN * 0.5 - r) / STAIR_RUN, 0.0, 1.0)
	var stairs := 1.0 - smoothstep(STAIR_HALF - 0.3, STAIR_HALF + 0.3, absf(p.x - AXIS)) if p.y > APEX.y else 0.0
	return lerpf(lower, upper, lerpf(cliff, ramp, stairs))

## Terrace index: 0 lower town, 1 knights' tier, 2 summit.
func _tier_at(p: Vector2) -> int:
	var r := p.distance_to(APEX)
	return 2 if r < R2 else (1 if r < R1 else 0)

## The road embankment that carries the bridge's south end onto the shore.
func _apply_approach(p: Vector2, h: float) -> float:
	if p.y < BRIDGE_Z.y - 6.0 or p.y > 352.0: return h
	var w := 1.0 - smoothstep(5.0, 22.0, absf(p.x - AXIS))
	if w <= 0.0: return h
	return lerpf(h, lerpf(DECK, h, smoothstep(BRIDGE_Z.y + 1.0, 350.0, p.y)), w)

## Signed distance to the city wall's center line, negative inside.
func _wall_sdf(p: Vector2) -> float:
	var best := INF
	for i in WALL.size():
		best = minf(best, _segment_distance(p, WALL[i], WALL[(i + 1) % WALL.size()]))
	return -best if Geometry2D.is_point_in_polygon(p, wall_polygon) else best

## The bridge deck is walkable over the lake.
func _surface(x: float, z: float) -> float:
	if absf(x - AXIS) < BRIDGE_HALF + 0.2 and z > BRIDGE_Z.x - 1.0 and z < BRIDGE_Z.y + 1.0:
		return maxf(DECK, _height(x, z))
	return _height(x, z)

func _build_roads() -> void:
	path_field.resize((SIZE + 1) * (SIZE + 1))
	path_field.fill(50.0)
	for road: Array in ROADS:
		var half: float = road[0]
		var dense := _smooth(road[1])
		path_points.append(dense)
		for i in dense.size() - 1:
			var a: Vector2 = dense[i]
			var b: Vector2 = dense[i + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(6, 6)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(6, 6)
			for z in range(maxi(0, floori(lo.y)), mini(SIZE, ceili(hi.y)) + 1):
				for x in range(maxi(0, floori(lo.x)), mini(SIZE, ceili(hi.x)) + 1):
					var index := z * (SIZE + 1) + x
					path_field[index] = minf(path_field[index], _segment_distance(Vector2(x, z), a, b) - half)

# --- Batched parts -------------------------------------------------------------

## While batching, static parts are merged into one mesh per material and CHUNK cell
## instead of a node each; parts under a "dynamic" node (windmill sails) stay nodes.
func _part(parent: Node3D, kind: String, size: Vector3, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	if not batching or _is_dynamic(parent): return super._part(parent, kind, size, at, material, rot)
	var xform := parent.global_transform * Transform3D(Basis.from_euler(rot), at)
	var key := "%s_%s" % [kind, size]
	if not shape_arrays.has(key):
		var shape := _shape(kind, size)
		shape_arrays[key] = (shape as PrimitiveMesh).get_mesh_arrays() if shape is PrimitiveMesh else shape.surface_get_arrays(0)
	var arrays: Array = shape_arrays[key]
	var cell := Vector2i(floori(xform.origin.x / CHUNK), floori(xform.origin.z / CHUNK))
	if not batches.has(material): batches[material] = {}
	if not batches[material].has(cell): batches[material][cell] = PartBatch.new()
	var batch: PartBatch = batches[material][cell]
	var vertices: PackedVector3Array = xform * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var normals: PackedVector3Array = Transform3D(xform.basis.orthonormalized(), Vector3.ZERO) * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var shifted := PackedInt32Array()
	shifted.resize(indices.size())
	for i in indices.size(): shifted[i] = indices[i] + batch.vertex_count
	batch.parts.append([vertices, normals, arrays[Mesh.ARRAY_TEX_UV], shifted])
	batch.vertex_count += vertices.size()
	return null

func _is_dynamic(node: Node) -> bool:
	while node and node != self:
		if node.has_meta("dynamic"): return true
		node = node.get_parent()
	return false

func _flush_parts(parent: Node3D) -> void:
	var count := 0
	for material: Material in batches:
		for cell: Vector2i in batches[material]:
			var batch: PartBatch = batches[material][cell]
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var uvs := PackedVector2Array()
			var indices := PackedInt32Array()
			for part: Array in batch.parts:
				vertices.append_array(part[0])
				normals.append_array(part[1])
				uvs.append_array(part[2])
				indices.append_array(part[3])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var instance := MeshInstance3D.new()
			instance.name = "Parts_%d_%d_%d" % [count, cell.x, cell.y]
			instance.mesh = mesh
			parent.add_child(instance)
			count += 1
	batches.clear()
	print("[JRPGWorld3] Merged city parts into ", count, " meshes")

## Extra primitive kinds: sphere, right-angled prisms (apex over the left / right edge),
## an octagonal spire, and the statue's gown and feathers (built meshes).
func _shape(kind: String, size: Vector3) -> Mesh:
	if not kind in ["sphere", "prism_l", "prism_r", "spire", "gown", "feather"]: return super._shape(kind, size)
	var key := "%s_%s" % [kind, size]
	if kind == "gown" and not meshes.has(key): meshes[key] = _gown_mesh()
	if kind == "feather" and not meshes.has(key): meshes[key] = _feather_mesh(size)
	if not meshes.has(key):
		var mesh: PrimitiveMesh
		match kind:
			"sphere":
				mesh = SphereMesh.new()
				mesh.radius = size.x
				mesh.height = size.y
				mesh.radial_segments = 14
				mesh.rings = 7
			"prism_l", "prism_r":
				mesh = PrismMesh.new()
				mesh.size = size
				mesh.left_to_right = 0.0 if kind == "prism_l" else 1.0
			"spire":
				mesh = CylinderMesh.new()
				mesh.bottom_radius = size.x
				mesh.top_radius = 0.0
				mesh.height = size.y
				mesh.radial_segments = 8
				mesh.rings = 1
		meshes[key] = mesh
	return meshes[key]

## The statue's gown, shoulders and hood as one surface of revolution (origin at the hem),
## with soft folds rippling round the skirt.
func _gown_mesh() -> ArrayMesh:
	var profile := [[2.05, 0.0], [2.0, 0.45], [1.78, 1.4], [1.48, 2.9], [1.15, 4.4], [0.85, 5.7], [0.7, 6.4], [0.8, 7.2],
		[0.98, 7.9], [1.08, 8.35], [0.95, 8.75], [0.52, 9.0], [0.64, 9.2], [0.8, 9.6], [0.76, 10.0], [0.58, 10.35], [0.28, 10.6], [0.0, 10.7]]
	var segments := 40
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Batched parts carry UVs and indices like the primitive meshes.
	st.set_uv(Vector2.ZERO)
	var rows: Array = []
	for point: Array in profile:
		var row: Array[Vector3] = []
		var y: float = point[1]
		for k in segments + 1:
			var theta := TAU * k / segments
			var fold := 1.0 + 0.07 * sin(theta * 9.0 + y * 0.35) * (1.0 - smoothstep(5.0, 6.4, y))
			# The hood opens toward the front (+Z): pulled back there, deeper behind.
			var hood := 1.0 - 0.18 * smoothstep(9.1, 9.6, y) * maxf(0.0, sin(theta))
			var r: float = point[0] * fold * hood
			row.append(Vector3(cos(theta) * r, y, sin(theta) * r))
		rows.append(row)
	for i in rows.size() - 1:
		for k in segments:
			var a: Vector3 = rows[i][k]
			var b: Vector3 = rows[i][k + 1]
			var c: Vector3 = rows[i + 1][k]
			var d: Vector3 = rows[i + 1][k + 1]
			for p in [a, c, b, b, c, d]: st.add_vertex(p)
	st.generate_normals()
	st.index()
	return st.commit()

## A tapered, pointed feather lying in local XY (size: width, length, thickness), its quill
## root at the origin and its tip up +Y.
func _feather_mesh(size: Vector3) -> ArrayMesh:
	var outline: Array[Vector2] = []
	var steps := 6
	for i in steps + 1:
		var s := float(i) / steps
		var half := size.x * 0.5 * (lerpf(0.55, 1.0, s / 0.25) if s < 0.25 else pow(1.0 - (s - 0.25) / 0.75, 0.7))
		outline.append(Vector2(half, s * size.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_uv(Vector2.ZERO)
	var t := size.z * 0.5
	for i in steps:
		var a := outline[i]
		var b := outline[i + 1]
		for face in [1.0, -1.0]:
			var quad := [Vector3(-a.x, a.y, t * face), Vector3(a.x, a.y, t * face), Vector3(-b.x, b.y, t * face), Vector3(b.x, b.y, t * face)]
			if face > 0.0: for q in [0, 2, 1, 1, 2, 3]: st.add_vertex(quad[q])
			else: for q in [0, 1, 2, 1, 3, 2]: st.add_vertex(quad[q])
		for side in [1.0, -1.0]:
			var edge := [Vector3(side * a.x, a.y, t), Vector3(side * a.x, a.y, -t), Vector3(side * b.x, b.y, t), Vector3(side * b.x, b.y, -t)]
			if side > 0.0: for q in [0, 1, 2, 2, 1, 3]: st.add_vertex(edge[q])
			else: for q in [0, 2, 1, 2, 3, 1]: st.add_vertex(edge[q])
	st.generate_normals()
	st.index()
	return st.commit()

## Window glass that glows warm after dusk (see _process).
func _window_glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("3f6382")
	glass.roughness = 0.25
	glass.emission_enabled = true
	glass.emission = Color("ffc977")
	glass.emission_energy_multiplier = 0.0
	return glass

## World-space masonry (castle_stone.gdshader), registered with Props so weather reaches it.
func _stone(stone: Color, mortar: Color, brick := Vector2(1.2, 0.55)) -> ShaderMaterial:
	var key := "castle_%s_%s_%s" % [stone.to_html(), mortar.to_html(), brick]
	if not Props.materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = STONE_SHADER
		material.set_shader_parameter("stone", stone)
		material.set_shader_parameter("mortar", mortar)
		material.set_shader_parameter("brick", brick)
		Props.materials[key] = material
	return Props.materials[key]

func _setup_materials() -> void:
	mat = {
		"wall": _stone(Color("bdb8ab"), Color("8a867c")),
		"keep": _stone(Color("a9a69d"), Color("7b786f"), Vector2(1.3, 0.6)),
		"church": _stone(Color("dcd9cf"), Color("aaa69b"), Vector2(0.9, 0.45)),
		"house": _stone(Color("c9c2b2"), Color("958e7f"), Vector2(0.8, 0.4)),
		"trim": Props.flat(Color("dcd6c6")),
		"dark": Props.flat(Color("262d36")),
		"glass": Props.flat(Color("3f6382"), 0.25),
		"rose": Props.flat(Color("3f72b8"), 0.25, Color("1c3666")),
		"door": Props.flat(Color("6b4a32")),
		"timber": Props.flat(Color("5e402c")),
		"wood": Props.flat(Color("8b6440")),
		"iron": Props.flat(Color("2d2f33"), 0.6),
		"red": Props.flat(Color("c23b33"), 0.8),
		"gold": Props.flat(Color("e0b45a"), 0.5),
		"white": Props.flat(Color("f4f1e8")),
		"blue": Props.flat(Color("3b5f9a")),
		"green_roof": Props.flat(Color("4f8c78"), 0.7),
		"slate": Props.flat(Color("5b6f86"), 0.7),
		"hedge": Props.flat(Color("4c8a3c")),
		"ivy": Props.flat(Color("4a8436")),
		"ivy_light": Props.flat(Color("6aa648")),
		"glass_lit": _window_glass(),
		"water": Props.flat(Color("5aa6bd"), 0.12),
		"statue": Props.rock_material(Color("a9aeb3"), 0.06),
	}

# --- World ------------------------------------------------------------------

func _build_city() -> void:
	var started := Time.get_ticks_msec()
	_setup_materials()
	lamp_material = Props.flat(Color("ffd58a"), 0.5, Color("ffb54d"))
	_build_city_terrain()
	_build_far_ring()
	_build_lake()
	# One still water body: the sea and river slots of the weather sync share the lake's.
	sea_material = lake_material
	river_material = lake_material
	var root := Node3D.new()
	root.name = "Aurelia"
	add_child(root)
	batching = true
	_build_ramparts(root)
	_build_gatehouse(root)
	_build_bridge(root)
	_build_terraces(root)
	_build_cathedral(root)
	_build_statue_plaza(root)
	_build_pavilions(root)
	_build_keep(root)
	for mill: Array in MILLS: _mill(root, mill[0], mill[1])
	_build_streets(root)
	_build_houses(root)
	batching = false
	_flush_parts(root)
	_index_obstacles()
	_build_island_rocks()
	_build_city_trees()
	_index_obstacles()
	_build_city_grass()
	_build_city_labels(root)
	print("[JRPGWorld3] Built castle city in ", Time.get_ticks_msec() - started, " ms")

## Terrain chunks. COLOR: r = dirt road, g = shore sand, b = cobbles inside the walls.
func _build_city_terrain() -> void:
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	for cz in range(0, SIZE, CHUNK):
		for cx in range(0, SIZE, CHUNK):
			var x1 := mini(cx + CHUNK, SIZE)
			var z1 := mini(cz + CHUNK, SIZE)
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var uvs := PackedVector2Array()
			for z in range(cz, z1 + 1):
				for x in range(cx, x1 + 1):
					var h := _cached(x, z)
					vertices.append(Vector3(x, h, z))
					var normal := Vector3(_cached(x - 1, z) - _cached(x + 1, z), 2.0, _cached(x, z - 1) - _cached(x, z + 1))
					normals.append(normal.normalized())
					var p := Vector2(x, z)
					var city := 0.0
					if x > 110 and x < 290 and z > 70 and z < 290: city = 1.0 - smoothstep(-1.5, 0.0, _wall_sdf(p))
					var above := h - LAKE
					var road := (1.0 - smoothstep(-0.4, 1.0, _path_distance(x, z) + noise.get_noise_2d(x * 5.0, z * 5.0) * 0.8)) * (1.0 - city)
					var steep := smoothstep(1.4, 2.4, Vector2(normal.x, normal.z).length())
					var sand := (1.0 - smoothstep(0.4, 1.8, above)) * (1.0 - road) * (1.0 - steep) * (1.0 - city)
					colors.append(Color(road, sand, city, 0.0))
					uvs.append(Vector2(-above, 0.0))
			var width := x1 - cx + 1
			var indices := PackedInt32Array()
			for z in z1 - cz:
				for x in x1 - cx:
					var i := z * width + x
					indices.append_array([i, i + 1, i + width, i + 1, i + width + 1, i + width])
			var chunk := MeshInstance3D.new()
			chunk.name = "Terrain_%d_%d" % [cx / CHUNK, cz / CHUNK]
			chunk.mesh = _array_mesh(vertices, normals, colors, indices, terrain_material, uvs)
			root.add_child(chunk)

## Coarse bluffs and ranges beyond the playable square.
func _build_far_ring() -> void:
	var step := 8
	var lo := -480
	var count := (SIZE + 960) / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for j in count:
		for i in count:
			var x := float(lo + i * step)
			var z := float(lo + j * step)
			var inside := x >= 0 and x <= SIZE and z >= 0 and z <= SIZE
			var h := _cached(int(x), int(z)) - 0.4 if inside else _expanded_height(x, z)
			vertices.append(Vector3(x, h, z))
			colors.append(Color(0, 0, 0, 0))
			uvs.append(Vector2(LAKE - h, 0.0))
	for j in count:
		for i in count:
			var l := vertices[j * count + maxi(i - 1, 0)].y
			var r := vertices[j * count + mini(i + 1, count - 1)].y
			var d := vertices[maxi(j - 1, 0) * count + i].y
			var u := vertices[mini(j + 1, count - 1) * count + i].y
			normals.append(Vector3(l - r, 2.0 * step, d - u).normalized())
	var indices := PackedInt32Array()
	for j in count - 1:
		for i in count - 1:
			var x := lo + i * step
			var z := lo + j * step
			if x >= step and x + step <= SIZE - step and z >= step and z + step <= SIZE - step: continue
			var k := j * count + i
			indices.append_array([k, k + 1, k + count, k + 1, k + count + 1, k + count])
	var far := MeshInstance3D.new()
	far.name = "FarTerrain"
	far.mesh = _array_mesh(vertices, normals, colors, indices, terrain_material, uvs)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)

# --- Walls and gate --------------------------------------------------------------

func _build_ramparts(root: Node3D) -> void:
	var count := WALL.size()
	var tops: Array[float] = []
	for i in count:
		var a: Vector2 = WALL[i]
		var b: Vector2 = WALL[(i + 1) % count]
		var top := 0.0
		for s in 9: top = maxf(top, _city_height(a.lerp(b, s / 8.0)))
		tops.append(top + WALL_RISE)
	for i in count:
		var a: Vector2 = WALL[i]
		var b: Vector2 = WALL[(i + 1) % count]
		if i == 0:
			# The gatehouse fills the middle of the south wall.
			_rampart(root, a, Vector2(AXIS - 14.0, GATE_Z), tops[i])
			_rampart(root, Vector2(AXIS + 14.0, GATE_Z), b, tops[i])
		else:
			_rampart(root, a, b, tops[i])
	for i in count:
		_bastion(root, WALL[i], maxf(tops[i], tops[(i - 1 + count) % count]) + 4.0, i % 4 == 2)

## A thick crenellated curtain wall rising from below the ledge, with a corbelled walk,
## arrow slits and ivy on its outer face.
func _rampart(root: Node3D, a: Vector2, b: Vector2, top: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var out := Vector2(-dir.y, dir.x)
	var wall_yaw := Vector3(0, atan2(-dir.y, dir.x), 0)
	var bottom := LAKE - 3.0
	var mid := (a + b) * 0.5
	var stone: Material = mat.wall
	_part(root, "box", Vector3(length, top - bottom, 3.0), Vector3(mid.x, (top + bottom) * 0.5, mid.y), stone, wall_yaw)
	_part(root, "box", Vector3(length, 0.7, 3.7), Vector3(mid.x, top - 1.4, mid.y), stone, wall_yaw)
	var inner := mid - out * 1.25
	_part(root, "box", Vector3(length, 0.7, 0.5), Vector3(inner.x, top + 0.35, inner.y), stone, wall_yaw)
	var merlons := maxi(1, int(length / 1.9))
	for m in merlons:
		var q := a.lerp(b, (m + 0.5) / merlons) + out * 1.45
		_part(root, "box", Vector3(1.0, 1.3, 0.8), Vector3(q.x, top + 0.65, q.y), stone, wall_yaw)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.x * 31.0 + a.y * 17.0)
	for s in maxi(1, int(length / 9.0)):
		var q := a.lerp(b, (s + 0.5) / maxi(1, int(length / 9.0))) + out * 1.53
		_part(root, "box", Vector3(0.28, 1.6, 0.1), Vector3(q.x, top - 4.0, q.y), mat.dark, wall_yaw)
		if rng.randf() < 0.45:
			var p := q + dir * rng.randf_range(-3.0, 3.0)
			var foot := maxf(_height(p.x + out.x * 2.0, p.y + out.y * 2.0), LAKE)
			_ivy(root, Vector3(p.x, foot, p.y) - Vector3(out.x, 0, out.y) * 0.03, rng.randf_range(3.0, 7.0), dir, out, rng)
	for k in ceili(length / 1.2) + 1:
		_block(a.lerp(b, k / ceilf(length / 1.2)), Vector2(1.7, 1.7))

## A ragged patch of ivy climbing `height` meters up a wall face from `foot`: overlapping
## leaf clumps in two greens, thinning toward the top. `along` runs with the wall, `out`
## is the face normal.
func _ivy(root: Node3D, foot: Vector3, height: float, along: Vector2, out: Vector2, rng: RandomNumberGenerator) -> void:
	var rot := Vector3(0, atan2(-along.y, along.x), 0)
	var leaves: Array[Material] = [mat.ivy, mat.ivy_light]
	var y := 0.0
	while y < height:
		var spread := lerpf(1.6, 0.5, y / height)
		for k in 2:
			var size := Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.6, 1.3), 0.12 + k * 0.04)
			var p := foot + Vector3(along.x, 0, along.y) * rng.randf_range(-spread, spread) + Vector3(out.x, 0, out.y) * (0.06 + k * 0.04) + Vector3(0, y + size.y * 0.5, 0)
			_part(root, "box", size, p, leaves[(k + int(y)) % 2], rot)
		y += rng.randf_range(0.5, 0.9)

## Round wall tower at a corner of the wall: crenellated, or capped with a slate cone.
func _bastion(root: Node3D, at: Vector2, top: float, roofed: bool) -> void:
	var r := 4.2
	var bottom := LAKE - 3.0
	var stone: Material = mat.wall
	_part(root, "cylinder", Vector3(r, top - bottom, r), Vector3(at.x, (top + bottom) * 0.5, at.y), stone)
	_part(root, "cylinder", Vector3(r + 0.45, 0.9, r + 0.45), Vector3(at.x, top - 0.45, at.y), stone)
	if roofed:
		_part(root, "cone", Vector3(r + 0.8, r * 2.6, 0), Vector3(at.x, top + r * 1.3, at.y), mat.slate)
	else:
		for k in 12:
			var angle := k * TAU / 12.0
			var q := at + Vector2(cos(angle), sin(angle)) * (r + 0.05)
			_part(root, "box", Vector3(1.1, 1.3, 0.8), Vector3(q.x, top + 0.65, q.y), stone, Vector3(0, -angle + PI / 2.0, 0))
	for k in 4:
		var angle := k * TAU / 4.0 + 0.4
		var q := at + Vector2(cos(angle), sin(angle)) * (r + 0.02)
		_part(root, "box", Vector3(0.28, 1.6, 0.12), Vector3(q.x, top - 4.5, q.y), mat.dark, Vector3(0, -angle + PI / 2.0, 0))
	_block(at, Vector2(r, r))

## Twin square towers with red banners flank a pointed archway; the raised portcullis
## shows its teeth and a lion crest sits over the arch. Local +Z faces the bridge.
func _build_gatehouse(root: Node3D) -> void:
	var gate := _anchor(root, Vector2(AXIS, GATE_Z), 0.0, TIERS[0])
	gate.name = "Gatehouse"
	var stone: Material = mat.wall
	for side in [-1, 1]:
		var x: float = side * 9.5
		_part(gate, "box", Vector3(9, 31, 9), Vector3(x, 5.5, 0), stone)
		_part(gate, "box", Vector3(9.8, 1.0, 9.8), Vector3(x, 19.6, 0), stone)
		for k in 4:
			var t := -3.6 + k * 2.4
			for edge in [Vector3(t, 0, 4.55), Vector3(t, 0, -4.55), Vector3(4.55, 0, t), Vector3(-4.55, 0, t)]:
				_part(gate, "box", Vector3(1.1, 1.4, 1.1), Vector3(x, 21.7, 0) + edge, stone)
		for wy in [9.5, 14.5]:
			_lancet(gate, Vector3(x + side * 2.2, wy, 4.52), Vector2(0.8, 1.5), mat.glass)
		_banner(gate, Vector3(x - side * 1.4, 15.5, 4.56), 1.9, 8.0, mat.red, true)
		_block(Vector2(AXIS + x, GATE_Z), Vector2(4.5, 4.5))
	# Arch: pillars, corner fills that point the opening, and the wall above.
	for side in [-1, 1]:
		_part(gate, "box", Vector3(2.5, 17.8, 7), Vector3(side * 3.75, -1.1, 0), stone)
		_block(Vector2(AXIS + side * 3.75, GATE_Z), Vector2(1.25, 3.5))
	_part(gate, "prism_r", Vector3(2.5, 2.6, 7), Vector3(-1.25, 6.5, 0), stone, Vector3(0, 0, PI))
	_part(gate, "prism_l", Vector3(2.5, 2.6, 7), Vector3(1.25, 6.5, 0), stone, Vector3(0, 0, PI))
	_part(gate, "box", Vector3(10, 10.7, 7), Vector3(0, 13.15, 0), stone)
	_part(gate, "box", Vector3(10.6, 0.7, 7.8), Vector3(0, 17.2, 0), stone)
	for k in 4:
		for face in [3.7, -3.7]:
			_part(gate, "box", Vector3(1.1, 1.3, 0.8), Vector3(-3.75 + k * 2.5, 19.15, face), stone)
	# Raised archivolt around the opening.
	for side in [-1, 1]:
		_part(gate, "box", Vector3(0.6, 5.4, 0.4), Vector3(side * 2.8, 2.7, 3.6), mat.trim)
		_part(gate, "box", Vector3(3.7, 0.55, 0.4), Vector3(side * 1.45, 6.75, 3.6), mat.trim, Vector3(0, 0, -side * 0.805))
	# Lion crest, windows and the portcullis.
	_part(gate, "box", Vector3(2.1, 2.1, 0.35), Vector3(0, 10.4, 3.65), mat.trim, Vector3(0, 0, PI / 4.0))
	_part(gate, "cylinder", Vector3(0.75, 0.25, 0.75), Vector3(0, 10.4, 3.85), mat.gold, Vector3(PI / 2.0, 0, 0))
	for wx in [-2.2, 0.0, 2.2]:
		_lancet(gate, Vector3(wx, 13.6, 3.52), Vector2(0.7, 1.3), mat.glass)
	for k in 9:
		_part(gate, "box", Vector3(0.12, 1.5, 0.12), Vector3(-2.2 + k * 0.55, 4.75, 2.6), mat.iron)
	for y in [4.4, 5.2]:
		_part(gate, "box", Vector3(4.9, 0.12, 0.12), Vector3(0, y, 2.6), mat.iron)
	# Bracket lanterns on the pillars.
	for side in [-1, 1]:
		var lantern := Vector3(side * 3.75, 4.6, 3.95)
		_part(gate, "box", Vector3(0.1, 0.1, 0.7), lantern + Vector3(0, 0.6, -0.1), mat.iron)
		_part(gate, "box", Vector3(0.36, 0.5, 0.36), lantern, lamp_material)
		_part(gate, "cone", Vector3(0.3, 0.3, 0), lantern + Vector3(0, 0.4, 0), mat.iron)

## Pointed window: pane under a small gable, on a face whose normal is the parent's +Z
## (rotated by `rot_y`).
func _lancet(parent: Node3D, at: Vector3, size: Vector2, glass: Material, rot_y := 0.0) -> void:
	var rot := Vector3(0, rot_y, 0)
	_part(parent, "box", Vector3(size.x + 0.3, size.y + 0.15, 0.06), at + Vector3(0, -0.075, 0), mat.trim, rot)
	_part(parent, "box", Vector3(size.x, size.y, 0.1), at, glass, rot)
	_part(parent, "prism", Vector3(size.x, size.x * 0.7, 0.1), at + Vector3(0, size.y * 0.5 + size.x * 0.35, 0), glass, rot)

## Hanging banner with a gold rod and a swallowtail; `crosses` adds the white cross motif.
## The cloth faces the parent's +Z.
func _banner(parent: Node3D, at: Vector3, width: float, height: float, cloth: Material, crosses := false) -> void:
	_part(parent, "box", Vector3(width, height, 0.06), at, cloth)
	for side in [-1, 1]:
		_part(parent, "prism", Vector3(width * 0.5, width * 0.55, 0.06), at + Vector3(side * width * 0.25, -height * 0.5 - width * 0.275, 0), cloth, Vector3(0, 0, PI))
		_part(parent, "box", Vector3(0.1, height, 0.07), at + Vector3(side * (width * 0.5 - 0.05), 0, 0.01), mat.gold)
	_part(parent, "box", Vector3(width + 0.5, 0.14, 0.14), at + Vector3(0, height * 0.5 + 0.05, 0.02), mat.gold)
	if crosses:
		for k in 3:
			var c := at + Vector3(0, height * 0.32 - k * height * 0.28, 0.04)
			_part(parent, "box", Vector3(width * 0.36, 0.13, 0.03), c, mat.white)
			_part(parent, "box", Vector3(0.13, width * 0.36, 0.03), c, mat.white)

# --- Bridge -----------------------------------------------------------------------

## Stone bridge on arched spans: piers with cutwaters, corbelled parapets, posts with lamps
## and blue-white banners, ivy trailing down the spandrels.
func _build_bridge(root: Node3D) -> void:
	var stone: Material = mat.wall
	var length := BRIDGE_Z.y - BRIDGE_Z.x
	var mid := (BRIDGE_Z.x + BRIDGE_Z.y) * 0.5
	var deck_bottom := DECK - 1.0
	_part(root, "box", Vector3(8.0, 1.0, length), Vector3(AXIS, DECK - 0.5, mid), stone)
	var bed := LAKE - 6.0
	for pier: float in BRIDGE_PIERS:
		_part(root, "box", Vector3(8.6, deck_bottom - bed, 2.2), Vector3(AXIS, (deck_bottom + bed) * 0.5, pier), stone)
		for side in [-1, 1]:
			_part(root, "box", Vector3(1.55, LAKE + 2.0 - bed, 1.55), Vector3(AXIS + side * 4.3, (LAKE + 2.0 + bed) * 0.5, pier), stone, Vector3(0, PI / 4.0, 0))
	var supports: Array[float] = [BRIDGE_Z.x]
	for pier: float in BRIDGE_PIERS: supports.append(pier)
	supports.append(BRIDGE_Z.y)
	for s in supports.size() - 1:
		var a := supports[s] + (1.1 if s > 0 else 0.0)
		var b := supports[s + 1] - (1.1 if s + 1 < supports.size() - 1 else 0.0)
		var n := ceili((b - a) / 0.5)
		for k in n:
			var z0 := lerpf(a, b, float(k) / n)
			var z1 := lerpf(a, b, float(k + 1) / n)
			var t := ((z0 + z1) * 0.5 - a) / (b - a)
			var arc := lerpf(LAKE - 1.0, deck_bottom - 0.7, sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0))))
			_part(root, "box", Vector3(8.0, deck_bottom - arc + 0.05, z1 - z0 + 0.02), Vector3(AXIS, (deck_bottom + arc) * 0.5, (z0 + z1) * 0.5), stone)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 61
	for side in [-1, 1]:
		var x: float = AXIS + side * 3.75
		_part(root, "box", Vector3(0.5, 1.05, length), Vector3(x, DECK + 0.52, mid), stone)
		_part(root, "box", Vector3(0.75, 0.16, length), Vector3(x, DECK + 1.12, mid), mat.trim)
		var z := BRIDGE_Z.x + 0.7
		while z < BRIDGE_Z.y:
			_part(root, "box", Vector3(0.35, 0.45, 0.4), Vector3(AXIS + side * 4.15, DECK - 1.2, z), stone)
			z += 1.4
		for k in supports.size():
			var at := Vector3(x, DECK, clampf(supports[k], BRIDGE_Z.x + 0.5, BRIDGE_Z.y - 0.5))
			_part(root, "box", Vector3(0.85, 1.7, 0.85), at + Vector3(0, 0.85, 0), stone)
			_part(root, "box", Vector3(1.0, 0.2, 1.0), at + Vector3(0, 1.8, 0), mat.trim)
			if (k + (1 if side > 0 else 0)) % 2 == 0:
				_street_lamp(root, Vector2(at.x, at.z), 0.0 if side < 0 else PI, DECK + 1.9, true)
			else:
				_part(root, "cone", Vector3(0.45, 0.6, 0), at + Vector3(0, 2.2, 0), mat.trim)
		for s in supports.size() - 1:
			if rng.randf() < 0.5:
				var ivy := rng.randf_range(2.5, 5.0)
				var at := Vector3(AXIS + side * 4.0, DECK - 0.3 - ivy, lerpf(supports[s], supports[s + 1], rng.randf_range(0.25, 0.75)))
				_ivy(root, at, ivy, Vector2(0, 1), Vector2(side, 0), rng)
		for zb in range(int(BRIDGE_Z.x), int(BRIDGE_Z.y) + 1):
			_block(Vector2(AXIS + side * 3.95, zb), Vector2(0.4, 0.6))

## Iron street lamp; the arm and lantern reach toward local +X of `yaw_angle`. With a
## banner it also flies a blue-white pennant from the pole.
func _street_lamp(root: Node3D, at: Vector2, yaw_angle: float, height := NAN, banner := false) -> void:
	var node := _anchor(root, at, yaw_angle, height)
	var iron: Material = mat.iron
	_part(node, "cylinder", Vector3(0.1, 4.0, 0.08), Vector3(0, 2.0, 0), iron)
	_part(node, "cylinder", Vector3(0.2, 0.4, 0.2), Vector3(0, 0.2, 0), iron)
	_part(node, "box", Vector3(1.0, 0.08, 0.08), Vector3(0.4, 3.85, 0), iron)
	_part(node, "box", Vector3(0.36, 0.5, 0.36), Vector3(0.8, 3.45, 0), lamp_material)
	_part(node, "cone", Vector3(0.32, 0.28, 0), Vector3(0.8, 3.85, 0), iron)
	if banner:
		_part(node, "box", Vector3(0.05, 1.8, 0.62), Vector3(0, 2.3, 0.36), mat.white)
		_part(node, "box", Vector3(0.06, 1.8, 0.14), Vector3(0, 2.3, 0.62), mat.blue)
		_part(node, "box", Vector3(0.06, 0.3, 0.62), Vector3(0, 1.55, 0.36), mat.blue)
		_part(node, "prism", Vector3(0.62, 0.4, 0.05), Vector3(0, 1.2, 0.36), mat.white, Vector3(0, PI / 2.0, PI))
	_block(at, Vector2(0.3, 0.3))

# --- Terraces ---------------------------------------------------------------------

func _build_terraces(root: Node3D) -> void:
	_terrace_wall(root, R1, TIERS[0], TIERS[1])
	_terrace_wall(root, R2, TIERS[1], TIERS[2])
	_stairs(root, R1, TIERS[0], TIERS[1])
	_stairs(root, R2, TIERS[1], TIERS[2])

## Retaining wall along a terrace face, standing a parapet's height above the upper street.
func _terrace_wall(root: Node3D, radius: float, lower: float, upper: float) -> void:
	var step := 2.0 / radius
	var theta := 0.0
	while theta <= PI:
		var a := APEX + Vector2(cos(theta), sin(theta)) * radius
		var angle := theta
		theta += step
		if _wall_sdf(a) > -2.0 or absf(a.x - AXIS) < STAIR_HALF + 0.6: continue
		var rot := Vector3(0, -(angle + PI / 2.0), 0)
		# Centered half a meter downhill so it also hides the terrain's 1 m cliff facets.
		var c := APEX + Vector2(cos(angle), sin(angle)) * (radius + 0.5)
		_part(root, "box", Vector3(2.2, upper - lower + 2.0, 2.4), Vector3(c.x, (lower - 1.0 + upper + 1.0) * 0.5, c.y), mat.wall, rot)
		_part(root, "box", Vector3(2.25, 0.16, 2.7), Vector3(c.x, upper + 1.08, c.y), mat.trim, rot)
		_block(c, Vector2(1.3, 1.3))

## Steps over the stair ramp, with balustrade walls stepping down both sides.
func _stairs(root: Node3D, radius: float, lower: float, upper: float) -> void:
	var z_top := APEX.y + radius - STAIR_RUN * 0.5
	var steps := ceili((upper - lower) / 0.3)
	var rise := (upper - lower) / steps
	var run := STAIR_RUN / steps
	for i in steps:
		var z := z_top + STAIR_RUN - (i + 0.5) * run
		var top := lower + (i + 0.5) * rise + 0.15
		_part(root, "box", Vector3(STAIR_HALF * 2.0, top - lower + 0.6, run + 0.02), Vector3(AXIS, (top + lower - 0.6) * 0.5, z), mat.church)
	for side in [-1, 1]:
		var x: float = AXIS + side * (STAIR_HALF + 0.5)
		for z in range(floori(z_top - 1.0), ceili(z_top + STAIR_RUN + 1.0)):
			var ramp := _height(AXIS, z + 0.5)
			var beside := _height(AXIS + side * 7.0, z + 0.5)
			var top := maxf(ramp, beside) + 1.0
			var bottom := minf(ramp, beside) - 1.0
			_part(root, "box", Vector3(1.0, top - bottom, 1.02), Vector3(x, (top + bottom) * 0.5, z + 0.5), mat.wall)
			_block(Vector2(x, z + 0.5), Vector2(0.5, 0.5))
		_street_lamp(root, Vector2(x, z_top + STAIR_RUN + 0.6), PI if side > 0 else 0.0)

# --- Summit: cathedral, winged statue, pavilions ----------------------------------

## Gothic cathedral facing the statue plaza (local +Z): nave and aisles under steep green
## roofs, flying buttresses, a twin-spired facade with a rose window and a pointed portal.
func _build_cathedral(root: Node3D) -> void:
	var c := _anchor(root, CATHEDRAL_AT, 0.0, TIERS[2])
	c.name = "Cathedral"
	var stone: Material = mat.church
	var roof: Material = mat.green_roof
	_part(c, "box", Vector3(12, 16, 20), Vector3(0, 7.5, -1), stone)
	_part(c, "prism", Vector3(12.8, 7.5, 20.4), Vector3(0, 19.25, -1), roof)
	for sx in [-1, 1]:
		_part(c, "box", Vector3(4, 9, 18), Vector3(sx * 8, 4, -1.5), stone)
		_part(c, "box", Vector3(4.8, 0.25, 18.4), Vector3(sx * 8.2, 9.2, -1.5), roof, Vector3(0, 0, -sx * 0.45))
		for i in 5:
			var z := -9.0 + i * 4.2
			_part(c, "box", Vector3(1.0, 11, 1.4), Vector3(sx * 10.4, 5, z), stone)
			_part(c, "spire", Vector3(0.55, 2.4, 0), Vector3(sx * 10.4, 11.7, z), stone)
			_part(c, "box", Vector3(5.3, 0.5, 0.6), Vector3(sx * 8.2, 12, z), stone, Vector3(0, 0, -sx * atan2(3.0, 4.4)))
			if i < 4:
				_lancet(c, Vector3(sx * 6.03, 12.2, z + 2.1), Vector2(1.0, 2.4), mat.glass, PI / 2.0)
				_lancet(c, Vector3(sx * 10.03, 4.4, z + 2.1), Vector2(1.0, 3.0), mat.glass, PI / 2.0)
	# Facade towers.
	for sx in [-1, 1]:
		var x: float = sx * 7.5
		_part(c, "box", Vector3(6, 25, 6), Vector3(x, 12, 8), stone)
		for cx in [-1, 1]:
			_part(c, "box", Vector3(0.8, 25, 0.8), Vector3(x + cx * 3.0, 12, 11.0), stone)
		_part(c, "box", Vector3(6.6, 0.5, 6.6), Vector3(x, 24.5, 8), mat.trim)
		for cx in [-1, 1]:
			for cz in [-1, 1]:
				_part(c, "spire", Vector3(0.5, 3.0, 0), Vector3(x + cx * 2.8, 26.2, 8 + cz * 2.8), stone)
		_part(c, "spire", Vector3(3.0, 17, 0), Vector3(x, 33.0, 8), roof)
		_lancet(c, Vector3(x, 19.5, 11.03), Vector2(1.1, 3.2), mat.dark)
		_lancet(c, Vector3(x, 10.5, 11.03), Vector2(0.9, 2.6), mat.glass)
		_lancet(c, Vector3(x + sx * 3.03, 19.5, 8), Vector2(1.1, 3.2), mat.dark, PI / 2.0)
	# Central gable, rose window and portal.
	_part(c, "box", Vector3(9, 19, 1.6), Vector3(0, 9, 10.2), stone)
	_part(c, "prism", Vector3(9, 4.5, 1.6), Vector3(0, 20.75, 10.2), stone)
	_part(c, "cylinder", Vector3(3.0, 0.3, 3.0), Vector3(0, 13.4, 11.05), mat.trim, Vector3(PI / 2.0, 0, 0))
	_part(c, "cylinder", Vector3(2.5, 0.32, 2.5), Vector3(0, 13.4, 11.06), mat.rose, Vector3(PI / 2.0, 0, 0))
	for k in 6:
		_part(c, "box", Vector3(0.12, 5.0, 0.36), Vector3(0, 13.4, 11.08), mat.trim, Vector3(0, 0, k * PI / 6.0))
	_part(c, "box", Vector3(4.4, 6.2, 0.5), Vector3(0, 3.1, 11.1), mat.trim)
	_part(c, "prism", Vector3(4.4, 2.3, 0.5), Vector3(0, 7.35, 11.1), mat.trim)
	_part(c, "box", Vector3(3.0, 5.0, 0.4), Vector3(0, 2.5, 11.2), mat.door)
	_part(c, "prism", Vector3(3.0, 1.6, 0.4), Vector3(0, 5.8, 11.2), mat.door)
	for sx in [-1, 1]:
		_banner(c, Vector3(sx * 3.4, 8.2, 11.08), 1.1, 4.4, mat.red, true)
	# Crossing flèche.
	_part(c, "box", Vector3(2.4, 2.5, 2.4), Vector3(0, 23.6, -5), stone)
	_part(c, "spire", Vector3(1.4, 12, 0), Vector3(0, 30.8, -5), roof)
	_block(CATHEDRAL_AT, Vector2(11.2, 11.2))

## The winged, hooded statue on its fountain in the summit plaza, ringed by hedges and lamps.
func _build_statue_plaza(root: Node3D) -> void:
	var base := _anchor(root, STATUE_AT, 0.0, TIERS[2])
	base.name = "WingedStatue"
	var trim: Material = mat.trim
	_part(base, "cylinder", Vector3(7.0, 0.9, 7.0), Vector3(0, 0.2, 0), trim)
	_part(base, "cylinder", Vector3(6.4, 0.1, 6.4), Vector3(0, 0.62, 0), mat.water)
	_part(base, "cylinder", Vector3(3.2, 1.6, 3.2), Vector3(0, 0.8, 0), trim)
	_part(base, "cylinder", Vector3(2.4, 2.0, 2.2), Vector3(0, 2.4, 0), mat.church)
	_part(base, "cylinder", Vector3(2.7, 0.35, 2.7), Vector3(0, 3.5, 0), trim)
	var stone: Material = mat.statue
	var y := 3.7
	# Gown, shoulders and hood in one smooth lathe; the head bows inside the hood.
	_part(base, "gown", Vector3.ONE, Vector3(0, y, 0), stone)
	_part(base, "sphere", Vector3(0.42, 0.9, 0), Vector3(0, y + 9.3, 0.3), stone)
	# Arms in wide sleeves reaching forward and down, open hands offered to the plaza.
	for side in [-1, 1]:
		# Rotated past the horizontal so the sleeve (widening toward the wrist) points forward and down.
		_part(base, "cylinder", Vector3(0.3, 2.3, 0.48), Vector3(side * 0.82, y + 7.78, 1.22), stone, Vector3(2.04, 0, -side * 0.1))
		_part(base, "box", Vector3(0.34, 0.1, 0.62), Vector3(side * 0.74, y + 7.2, 2.45), stone, Vector3(0.15, 0, -side * 0.3))
	# Wings: long primaries, secondaries and short coverts fanning up and out behind the
	# shoulders from a leading-edge bone.
	for side in [-1, 1]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 0.6, y + 8.6, -0.75)
		wing.rotation.y = side * 0.45
		base.add_child(wing)
		_part(wing, "cylinder", Vector3(0.38, 5.0, 0.2), Vector3(side * sin(0.55), cos(0.55), 0) * 2.5, stone, Vector3(0, 0, -side * 0.55))
		var layers := [[12, 0.12, 1.5, 9.5, 3.8, 0.9, 0.0], [10, 0.2, 1.4, 6.0, 2.8, 0.95, 0.15], [8, 0.3, 1.3, 3.0, 1.8, 1.05, 0.3]]
		for layer: Array in layers:
			var count: int = layer[0]
			for i in count:
				var f := float(i) / (count - 1)
				var theta := lerpf(layer[1], layer[2], f)
				var feather := snappedf(lerpf(layer[3], layer[4], pow(f, 0.8)), 0.1)
				var root_at := Vector3(side * sin(theta), cos(theta), 0) * 0.3 + Vector3(0, 0, -float(layer[6]))
				_part(wing, "feather", Vector3(layer[5], feather, 0.16), root_at, stone, Vector3(0, 0, -side * theta))
	# Hedge ring with gaps on the four paths, and lamps between.
	for k in 16:
		if k % 4 == 0: continue
		var angle := k * TAU / 16.0
		var q := STATUE_AT + Vector2(cos(angle), sin(angle)) * 12.5
		_part(root, "box", Vector3(4.7, 0.55, 1.7), Vector3(q.x, TIERS[2] + 0.2, q.y), mat.church, Vector3(0, -angle + PI / 2.0, 0))
		_part(root, "box", Vector3(4.4, 0.1, 1.4), Vector3(q.x, TIERS[2] + 0.5, q.y), Props.flat(Color("5b4632")), Vector3(0, -angle + PI / 2.0, 0))
		for b in 3:
			planter_bushes.append(STATUE_AT + Vector2(cos(angle + (b - 1) * 0.1), sin(angle + (b - 1) * 0.1)) * 12.5)
		_block(q, Vector2(1.3, 1.3))
	for k in 4:
		var angle := k * TAU / 4.0 + PI / 4.0
		_street_lamp(root, STATUE_AT + Vector2(cos(angle), sin(angle)) * 7.8, -angle, TIERS[2])
	_block(STATUE_AT, Vector2(4.6, 4.6))
	for k in 12:
		var angle := k * TAU / 12.0
		_block(STATUE_AT + Vector2(cos(angle), sin(angle)) * 6.0, Vector2(1.1, 1.1))

## Small colonnaded halls with green roofs flanking the statue plaza (local +Z faces it).
func _build_pavilions(root: Node3D) -> void:
	for spec: Array in PAVILIONS:
		var at: Vector2 = spec[0]
		var node := _anchor(root, at, spec[1], TIERS[2])
		_part(node, "box", Vector3(7, 0.5, 5.6), Vector3(0, 0.0, 0), mat.trim)
		_part(node, "box", Vector3(7, 5.0, 3.4), Vector3(0, 2.5, -1.0), mat.church)
		for k in 4:
			_part(node, "cylinder", Vector3(0.28, 4.6, 0.28), Vector3(-2.7 + k * 1.8, 2.5, 2.2), mat.trim)
		_part(node, "box", Vector3(7.4, 0.6, 5.8), Vector3(0, 5.2, 0), mat.trim)
		_part(node, "prism", Vector3(6.2, 2.4, 7.8), Vector3(0, 6.7, 0), mat.green_roof, Vector3(0, PI / 2.0, 0))
		_banner(node, Vector3(0, 3.0, 0.72), 1.0, 2.6, mat.red, true)
		_block(at, Vector2(3.6, 3.6))

# --- Knights' keep ----------------------------------------------------------------

## The knights' headquarters: a crenellated stone hall with corner towers and a donjon,
## its bannered portal facing the main street (local +Z, east).
func _build_keep(root: Node3D) -> void:
	var keep := _anchor(root, KEEP_AT, PI / 2.0, TIERS[1])
	keep.name = "KnightsKeep"
	var stone: Material = mat.keep
	_part(keep, "box", Vector3(16, 17, 22), Vector3(0, 7.5, 0), stone)
	_part(keep, "box", Vector3(16.6, 0.7, 22.6), Vector3(0, 15.2, 0), stone)
	for k in 6:
		var t := -6.5 + k * 2.6
		for edge in [Vector3(t, 0, 11.1), Vector3(t, 0, -11.1)]:
			_part(keep, "box", Vector3(1.1, 1.3, 0.8), Vector3(0, 16.65, 0) + edge, stone)
	for k in 8:
		var t := -9.6 + k * 2.75
		for edge in [Vector3(8.1, 0, t), Vector3(-8.1, 0, t)]:
			_part(keep, "box", Vector3(0.8, 1.3, 1.1), Vector3(0, 16.65, 0) + edge, stone)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var t := Vector3(sx * 8, 0, sz * 11)
			_part(keep, "box", Vector3(5.5, 22, 5.5), t + Vector3(0, 10, 0), stone)
			_part(keep, "box", Vector3(6.1, 0.7, 6.1), t + Vector3(0, 20.3, 0), stone)
			for m in [Vector3(2.4, 0, 2.4), Vector3(-2.4, 0, 2.4), Vector3(2.4, 0, -2.4), Vector3(-2.4, 0, -2.4), Vector3(0, 0, 2.6), Vector3(0, 0, -2.6), Vector3(2.6, 0, 0), Vector3(-2.6, 0, 0)]:
				_part(keep, "box", Vector3(1.0, 1.3, 1.0), t + m + Vector3(0, 21.6, 0), stone)
			for wy in [7.0, 13.0]:
				_lancet(keep, t + Vector3(0, wy, sz * 2.78), Vector2(0.7, 1.4), mat.glass, 0.0 if sz > 0 else PI)
	# Donjon with the order's flag.
	_part(keep, "box", Vector3(8, 9, 9), Vector3(0, 19.5, -2), stone)
	for m in 4:
		_part(keep, "box", Vector3(1.0, 1.2, 0.8), Vector3(-3.0 + m * 2.0, 24.6, 2.4), stone)
		_part(keep, "box", Vector3(1.0, 1.2, 0.8), Vector3(-3.0 + m * 2.0, 24.6, -6.4), stone)
	_part(keep, "cylinder", Vector3(0.1, 6.0, 0.1), Vector3(0, 27.0, -2), mat.iron)
	_part(keep, "box", Vector3(0.06, 1.6, 2.6), Vector3(0, 29.0, -0.7), mat.red)
	# Windows along every face.
	for wy in [5.0, 9.5]:
		for k in 4:
			var t := -4.5 + k * 3.0
			if absf(t) > 2.0:
				_lancet(keep, Vector3(t, wy, 11.03), Vector2(0.9, 1.7), mat.glass)
			_lancet(keep, Vector3(t, wy, -11.03), Vector2(0.9, 1.7), mat.glass, PI)
		for k in 5:
			var t := -6.0 + k * 3.0
			_lancet(keep, Vector3(8.03, wy, t), Vector2(0.9, 1.7), mat.glass, PI / 2.0)
			_lancet(keep, Vector3(-8.03, wy, t), Vector2(0.9, 1.7), mat.glass, -PI / 2.0)
	# Portal.
	_part(keep, "box", Vector3(4.4, 5.2, 0.5), Vector3(0, 2.6, 11.1), mat.trim)
	_part(keep, "prism", Vector3(4.4, 1.9, 0.5), Vector3(0, 6.15, 11.1), mat.trim)
	_part(keep, "box", Vector3(3.0, 4.4, 0.4), Vector3(0, 2.2, 11.2), mat.door)
	_part(keep, "prism", Vector3(3.0, 1.3, 0.4), Vector3(0, 5.05, 11.2), mat.door)
	for sx in [-1, 1]:
		_banner(keep, Vector3(sx * 3.6, 9.0, 11.08), 1.6, 6.5, mat.red, true)
	_block(KEEP_AT, Vector2(13.9, 10.9))

# --- Lower town -------------------------------------------------------------------

## Stone windmill tower with a timber cap and four great canvas sails turning in the wind.
func _mill(root: Node3D, at: Vector2, yaw_angle: float) -> void:
	var node := _anchor(root, at, yaw_angle)
	node.name = "Windmill"
	_part(node, "cylinder", Vector3(3.4, 23, 2.8), Vector3(0, 10.5, 0), mat.wall)
	_part(node, "cylinder", Vector3(3.1, 0.6, 3.1), Vector3(0, 21.6, 0), mat.timber)
	_part(node, "cone", Vector3(3.6, 4.8, 0), Vector3(0, 24.3, 0), Props.flat(Color("b9502f"), 0.8))
	_part(node, "box", Vector3(1.3, 2.4, 0.3), Vector3(0, 1.2, 3.3), mat.door)
	for wy in [6.5, 12.0, 17.0]:
		_lancet(node, Vector3(0, wy, 3.05 - wy * 0.02), Vector2(0.7, 1.2), mat.glass)
	var hub := Node3D.new()
	hub.position = Vector3(0, MILL_HUB, 3.2)
	hub.set_meta("dynamic", true)
	node.add_child(hub)
	_part(hub, "cylinder", Vector3(0.6, 1.4, 0.6), Vector3.ZERO, mat.timber, Vector3(PI / 2.0, 0, 0))
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = k * PI / 2.0 + 0.3
		arm.position.z = 0.7
		hub.add_child(arm)
		_part(arm, "box", Vector3(0.36, MILL_SAIL, 0.24), Vector3(0, MILL_SAIL * 0.5, 0), mat.timber)
		_part(arm, "box", Vector3(2.9, MILL_SAIL * 0.76, 0.06), Vector3(1.6, MILL_SAIL * 0.58, 0.1), Props.flat(Color("f3ecdc")))
		for b in 5:
			_part(arm, "box", Vector3(3.1, 0.1, 0.12), Vector3(1.55, MILL_SAIL * (0.22 + b * 0.18), 0.0), mat.wood)
	spinning.append(hub)
	_block(at, Vector2(3.4, 3.4))

## Rows of half-timbered houses back to back between the north-running lanes, on every
## terrace, wherever a lot is clear of plazas, stairs and landmarks.
func _build_houses(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 303
	var count := 0
	for k in LANES.size() - 1:
		var lo: float = AXIS + LANES[k] + (4.0 if LANES[k] == 0.0 else 2.2)
		var hi: float = AXIS + LANES[k + 1] - (4.0 if LANES[k + 1] == 0.0 else 2.2)
		for row in 2:
			var z := 98.0
			while z < 268.0:
				var w := rng.randf_range(6.0, 8.5)
				var d := rng.randf_range(5.6, 6.8)
				var floors := 3 if rng.randf() < 0.3 else 2
				var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
				var at := Vector2(lo + d * 0.5 + 0.5 if row == 0 else hi - d * 0.5 - 0.5, z + w * 0.5)
				if _lot_free(at, Vector2(d * 0.5 + 0.6, w * 0.5 + 0.4)):
					_townhouse(root, at, -PI / 2.0 if row == 0 else PI / 2.0, w, d, floors, roof, rng)
					count += 1
					z += w + rng.randf_range(0.6, 1.6)
				else:
					z += 1.5
	print("[JRPGWorld3] Houses: ", count)

func _lot_free(center: Vector2, half: Vector2) -> bool:
	var tier := -1
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var p := center + Vector2(sx * half.x, sz * half.y)
			if _wall_sdf(p) > -4.0: return false
			var r := p.distance_to(APEX)
			if absf(r - R1) < 3.0 or absf(r - R2) < 3.0: return false
			if tier >= 0 and _tier_at(p) != tier: return false
			tier = _tier_at(p)
	var lot := Rect2(center - half, half * 2.0)
	var reserved: Array[Rect2] = [GATE_PLAZA, Rect2(150, 148, 33, 28), Rect2(186, 88, 28, 30),
		Rect2(AXIS - 12.0, APEX.y + R1 - STAIR_RUN * 0.5 - 4.0, 24, STAIR_RUN + 10.0),
		Rect2(AXIS - 12.0, APEX.y + R2 - STAIR_RUN * 0.5 - 3.0, 24, STAIR_RUN + 6.0)]
	if tier == 0: reserved.append(Rect2(120, CROSS_Z - 3.5, 160, 7))
	for spec: Array in PAVILIONS: reserved.append(Rect2(spec[0] - Vector2(5, 5), Vector2(10, 10)))
	for rect in reserved:
		if rect.intersects(lot): return false
	for circle: Array in [[STATUE_AT, 17.0], [FOUNTAIN_AT, 12.0]]:
		if _rect_sdf(circle[0], center, half) < circle[1]: return false
	for mill: Array in MILLS:
		if _rect_sdf(mill[0], center, half) < 6.0: return false
		# The sails turn in a vertical disc just in front of the tower.
		var yaw_angle: float = mill[1]
		var forward := Vector2(sin(yaw_angle), cos(yaw_angle))
		var offset: Vector2 = center - (mill[0] + forward * 3.9)
		var reach := maxf(half.x, half.y)
		if absf(offset.dot(forward)) < 2.5 + reach and absf(offset.dot(Vector2(forward.y, -forward.x))) < MILL_SAIL + 1.0 + reach: return false
	for tree: Vector2 in CITY_TREES:
		if _rect_sdf(tree, center, half) < 3.5: return false
	return true

## Half-timbered town house, ridge along local X and front (+Z) on the lane: a stone ground
## floor with the door, jettied plaster upper floors with braced timber framing and
## flower boxes, and a steep tiled roof over plaster gables with a chimney and dormer.
func _townhouse(parent: Node3D, at: Vector2, yaw_angle: float, w: float, d: float, floors: int, roof: Color, rng: RandomNumberGenerator) -> void:
	var root := _anchor(parent, at, yaw_angle)
	var plaster := Props.flat(PLASTERS[rng.randi() % PLASTERS.size()])
	var timber: Material = mat.timber
	var ground := 3.0
	_part(root, "box", Vector3(w, ground + 1.5, d), Vector3(0, ground * 0.5 - 0.75, 0), mat.house)
	var door_x := rng.randf_range(-w * 0.2, w * 0.2)
	_part(root, "box", Vector3(1.3, 2.3, 0.12), Vector3(door_x, 1.15, d * 0.5 + 0.04), mat.door)
	_part(root, "box", Vector3(1.7, 0.2, 0.3), Vector3(door_x, 2.42, d * 0.5 + 0.1), mat.trim)
	for sx in [-1, 1]:
		var wx: float = door_x + sx * 2.1
		if absf(wx) < w * 0.5 - 0.8: _pane(root, Vector3(wx, 1.6, d * 0.5), Vector2(1.0, 1.1), false)
	var y := ground
	var ow := w
	var od := d
	for f in floors - 1:
		# Each upper floor juts out over the one below.
		ow += 0.5
		od += 0.5
		_part(root, "box", Vector3(ow, 2.8, od), Vector3(0, y + 1.4, 0), plaster)
		_part(root, "box", Vector3(ow + 0.1, 0.26, od + 0.1), Vector3(0, y + 0.13, 0), timber)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_part(root, "box", Vector3(0.24, 2.8, 0.24), Vector3(sx * ow * 0.5, y + 1.4, sz * od * 0.5), timber)
		var bays := maxi(3, int(ow / 2.2))
		var bay := ow / bays
		for sz in [-1, 1]:
			var face: float = sz * (od * 0.5 + 0.03)
			for i in range(1, bays):
				_part(root, "box", Vector3(0.18, 2.8, 0.06), Vector3(-ow * 0.5 + bay * i, y + 1.4, face), timber)
			for i in bays:
				var cx := -ow * 0.5 + bay * (i + 0.5)
				if i == 0 or i == bays - 1:
					var brace := atan2(bay, 2.5)
					var lean := 1.0 if i == 0 else -1.0
					_part(root, "box", Vector3(0.16, sqrt(bay * bay + 6.25), 0.06), Vector3(cx, y + 1.4, face), timber, Vector3(0, 0, lean * brace))
				else:
					_pane(root, Vector3(cx, y + 1.5, face - sz * 0.03), Vector2(0.9, 1.1), rng.randf() < 0.5, sz < 0)
		for sx in [-1, 1]:
			_pane(root, Vector3(sx * ow * 0.5, y + 1.5, 0), Vector2(0.9, 1.1), false, false, sx)
		y += 2.8
	_part(root, "box", Vector3(ow + 0.1, 0.24, od + 0.1), Vector3(0, y + 0.12, 0), timber)
	# Roof: plaster gable fill under two tiled planes.
	var rise := od * 0.8
	var half := od * 0.5
	var pitch_angle := atan2(rise, half)
	var eave := 0.6
	var slope := (half + eave) / cos(pitch_angle)
	var roof_mat := Props.flat(roof, 0.8)
	_part(root, "prism", Vector3(od, rise, ow), Vector3(0, y + rise * 0.5, 0), plaster, Vector3(0, PI / 2.0, 0))
	for sz in [-1, 1]:
		var center := Vector3(0, y + rise - (half + eave) * tan(pitch_angle) * 0.5 + 0.12, sz * (half + eave) * 0.5)
		_part(root, "box", Vector3(ow + 0.9, 0.24, slope), center, roof_mat, Vector3(sz * pitch_angle, 0, 0))
	_part(root, "box", Vector3(ow + 0.9, 0.22, 0.4), Vector3(0, y + rise + 0.12, 0), roof_mat)
	var chimney_x := w * 0.28 * (1.0 if rng.randf() < 0.5 else -1.0)
	_part(root, "box", Vector3(0.75, rise * 0.7 + 1.0, 0.75), Vector3(chimney_x, y + rise * 0.65, -half * 0.35), mat.house)
	if rng.randf() < 0.45:
		var dz := half * 0.45
		var dy := y + rise * (1.0 - dz / half) + 0.2
		_part(root, "box", Vector3(1.5, 1.4, 1.6), Vector3(-chimney_x * 0.6, dy + 0.3, dz + 0.2), plaster)
		_part(root, "box", Vector3(0.8, 0.8, 0.08), Vector3(-chimney_x * 0.6, dy + 0.3, dz + 1.02), mat.glass)
		_part(root, "prism", Vector3(1.8, 0.9, 1.9), Vector3(-chimney_x * 0.6, dy + 1.45, dz + 0.2), roof_mat)
	var corners := [Vector2(w, d), Vector2(-w, d), Vector2(w, -d), Vector2(-w, -d)]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c: Vector2 in corners:
		var r := (c * 0.5 + c.sign() * 0.2).rotated(-yaw_angle)
		lo = lo.min(r)
		hi = hi.max(r)
	obstacles.append(Rect2(at + lo, hi - lo))

## Framed window with a cross mullion on a face of the parent: front/back (normal ±Z, `back`
## for -Z) or a side wall (`side` = ±1, normal ±X). Optional flower box below.
func _pane(root: Node3D, at: Vector3, size: Vector2, flowers: bool, back := false, side := 0) -> void:
	var rot := Vector3(0, PI / 2.0 * side if side != 0 else (PI if back else 0.0), 0)
	var out := Vector3(side, 0, 0) if side != 0 else Vector3(0, 0, -1.0 if back else 1.0)
	_part(root, "box", Vector3(size.x + 0.26, size.y + 0.26, 0.06), at + out * 0.02, mat.trim, rot)
	var lit := int(absf(at.x * 13.0 + at.y * 7.0 + at.z * 3.0)) % 5 < 2
	_part(root, "box", Vector3(size.x, size.y, 0.06), at + out * 0.04, mat.glass_lit if lit else mat.glass, rot)
	_part(root, "box", Vector3(0.07, size.y, 0.05), at + out * 0.07, mat.trim, rot)
	_part(root, "box", Vector3(size.x, 0.07, 0.05), at + out * 0.07, mat.trim, rot)
	if flowers:
		var sill := at + out * 0.2 + Vector3(0, -size.y * 0.5 - 0.18, 0)
		_part(root, "box", Vector3(size.x + 0.2, 0.26, 0.32), sill, mat.wood, rot)
		var bloom: Material = Props.flat([Color("e2475a"), Color("f08aa8"), Color("f2c94c"), Color("e86a3a")][int(absf(at.x * 7.0 + at.z * 3.0)) % 4])
		_part(root, "box", Vector3(size.x + 0.1, 0.22, 0.3), sill + Vector3(0, 0.2, 0), bloom, rot)

## Plazas, lamps, the fountain, market stalls and bunting over the main street.
func _build_streets(root: Node3D) -> void:
	# Main street lamps, staggered, lanterns over the cobbles.
	var z := 204.0
	var side := -1.0
	while z < 264.0:
		if absf(z - CROSS_Z) > 4.0 and not GATE_PLAZA.grow(-1.0).has_point(Vector2(AXIS, z)):
			_street_lamp(root, Vector2(AXIS + side * 3.6, z), 0.0 if side < 0 else PI)
		z += 9.0
		side = -side
	for k in 4:
		var angle := k * TAU / 4.0 + PI / 4.0
		_street_lamp(root, FOUNTAIN_AT + Vector2(cos(angle), sin(angle)) * 8.0, -angle + PI)
	_tiered_fountain(root, FOUNTAIN_AT, TIERS[1])
	_tiered_fountain(root, Vector2(AXIS, CROSS_Z), TIERS[0], 0.6)
	for at: Vector2 in [Vector2(193.5, 258.0), Vector2(206.5, 258.0), Vector2(191.0, 251.0), Vector2(209.0, 251.0)]:
		_stall(root, at, PI / 2.0 if at.x < AXIS else -PI / 2.0, [Color("c8423a"), Color("3f74b8"), Color("e0a83a"), Color("5a9a4a")][int(at.y + at.x) % 4])
	for bz in [212.0, 224.0, 244.0]:
		_bunting(root, Vector3(AXIS - 4.6, TIERS[0] + 6.2, bz), Vector3(AXIS + 4.6, TIERS[0] + 6.2, bz))
	# Masts at the gate plaza's corners carry bunting across it.
	var masts: Array[Vector3] = []
	for at: Vector2 in [Vector2(185.5, 249.0), Vector2(214.5, 249.0), Vector2(214.5, 265.5), Vector2(185.5, 265.5)]:
		_part(root, "cylinder", Vector3(0.13, 7.4, 0.1), Vector3(at.x, TIERS[0] + 3.7, at.y), mat.wood)
		_block(at, Vector2(0.3, 0.3))
		masts.append(Vector3(at.x, TIERS[0] + 7.1, at.y))
	for k in 4: _bunting(root, masts[k], masts[(k + 1) % 4])
	_bunting(root, masts[0], masts[2])
	_bunting(root, masts[1], masts[3])
	# Barrels and crates by the gate plaza and the cross street.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 88
	for at: Vector2 in [Vector2(186.5, 264.0), Vector2(187.4, 265.2), Vector2(213.0, 264.5), Vector2(205.8, 236.4), Vector2(214.0, 229.0), Vector2(186.0, 235.5)]:
		var barrel := _anchor(root, at, rng.randf() * TAU)
		if rng.randf() < 0.5:
			_part(barrel, "cylinder", Vector3(0.42, 1.0, 0.42), Vector3(0, 0.5, 0), mat.wood)
			for y in [0.2, 0.8]: _part(barrel, "cylinder", Vector3(0.44, 0.07, 0.44), Vector3(0, y, 0), mat.iron)
		else:
			_part(barrel, "box", Vector3(0.9, 0.8, 0.9), Vector3(0, 0.4, 0), mat.wood)
			_part(barrel, "box", Vector3(0.6, 0.55, 0.6), Vector3(0.1, 1.07, 0.05), mat.wood, Vector3(0, 0.4, 0))
		_block(at, Vector2(0.5, 0.5))

func _tiered_fountain(root: Node3D, at: Vector2, height: float, scale_factor := 1.0) -> void:
	var node := _anchor(root, at, 0.0, height)
	node.scale = Vector3.ONE * scale_factor
	var trim: Material = mat.trim
	_part(node, "cylinder", Vector3(4.2, 0.8, 4.2), Vector3(0, 0.3, 0), trim)
	_part(node, "cylinder", Vector3(3.8, 0.1, 3.8), Vector3(0, 0.66, 0), mat.water)
	_part(node, "cylinder", Vector3(0.5, 2.4, 0.6), Vector3(0, 1.5, 0), trim)
	_part(node, "cylinder", Vector3(1.6, 0.35, 0.9), Vector3(0, 2.7, 0), trim)
	_part(node, "cylinder", Vector3(1.45, 0.06, 1.45), Vector3(0, 2.86, 0), mat.water)
	_part(node, "cylinder", Vector3(0.28, 1.2, 0.34), Vector3(0, 3.4, 0), trim)
	_part(node, "sphere", Vector3(0.4, 0.8, 0), Vector3(0, 4.1, 0), mat.gold)
	_block(at, Vector2(3.6, 3.6) * scale_factor)

## Market stall: counter toward local +Z under a striped awning, with produce and crates.
func _stall(root: Node3D, at: Vector2, yaw_angle: float, cloth: Color) -> void:
	var node := _anchor(root, at, yaw_angle)
	var wood: Material = mat.wood
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(node, "box", Vector3(0.16, 2.7 if sz < 0 else 2.3, 0.16), Vector3(sx * 1.4, 1.35 if sz < 0 else 1.15, sz * 0.9), wood)
	_part(node, "box", Vector3(3.0, 0.95, 0.8), Vector3(0, 0.48, 0.55), wood)
	var cloth_mat := Props.flat(cloth, 0.85)
	for k in 6:
		_part(node, "box", Vector3(0.56, 0.06, 2.5), Vector3(-1.4 + 0.56 * k, 2.5, 0.1), cloth_mat if k % 2 == 0 else mat.white, Vector3(0.2, 0, 0))
	for k in 5:
		var goods: Material = Props.flat([Color("d8443a"), Color("f0c04a"), Color("8cc04a"), Color("e8873a"), Color("b46ad0")][k])
		_part(node, "sphere", Vector3(0.24, 0.4, 0), Vector3(-1.1 + k * 0.55, 1.08, 0.5), goods)
	_part(node, "box", Vector3(0.8, 0.6, 0.8), Vector3(1.0, 0.3, -0.5), wood, Vector3(0, 0.3, 0))
	_block(at, Vector2(1.6, 1.6))

## A sagging string of pennants between two points.
func _bunting(root: Node3D, a: Vector3, b: Vector3) -> void:
	var count := maxi(2, int(a.distance_to(b) / 0.75))
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var rot_y := atan2(-flat.y, flat.x)
	var previous := a
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t) - Vector3(0, 0.9 * (1.0 - pow(2.0 * t - 1.0, 2.0)), 0)
		if i > 0:
			var span := p - previous
			_part(root, "box", Vector3(span.length(), 0.04, 0.04), (p + previous) * 0.5, mat.iron, Vector3(0, rot_y, atan2(span.y, Vector2(span.x, span.z).length())))
			var flag := (p + previous) * 0.5 - Vector3(0, 0.3, 0)
			_part(root, "prism", Vector3(0.48, 0.6, 0.03), flag, Props.flat(BUNTING[i % BUNTING.size()], 0.85), Vector3(0, rot_y, PI))
		previous = p

# --- Nature and dressing ----------------------------------------------------------------

## Rock slabs heaped around the island's foot, half in the water.
func _build_island_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 17
	var transforms: Array = [[], [], [], []]
	for i in WALL.size():
		var a: Vector2 = WALL[i]
		var b: Vector2 = WALL[(i + 1) % WALL.size()]
		var dir := (b - a).normalized()
		var out := Vector2(-dir.y, dir.x)
		var t := 0.0
		var length := a.distance_to(b)
		while t < length:
			var p := a + dir * t + out * rng.randf_range(4.0, 9.5)
			t += rng.randf_range(2.0, 3.4)
			if absf(p.x - AXIS) < 8.0 and p.y > GATE_Z: continue
			var h := _height(p.x, p.y)
			var size := rng.randf_range(1.6, 3.6)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.6, 1.1), size))
			transforms[rng.randi_range(0, 3)].append(Transform3D(basis, Vector3(p.x, minf(h, LAKE + 1.0) - size * 0.4, p.y)))
	var root := Node3D.new()
	root.name = "IslandRocks"
	add_child(root)
	for v in 4:
		_multimesh(root, Props.mesh("rock", v), transforms[v], Props.rock_material(Color("8a929e"), 0.6), "IslandRock_%d" % v)

## Toon groves on the shore meadows and bluffs, and garden trees inside the walls.
func _build_city_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 5
	var chunks: Dictionary = {}
	var spacing := 5.0
	var z := 0.0
	while z < SIZE:
		var x := 0.0
		while x < SIZE:
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.85, 1.2)
			var angle := rng.randf() * TAU
			x += spacing
			if p.x < 3.0 or p.y < 3.0 or p.x > SIZE - 3.0 or p.y > SIZE - 3.0: continue
			var h := _height(p.x, p.y)
			if _basin_e(p) < 1.1 or h < LAKE + 1.5 or _path_distance(p.x, p.y) < 3.0: continue
			if p.distance_to(SPAWN) < 11.0 or (absf(p.x - AXIS) < 16.0 and p.y > 300.0): continue
			if p.x > 100.0 and p.x < 300.0 and p.y > 60.0 and p.y < 300.0 and _wall_sdf(p) < 10.0: continue
			if _slope(p.x, p.y) > 0.8 or _blocked(p, 1.0): continue
			var grove := smoothstep(0.08, 0.4, noise.get_noise_2d(p.x * 1.4 + 911.0, p.y * 1.4 - 45.0))
			if roll >= 0.07 + 0.6 * grove: continue
			var asset: String
			if h > 27.0: asset = ["toon_spruce", "toon_fir", "toon_round"][mini(int(pick * 3.0), 2)]
			else: asset = ["toon_round", "toon_oak", "toon_tall", "toon_umbrella", "toon_round"][mini(int(pick * 5.0), 4)]
			_add_tree(chunks, asset, p, h, size, angle)
		z += spacing
	for i in CITY_TREES.size():
		var p: Vector2 = CITY_TREES[i]
		_add_tree(chunks, "toon_round" if i % 2 == 0 else "toon_oak", p, _height(p.x, p.y), 0.9, i * 1.7)
	var bushes: Array = []
	for i in planter_bushes.size():
		var p := planter_bushes[i]
		bushes.append(Transform3D(Basis(Vector3.UP, i * 2.3).scaled(Vector3.ONE * 0.95), Vector3(p.x, TIERS[2] + 0.45, p.y)))
	var planters := Node3D.new()
	planters.name = "PlanterBushes"
	add_child(planters)
	Vegetation.add_bush_chunk(planters, "bush_a", bushes)
	# The great tree by the bridge's south end.
	_add_tree(chunks, "toon_oak", Vector2(186, 323), _height(186, 323), 1.35, 0.4)
	var root := Node3D.new()
	root.name = "Forest"
	add_child(root)
	for key: Vector2i in chunks:
		var chunk := Node3D.new()
		chunk.name = "Forest_%d_%d" % [key.x, key.y]
		root.add_child(chunk)
		for asset: String in chunks[key]:
			Vegetation.add_tree_chunk(chunk, asset, chunks[key][asset])

func _add_tree(chunks: Dictionary, asset: String, p: Vector2, h: float, size: float, angle: float) -> void:
	var key := Vegetation.chunk_key(asset, p)
	if not chunks.has(key): chunks[key] = {}
	if not chunks[key].has(asset): chunks[key][asset] = []
	chunks[key][asset].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * size), Vector3(p.x, h - 0.1, p.y)))
	obstacles.append(Rect2(p - Vector2(0.5, 0.5) * size, Vector2.ONE * size))
	cover_cells[world_position_to_cell(Vector3(p.x, 0, p.y))] = "TREE"

func _blocked(p: Vector2, margin: float) -> bool:
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), []):
		if rect.grow(margin).has_point(p): return true
	return false

## Grass carpet and flower drifts on the open ground outside the walls and on the ledges.
func _build_city_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 91
	var root := Node3D.new()
	root.name = "Meadow"
	add_child(root)
	var cell := int(Meadow.CELL)
	var patches := 0
	for cz in range(0, SIZE, cell):
		for cx in range(0, SIZE, cell):
			var carpet: Array = []
			var carpet_normals: Array = []
			var flowers: Array = []
			var flower_normals: Array = []
			for z in range(cz, cz + cell):
				for x in range(cx, cx + cell):
					var px := x + 0.5 + rng.randf_range(-0.3, 0.3)
					var pz := z + 0.5 + rng.randf_range(-0.3, 0.3)
					var yaw_angle := rng.randf() * TAU
					var jitter := rng.randf_range(0.85, 1.15)
					var bloom := rng.randf()
					var h := _height(px, pz)
					if h < LAKE + 0.4 or _path_distance(px, pz) < -0.1 or _slope(px, pz) > 0.7: continue
					var p := Vector2(px, pz)
					if px > 110.0 and px < 290.0 and pz > 70.0 and pz < 290.0 and _wall_sdf(p) < 1.8: continue
					if absf(px - AXIS) < 4.5 and pz > BRIDGE_Z.x and pz < BRIDGE_Z.y + 2.0: continue
					if absf(px - AXIS) < 15.0 and pz > GATE_Z and pz < GATE_Z + 7.0: continue
					var tall := lerpf(0.3, 0.7, smoothstep(-0.1, 0.4, noise.get_noise_2d(px * 1.7 - 150.0, pz * 1.7 + 60.0)))
					tall *= lerpf(0.5, 1.0, smoothstep(0.0, 2.5, _path_distance(px, pz)))
					var n := _ground_normal(px, pz)
					carpet.append(Meadow.patch_transform(Vector3(px, h - 0.04, pz), n, tall * jitter, yaw_angle))
					carpet_normals.append(n)
					var drift := smoothstep(0.1, 0.45, noise.get_noise_2d(px * 2.2 + 70.0, pz * 2.2 - 31.0))
					if bloom < 0.12 * drift:
						flowers.append(Transform3D(Basis(Vector3.UP, yaw_angle).scaled(Vector3.ONE * 1.4), Vector3(px, h - 0.03, pz)))
						flower_normals.append(n)
			var detail := Node3D.new()
			detail.name = "Meadow_%d_%d" % [cx, cz]
			root.add_child(detail)
			patches += carpet.size()
			Meadow.add_cell(detail, carpet, carpet_normals, "Grass")
			Vegetation.add_grass_chunk(detail, "flower_grass_a" if (cx + cz) % 20 == 0 else "flower_grass_b", flowers, flower_normals)
	print("[JRPGWorld3] Grass patches: ", patches)

func _build_city_labels(parent: Node3D) -> void:
	for entry in [["風翼の都 アウレリア", Vector2(200, 205), 40.0], ["風翼大聖堂", CATHEDRAL_AT, 50.0], ["騎士団本部", KEEP_AT, 30.0],
			["天翼の広場", STATUE_AT, 24.0], ["白石の大橋", Vector2(200, 300), 10.0], ["澄碧の湖", Vector2(85, 200), 6.0]]:
		var label := Label3D.new()
		label.text = entry[0]
		var p: Vector2 = entry[1]
		label.position = Vector3(p.x, maxf(_height(p.x, p.y), LAKE) + float(entry[2]), p.y)
		label.font_size = 42
		label.pixel_size = 0.03
		label.visibility_range_begin = 60.0
		label.modulate = Color("fff2cb")
		label.outline_modulate = Color("243e47")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

# --- Characters, camera and regions -----------------------------------------

## Two roster characters stand guard on the bridge in front of the gate.
func _spawn_gate_guards() -> void:
	if character_roster.size() < 3: return
	for i in 2:
		var guard := character_roster[1 + i].instantiate() as Node3D
		guard.name = "GateGuard%d" % (i + 1)
		add_child(guard)
		var at := Vector2(AXIS + (-2.9 if i == 0 else 2.9), GATE_Z + 6.0)
		guard.position = Vector3(at.x, _surface(at.x, at.y) + 0.05, at.y)
		var animation_player: AnimationPlayer = guard.animation_player
		if animation_player and animation_player.has_animation("idle"):
			animation_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			animation_player.play("idle")
		npcs.append({"actor": guard, "data": {
			"id": "guard_" + guard.character_id, "name": "城門の衛兵 " + guard.display_name,
			"lines": ["ようこそ、風翼の都アウレリアへ。", "大通りを上れば騎士団本部、さらに階段の上が天翼の広場と大聖堂だ。"]
		}})

func _city_shot(shot_name: String) -> void:
	var shot: Array = CITY_SHOTS[shot_name]
	var from: Vector3 = shot[0]
	from.y += maxf(_surface(from.x, from.z), LAKE)
	var direction := ((shot[1] as Vector3) - from).normalized()
	overview = true
	distance = 20.0
	focus = from + direction * distance
	yaw = atan2(-direction.x, -direction.z)
	pitch = asin(-direction.y)
	_update_camera()

func _preset(index: int) -> void:
	match index:
		1: _city_shot("overview")
		2: _city_shot("street")
		3: _city_shot("plaza")
		4: _city_shot("gate")
		5: _city_shot("bridge")

func _region() -> String:
	var p := Vector2(player.position.x, player.position.z)
	if absf(p.x - AXIS) < 5.0 and p.y > BRIDGE_Z.x and p.y < BRIDGE_Z.y: return "白石の大橋"
	var sdf := _wall_sdf(p)
	if sdf < 0.0:
		if Rect2(CATHEDRAL_AT - Vector2(13, 13), Vector2(26, 28)).has_point(p): return "風翼大聖堂"
		match _tier_at(p):
			2: return "天翼の広場"
			1: return "騎士団本部" if p.distance_to(KEEP_AT) < 22.0 else "騎士の広場"
		return "城門広場" if GATE_PLAZA.grow(4.0).has_point(p) else "下町通り"
	if sdf < 12.0: return "城壁の外縁"
	if _basin_e(p) < 1.3: return "澄碧の湖畔"
	if _height(p.x, p.y) > 26.0: return "風見の断崖"
	return "湖畔の草原"

func _setup_hud() -> void:
	super._setup_hud()
	for label: Label in hud.find_children("*", "Label", true, false):
		if label.text.begins_with("WASD"):
			label.text = label.text.replace("5 : 絶景（見晴らしの丘）　F3 : バイオーム表示　", "5 : 絶景（白石の大橋）　")

## No biome map here: the terrain panel shows heights and walkability only.
func _update_terrain_hud() -> void:
	var p: Vector3 = player.position
	var cell := world_position_to_cell(p)
	terrain_text.text = "Region: %s\nCell: (%d, %d)\nHeight: %.2fm\nLogical Height: %.0fm\nSlope: %.2f\nWalkable: %s" % [
		_region(), cell.x, cell.y, get_gameplay_height(p.x, p.z), get_logical_height(p.x, p.z), get_slope_at(p.x, p.z), str(is_walkable_at(p.x, p.z))]

func _set_biome_debug(_on: bool) -> void:
	pass

func _process(delta: float) -> void:
	super._process(delta)
	if field_weather: (mat.glass_lit as StandardMaterial3D).emission_energy_multiplier = [0.0, 0.0, 0.5, 1.5][field_weather.time_index]
	if mode == "explore" and prompt_text and not prompt_text.text.begins_with("E /"):
		prompt_text.text = "目標 : 白石の大橋を渡って城門をくぐり、天翼の広場の大聖堂を目指そう"
