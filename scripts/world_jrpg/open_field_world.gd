extends "res://scripts/world_jrpg/world.gd"
## JRPGWorldSample2: JRPGWorldSample's explorer, camera, HUD, weather and input on a
## smooth open-field map (crag castle and its walled town, windmill hill, ruins, snow peaks).
## Only the map is replaced; one explorer (switchable through character_roster) roams it
## with no NPCs or encounters.
const Props = preload("res://scripts/world_jrpg/open_field_props.gd")
const TERRAIN_SHADER = preload("res://scripts/world_jrpg/open_field_terrain.gdshader")
const LAKE_SHADER = preload("res://scripts/world_jrpg/open_field_water.gdshader")
const LAKE := 10.0
const LAKE_CENTER := Vector2(205, 150)
const LAKE_RADIUS := Vector2(100, 64)
## The castle crowns a rocky crag on the lake's south shore; its walled town runs
## down the slope below it, with farmland beyond the gate.
const CRAG := Vector2(205, 121)
const CRAG_TOP := 44.0
const TOWN_RECT := Rect2(180, 146, 50, 54)
const TOWN_PLAZA := Vector2(205, 178)
const SPAWN_HILL := Vector2(150, 305)
const VILLAGE := Vector2(325, 262)
const RUINS := Vector2(75, 225)
## Mesas with cliff edges: center, half extents, top height.
const MESAS := [
	[Vector2(325, 255), Vector2(42, 35), 32.0],
	[Vector2(75, 225), Vector2(32, 24), 27.0],
	[CRAG, Vector2(19, 17), CRAG_TOP],
]
## Ramps cut into the mesa cliffs: start, end (on top), half width, mesa index.
const RAMPS := [
	[Vector2(258, 298), Vector2(295, 275), 4.5, 0],
	[Vector2(126, 262), Vector2(96, 237), 4.0, 1],
	[Vector2(205, 171), Vector2(205, 136), 3.0, 2],
]
## Dirt roads: half width, control points (smoothed with Catmull-Rom).
const PATHS := [
	[2.3, [Vector2(150, 300), Vector2(158, 290), Vector2(172, 276), Vector2(188, 258), Vector2(200, 240), Vector2(205, 228), Vector2(205, 214), Vector2(205, 204)]],
	[1.9, [Vector2(200, 240), Vector2(222, 252), Vector2(240, 272), Vector2(250, 290), Vector2(258, 298), Vector2(276, 287), Vector2(295, 275), Vector2(312, 265), Vector2(317, 263.5)]],
	[1.7, [Vector2(172, 276), Vector2(150, 268), Vector2(126, 262), Vector2(111, 250), Vector2(96, 237), Vector2(78, 226)]],
	[1.3, [Vector2(150, 300), Vector2(141, 313), Vector2(137, 330)]],
	# Main street: town gate, plaza, then the ramp up to the castle gate.
	[2.6, [Vector2(205, 206), Vector2(205, 128)]],
	[1.5, [Vector2(183, 190), Vector2(227, 190)]],
	[1.4, [Vector2(184, 160), Vector2(226, 160)]],
	[1.3, [Vector2(205, 211), Vector2(190, 214), Vector2(172, 218)]],
	[1.3, [Vector2(205, 211), Vector2(220, 214), Vector2(238, 218)]],
]
## Crop fields outside the town walls: center, half extents.
const FIELDS := [
	[Vector2(184, 226), Vector2(8, 6)], [Vector2(224, 226), Vector2(8, 6)],
	[Vector2(174, 240), Vector2(6, 5)], [Vector2(232, 240), Vector2(7, 5)],
]
## Cobbled plazas: center, radius.
const PLAZAS := [[VILLAGE, 8.5], [CRAG, 10.0], [TOWN_PLAZA, 8.0], [RUINS, 10.0]]
## Open ground kept free of trees and boulders: center, radius.
const CLEARINGS := [[SPAWN_HILL, 9.0], [Vector2(150, 300), 7.0], [Vector2(166, 279), 15.0], [Vector2(186, 255), 13.0], [CRAG, 22.0], [Vector2(205, 172), 40.0], [Vector2(205, 228), 32.0], [VILLAGE, 30.0], [RUINS, 18.0]]

var path_field := PackedFloat32Array()
var path_points: Array = []
var terrain_material: ShaderMaterial
var lake_material: ShaderMaterial
var lamp_material: StandardMaterial3D
var spinning: Array[Node3D] = []
var crystal: Node3D
var conditions_key := -1
var meshes: Dictionary = {}

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	_cache_heights()
	_build_world()
	_setup_view()
	_setup_hud()
	_spawn_characters()
	_focus_player()
	# Look over the explorer's shoulder toward the lake castle.
	yaw = -0.3
	pitch = 0.3
	distance = 16.0
	_update_camera()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--view=overview": _preset(1)
		if arg == "--view=village": _preset(2)
		if arg == "--view=castle": _preset(3)
		if arg == "--view=ruins": _preset(4)
		if arg.begins_with("--time="):
			field_weather.apply_conditions(maxi(0, ["morning", "day", "evening", "night"].find(arg.get_slice("=", 1))), field_weather.weather_index)
		if arg.begins_with("--weather="):
			field_weather.apply_conditions(field_weather.time_index, maxi(0, ["clear", "rain", "cloudy", "snow"].find(arg.get_slice("=", 1))))
	if "--sample-capture" in args:
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var capture_name := "hill"
		var directory := "user://"
		for arg in args:
			if arg.begins_with("--view="): capture_name = arg.get_slice("=", 1)
			if arg.begins_with("--capture-dir="): directory = arg.get_slice("=", 1)
		for arg in args:
			if arg.begins_with("--time=") or arg.begins_with("--weather="): capture_name += "_" + arg.get_slice("=", 1)
		get_viewport().get_texture().get_image().save_png(directory.path_join("open_field_%s.png" % capture_name))
		get_tree().quit()

# --- Height field -----------------------------------------------------------

func _expanded_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _base(p)
	for i in MESAS.size():
		var m := _mesa_mask(p, i)
		if m > 0.0:
			h = maxf(h, lerpf(h, MESAS[i][2] + noise.get_noise_2d(x * 3.0, z * 3.0) * 0.6, m))
	for ramp: Array in RAMPS:
		h = _apply_ramp(p, h, ramp)
	return h

## Ground with the lake carved out and the town slope laid in, before mesas and ramps.
func _base(p: Vector2) -> float:
	var h := _apply_lake(p, _ground(p))
	var town := _town_mask(p)
	return lerpf(h, _town_height(p), town) if town > 0.0 else h

## A broad spit of land from the crag to the south shore carries the town.
func _town_mask(p: Vector2) -> float:
	var dx := absf(p.x - CRAG.x) + noise.get_noise_2d(p.x * 1.5 + 300.0, p.y * 1.5) * 4.0
	return (1.0 - smoothstep(30.0, 42.0, dx)) * smoothstep(118.0, 134.0, p.y) * (1.0 - smoothstep(228.0, 258.0, p.y))

## The town climbs gently from the shore fields toward the foot of the crag.
func _town_height(p: Vector2) -> float:
	return 13.5 + 10.5 * (1.0 - smoothstep(146.0, 232.0, p.y)) + noise.get_noise_2d(p.x * 2.0, p.y * 2.0 - 60.0) * 0.4

## Rolling meadows, the spawn hill, northern ranges and a rim of hills at the map edge.
func _ground(p: Vector2) -> float:
	var h := 17.0 + noise.get_noise_2d(p.x * 0.35, p.y * 0.35) * 11.0 + noise.get_noise_2d(p.x * 1.4 + 500.0, p.y * 1.4 - 300.0) * 1.6
	h += 12.0 * exp(-(p - SPAWN_HILL).length_squared() / 1800.0)
	# Forested foothills north of the lake; the snow peaks stand beyond the map.
	var north := 1.0 - smoothstep(-20.0, 95.0, p.y)
	var ridge := 1.0 - absf(noise.get_noise_2d(p.x * 0.9 + 77.0, p.y * 0.9))
	h += north * north * (20.0 + ridge * 24.0)
	h += 230.0 * pow(maxf(0.0, 1.0 - p.distance_to(Vector2(290, -270)) / 250.0), 1.5)
	h += 160.0 * pow(maxf(0.0, 1.0 - p.distance_to(Vector2(30, -210)) / 190.0), 1.5)
	h += 140.0 * pow(maxf(0.0, 1.0 - p.distance_to(Vector2(600, 40)) / 190.0), 1.5)
	var edge := minf(minf(p.x, SIZE - p.x), minf(SIZE - p.y, p.y + 40.0))
	var rim := 1.0 - smoothstep(-10.0, 55.0, edge)
	h += rim * rim * (26.0 + noise.get_noise_2d(p.x * 0.7, p.y * 0.7 + 99.0) * 14.0) + maxf(0.0, -edge) * 0.18
	return h

## 1 on the mesa top, 0 outside, across a ~4 m cliff band with a wobbly outline.
func _mesa_mask(p: Vector2, index: int) -> float:
	var mesa: Array = MESAS[index]
	var q: Vector2 = (p - mesa[0]).abs() - mesa[1] + Vector2(14, 14)
	var sdf := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 14.0
	if sdf > 9.0: return 0.0
	sdf += noise.get_noise_2d(p.x * 2.2 + index * 300.0, p.y * 2.2) * 6.0
	return 1.0 - smoothstep(-2.0, 2.0, sdf)

func _apply_ramp(p: Vector2, h: float, ramp: Array) -> float:
	var a: Vector2 = ramp[0]
	var ab: Vector2 = ramp[1] - a
	var width: float = ramp[2]
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := p.distance_to(a + ab * t)
	if d > width + 5.0: return h
	var ramp_height := lerpf(_base(a), MESAS[ramp[3]][2], smoothstep(0.0, 1.0, t))
	return lerpf(h, ramp_height, 1.0 - smoothstep(width, width + 5.0, d))

func _apply_lake(p: Vector2, h: float) -> float:
	var e := ((p - LAKE_CENTER) / LAKE_RADIUS).length() + noise.get_noise_2d(p.x * 0.6 + 900.0, p.y * 0.6) * 0.16
	if e < 1.5: h = lerpf(LAKE - 7.0, h, smoothstep(0.72, 1.32, e))
	return h

## Smooth bilinear lookup of the cached height field.
func _height(x: float, z: float) -> float:
	if height_cache.is_empty() or x < -1.0 or z < -1.0 or x >= SIZE or z >= SIZE:
		return _expanded_height(x, z)
	var ix := floori(x)
	var iz := floori(z)
	var row := SIZE + 2
	var i := (iz + 1) * row + ix + 1
	var fx := x - ix
	var top := lerpf(height_cache[i], height_cache[i + 1], fx)
	return lerpf(top, lerpf(height_cache[i + row], height_cache[i + row + 1], fx), z - iz)

func _surface(x: float, z: float) -> float:
	return _height(x, z)

func _slope(x: float, z: float) -> float:
	return Vector2(_height(x + 0.5, z) - _height(x - 0.5, z), _height(x, z + 0.5) - _height(x, z - 0.5)).length()

func _cached(ix: int, iz: int) -> float:
	if ix < -1 or iz < -1 or ix > SIZE or iz > SIZE: return _expanded_height(ix, iz)
	return height_cache[(iz + 1) * (SIZE + 2) + ix + 1]

func _can_walk(p: Vector3, from: Vector3) -> bool:
	if p.x < 2 or p.z < 2 or p.x >= SIZE - 2 or p.z >= SIZE - 2: return false
	var h := _surface(p.x, p.z)
	if h < LAKE + 0.2: return false
	var run := Vector2(p.x - from.x, p.z - from.z).length()
	# Cliffs and steep mountainsides block; ordinary hills are freely walkable.
	if run > 0.0001 and absf(h - _surface(from.x, from.z)) / run > 1.05: return false
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK)), []):
		if rect.has_point(Vector2(p.x, p.z)): return false
	for npc in npcs:
		if p.distance_to(npc.actor.position) < 0.7: return false
	return true

# --- Roads ------------------------------------------------------------------

func _build_paths() -> void:
	path_field.resize((SIZE + 1) * (SIZE + 1))
	path_field.fill(50.0)
	for path: Array in PATHS:
		var half: float = path[0]
		var dense := _smooth(path[1])
		path_points.append(dense)
		for i in dense.size() - 1:
			var a: Vector2 = dense[i]
			var b: Vector2 = dense[i + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(6, 6)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(6, 6)
			for z in range(maxi(0, floori(lo.y)), mini(SIZE, ceili(hi.y)) + 1):
				for x in range(maxi(0, floori(lo.x)), mini(SIZE, ceili(hi.x)) + 1):
					var p := Vector2(x, z)
					var ab := b - a
					var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
					var index := z * (SIZE + 1) + x
					path_field[index] = minf(path_field[index], p.distance_to(a + ab * t) - half)

func _smooth(points: Array) -> Array:
	var dense: Array = []
	for i in points.size() - 1:
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		var steps := maxi(2, ceili(p1.distance_to(p2) / 1.5))
		for s in steps:
			var t := float(s) / steps
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	dense.append(points[-1])
	return dense

## Signed distance to the nearest road edge (negative on the road).
func _path_distance(x: float, z: float) -> float:
	var ix := clampi(roundi(x), 0, SIZE)
	var iz := clampi(roundi(z), 0, SIZE)
	return path_field[iz * (SIZE + 1) + ix]

func _plaza_weight(p: Vector2) -> float:
	var weight := 0.0
	for plaza: Array in PLAZAS:
		var r: float = plaza[1]
		if p.distance_to(plaza[0]) > r + 4.0: continue
		var d := p.distance_to(plaza[0]) + noise.get_noise_2d(p.x * 4.0, p.y * 4.0) * 2.0
		weight = maxf(weight, 1.0 - smoothstep(r - 1.5, r + 1.0, d))
	return weight

func _field_weight(p: Vector2) -> float:
	var weight := 0.0
	for field: Array in FIELDS:
		var q: Vector2 = (p - field[0]).abs() - field[1]
		weight = maxf(weight, 1.0 - smoothstep(-0.8, 0.6, maxf(q.x, q.y)))
	return weight

func _clear(p: Vector2, margin := 0.0) -> bool:
	for zone: Array in CLEARINGS:
		if p.distance_to(zone[0]) < zone[1] + margin: return true
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), []):
		if rect.grow(1.0 + margin).has_point(p): return true
	return false

# --- World ------------------------------------------------------------------

func _build_world() -> void:
	var started := Time.get_ticks_msec()
	_build_paths()
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("lake_level", LAKE)
	lamp_material = Props.flat(Color("ffd58a"), 0.5, Color("ffb54d"))
	_build_terrain()
	_build_far_terrain()
	_build_lake()
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	_build_castle(landmarks)
	_build_town(landmarks)
	_build_village(landmarks)
	_build_ruins(landmarks)
	_build_roadside(landmarks)
	_index_obstacles()
	_build_cliffs()
	_build_trees_and_rocks()
	_index_obstacles()
	_build_grass()
	_build_labels(landmarks)
	print("[JRPGWorld2] Built ", SIZE, " x ", SIZE, " open field in ", Time.get_ticks_msec() - started, " ms; seed=", world_seed)

func _build_terrain() -> void:
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
			for z in range(cz, z1 + 1):
				for x in range(cx, x1 + 1):
					var h := _cached(x, z)
					vertices.append(Vector3(x, h, z))
					normals.append(Vector3(_cached(x - 1, z) - _cached(x + 1, z), 2.0, _cached(x, z - 1) - _cached(x, z + 1)).normalized())
					var road := 1.0 - smoothstep(-0.4, 1.0, _path_distance(x, z) + noise.get_noise_2d(x * 5.0, z * 5.0) * 0.8)
					var sand := (1.0 - smoothstep(LAKE + 0.4, LAKE + 1.6, h)) * (1.0 - road)
					colors.append(Color(road, sand, _plaza_weight(Vector2(x, z)), _field_weight(Vector2(x, z)) * (1.0 - road)))
			var width := x1 - cx + 1
			var indices := PackedInt32Array()
			for z in z1 - cz:
				for x in x1 - cx:
					var i := z * width + x
					indices.append_array([i, i + 1, i + width, i + 1, i + width + 1, i + width])
			var chunk := MeshInstance3D.new()
			chunk.name = "Terrain_%d_%d" % [cx / CHUNK, cz / CHUNK]
			chunk.mesh = _array_mesh(vertices, normals, colors, indices, terrain_material)
			root.add_child(chunk)

## Coarse hills and ranges beyond the playable square, so the horizon is never empty.
func _build_far_terrain() -> void:
	var step := 8
	var lo := -480
	var count := (SIZE + 960) / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in count:
		for i in count:
			var x := float(lo + i * step)
			var z := float(lo + j * step)
			var inside := x >= 0 and x <= SIZE and z >= 0 and z <= SIZE
			var h := _cached(int(x), int(z)) - 0.4 if inside else maxf(_expanded_height(x, z), LAKE + 2.0)
			vertices.append(Vector3(x, h, z))
			colors.append(Color(0, 0, 0, 0))
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
	far.mesh = _array_mesh(vertices, normals, colors, indices, terrain_material)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)

func _build_lake() -> void:
	lake_material = ShaderMaterial.new()
	lake_material.shader = LAKE_SHADER
	var step := 4
	var count := SIZE / step + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var depths := PackedFloat32Array()
	for j in count:
		for i in count:
			var h := _cached(i * step, j * step)
			depths.append(LAKE - h)
			vertices.append(Vector3(i * step, LAKE, j * step))
			normals.append(Vector3.UP)
			colors.append(Color(clampf((LAKE - h) / 8.0, 0.0, 1.0), 0, 0))
	var indices := PackedInt32Array()
	for j in count - 1:
		for i in count - 1:
			var k := j * count + i
			if maxf(maxf(depths[k], depths[k + 1]), maxf(depths[k + count], depths[k + count + 1])) < -1.5: continue
			indices.append_array([k, k + 1, k + count, k + 1, k + count + 1, k + count])
	var water := MeshInstance3D.new()
	water.name = "Lake"
	water.mesh = _array_mesh(vertices, normals, colors, indices, lake_material)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _array_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

# --- Primitive helpers -------------------------------------------------------

func _shape(kind: String, size: Vector3) -> Mesh:
	var key := "%s_%s" % [kind, size]
	if not meshes.has(key):
		var mesh: Mesh
		match kind:
			"box":
				mesh = BoxMesh.new()
				mesh.size = size
			"prism":
				mesh = PrismMesh.new()
				mesh.size = size
			"dome":
				mesh = SphereMesh.new()
				mesh.radius = size.x
				mesh.height = size.y * 2.0
				mesh.is_hemisphere = true
				mesh.radial_segments = 18
				mesh.rings = 6
			"cylinder", "cone":
				mesh = CylinderMesh.new()
				mesh.bottom_radius = size.x
				mesh.top_radius = 0.0 if kind == "cone" else size.z
				mesh.height = size.y
				mesh.radial_segments = 14
				mesh.rings = 1
		meshes[key] = mesh
	return meshes[key]

func _part(parent: Node3D, kind: String, size: Vector3, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = _shape(kind, size)
	part.material_override = material
	part.position = at
	part.rotation = rot
	parent.add_child(part)
	return part

func _block(center: Vector2, half: Vector2) -> void:
	obstacles.append(Rect2(center - half, half * 2.0))

func _anchor(parent: Node3D, at: Vector2, yaw_angle := 0.0, height := NAN) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(at.x, _height(at.x, at.y) if is_nan(height) else height, at.y)
	node.rotation.y = yaw_angle
	parent.add_child(node)
	return node

## Half-timbered cottage. The ridge runs along local X.
func _house(parent: Node3D, at: Vector2, yaw_angle: float, w: float, d: float, wall: float, roof: Color) -> void:
	var root := _anchor(parent, at, yaw_angle)
	var stone := Props.rock_material(Color("8f8d86"), 0.3)
	var plaster := Props.flat(Color("efe4cc"))
	var timber := Props.flat(Color("5a3f2c"))
	var glass := Props.flat(Color("2f4656"), 0.3)
	_part(root, "box", Vector3(w + 0.3, 1.8, d + 0.3), Vector3(0, -0.3, 0), stone)
	_part(root, "box", Vector3(w, wall, d), Vector3(0, 0.6 + wall * 0.5, 0), plaster)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(root, "box", Vector3(0.28, wall, 0.28), Vector3(sx * w * 0.5, 0.6 + wall * 0.5, sz * d * 0.5), timber)
	for y in [0.6 + wall * 0.5, 0.6 + wall]:
		_part(root, "box", Vector3(w + 0.06, 0.22, d + 0.06), Vector3(0, y, 0), timber)
	var roof_h := d * 0.55
	_part(root, "prism", Vector3(d + 1.0, roof_h, w + 1.0), Vector3(0, 0.6 + wall + roof_h * 0.5, 0), Props.flat(roof, 0.8), Vector3(0, PI / 2, 0))
	_part(root, "box", Vector3(0.7, 2.0, 0.7), Vector3(w * 0.28, 0.6 + wall + roof_h * 0.6, d * 0.18), stone)
	for side in [-1, 1]:
		for i in [-1, 1]:
			_part(root, "box", Vector3(0.8, 0.9, 0.08), Vector3(i * w * 0.27, 0.6 + wall * 0.62, side * (d * 0.5 + 0.03)), glass)
	_part(root, "box", Vector3(1.0, 1.8, 0.1), Vector3(0, 1.5, d * 0.5 + 0.05), Props.flat(Color("7b5639")))
	var corners := [Vector2(w, d), Vector2(-w, d), Vector2(w, -d), Vector2(-w, -d)]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c: Vector2 in corners:
		var r := (c * 0.5 + c.sign() * 0.2).rotated(-yaw_angle)
		lo = lo.min(r)
		hi = hi.max(r)
	obstacles.append(Rect2(at + lo, hi - lo))

func _lamp(parent: Node3D, at: Vector2, height := NAN) -> void:
	var root := _anchor(parent, at, 0.0, height)
	var iron := Props.flat(Color("2d2f33"), 0.6)
	_part(root, "cylinder", Vector3(0.09, 3.2, 0.07), Vector3(0, 1.6, 0), iron)
	_part(root, "box", Vector3(0.9, 0.08, 0.08), Vector3(0.35, 3.1, 0), iron)
	_part(root, "box", Vector3(0.34, 0.45, 0.34), Vector3(0.7, 2.75, 0), lamp_material)
	_part(root, "cone", Vector3(0.32, 0.25, 0), Vector3(0.7, 3.1, 0), iron)
	_block(at, Vector2(0.25, 0.25))

# --- Landmarks ---------------------------------------------------------------

func _build_castle(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "LumiereCastle"
	parent.add_child(root)
	var c := Vector3(CRAG.x, CRAG_TOP, CRAG.y)
	var stone := Props.rock_material(Color("d6d0c2"), 0.25)
	var slate := Props.flat(Color("4a5d78"), 0.7)
	var roof := Props.flat(Color("6e4430"), 0.8)
	var dark := Props.flat(Color("2c3640"))
	var ring := 11.0
	var towers: Array[Vector3] = []
	for k in 8:
		var angle := (k + 0.5) * TAU / 8.0
		towers.append(c + Vector3(cos(angle), 0, sin(angle)) * ring)
	for k in 8:
		var a := towers[k]
		var b := towers[(k + 1) % 8]
		var dir := b - a
		var length := dir.length()
		var wall_yaw := atan2(-dir.z, dir.x)
		# k == 1 spans the south side, facing the town.
		var gate := k == 1
		var pieces: Array = [[0.0, 1.0]] if not gate else [[0.0, 0.3], [0.7, 1.0]]
		for piece: Array in pieces:
			var t0: float = piece[0]
			var t1: float = piece[1]
			var mid := a.lerp(b, (t0 + t1) * 0.5)
			_part(root, "box", Vector3(length * (t1 - t0), 7.0, 1.3), mid + Vector3(0, 1.0, 0), stone, Vector3(0, wall_yaw, 0))
			var merlons := int(length * (t1 - t0) / 1.6)
			for m in merlons:
				var p := a.lerp(b, lerpf(t0, t1, (m + 0.5) / merlons))
				_part(root, "box", Vector3(0.8, 0.7, 1.4), p + Vector3(0, 4.85, 0), stone, Vector3(0, wall_yaw, 0))
			for s in int(length * (t1 - t0) / 1.4) + 1:
				var p := a.lerp(b, lerpf(t0, t1, float(s) / maxf(1.0, length * (t1 - t0) / 1.4)))
				_block(Vector2(p.x, p.z), Vector2(0.75, 0.75))
		if gate:
			_part(root, "box", Vector3(length * 0.44, 1.6, 1.7), a.lerp(b, 0.5) + Vector3(0, 4.3, 0), stone, Vector3(0, wall_yaw, 0))
	for t in towers:
		_part(root, "cylinder", Vector3(1.7, 10.5, 1.55), t + Vector3(0, 3.25, 0), stone)
		_part(root, "cylinder", Vector3(2.0, 0.6, 2.0), t + Vector3(0, 8.6, 0), stone)
		_part(root, "cone", Vector3(2.1, 3.8, 0), t + Vector3(0, 10.8, 0), slate)
		_part(root, "box", Vector3(0.3, 1.0, 0.3), t + Vector3(0, 6.0, 0) + (t - c).normalized() * 1.55, dark)
		_block(Vector2(t.x, t.z), Vector2(1.8, 1.8))
	# Palace wings with brown gables flank the keep; a long hall closes the rear.
	for side in [-1, 1]:
		_part(root, "box", Vector3(6.0, 7.0, 7.0), c + Vector3(side * 6.2, 2.5, 1.0), stone)
		_part(root, "prism", Vector3(6.6, 2.6, 7.6), c + Vector3(side * 6.2, 7.3, 1.0), roof)
		for z in [-1.5, 1.0, 3.5]:
			_part(root, "box", Vector3(0.1, 1.2, 0.6), c + Vector3(side * 3.15, 4.2, z), dark)
		_block(CRAG + Vector2(side * 6.2, 1.0), Vector2(3.1, 3.6))
	_part(root, "box", Vector3(9.0, 8.0, 5.0), c + Vector3(0, 3.0, -6.5), stone)
	_part(root, "prism", Vector3(5.6, 2.8, 9.6), c + Vector3(0, 8.4, -6.5), roof, Vector3(0, PI / 2, 0))
	_block(CRAG + Vector2(0, -6.5), Vector2(4.6, 2.6))
	# Tiered central keep under a tall spire.
	_part(root, "cylinder", Vector3(4.6, 13.0, 4.3), c + Vector3(0, 5.5, 0), stone)
	_part(root, "cylinder", Vector3(3.4, 7.0, 3.2), c + Vector3(0, 15.5, 0), stone)
	_part(root, "cylinder", Vector3(2.3, 5.0, 2.1), c + Vector3(0, 21.5, 0), stone)
	_part(root, "cone", Vector3(2.6, 13.0, 0), c + Vector3(0, 30.5, 0), slate)
	for k in 4:
		var angle := k * TAU / 4.0 + PI / 4.0
		var t := c + Vector3(cos(angle), 0, sin(angle)) * 4.6
		_part(root, "cylinder", Vector3(1.1, 15.0, 1.0), t + Vector3(0, 6.5, 0), stone)
		_part(root, "cone", Vector3(1.4, 4.0, 0), t + Vector3(0, 16.0, 0), slate)
	for k in 10:
		var angle := k * TAU / 10.0
		_part(root, "box", Vector3(0.35, 1.4, 0.35), c + Vector3(cos(angle) * 4.4, 9.0, sin(angle) * 4.4), dark, Vector3(0, -angle, 0))
	_part(root, "box", Vector3(1.6, 2.6, 0.3), c + Vector3(0, 1.3, 4.4), Props.flat(Color("5a3f2c")))
	_block(CRAG, Vector2(5.0, 5.0))

## Walled castle town on the slope below the crag, in the spirit of a JRPG royal capital.
func _build_town(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CastleTown"
	parent.add_child(root)
	var stone := Props.rock_material(Color("cfc8b8"), 0.3)
	var slate := Props.flat(Color("4a5d78"), 0.7)
	var brown := Props.flat(Color("7f5236"), 0.8)
	# Town walls: a U open to the crag, gate on the main street.
	var w := TOWN_RECT.position.x
	var e := TOWN_RECT.end.x
	var n := TOWN_RECT.position.y
	var s := TOWN_RECT.end.y
	for run in [[Vector2(189, 133), Vector2(w, n)], [Vector2(w, n), Vector2(w, s)], [Vector2(w, s), Vector2(CRAG.x - 3.0, s)],
			[Vector2(CRAG.x + 3.0, s), Vector2(e, s)], [Vector2(e, s), Vector2(e, n)], [Vector2(e, n), Vector2(221, 133)]]:
		_wall_run(root, run[0], run[1], stone)
	var mid := (n + s) * 0.5
	for at in [Vector2(w, n), Vector2(w, mid), Vector2(w, s), Vector2(e, s), Vector2(e, mid), Vector2(e, n)]:
		_round_tower(root, at, 2.2, 8.5, stone, slate)
	for side in [-1, 1]:
		_round_tower(root, Vector2(CRAG.x + side * 4.2, s), 1.8, 9.5, stone, brown)
	var gate_top := _height(CRAG.x, s) + 4.2
	_part(root, "box", Vector3(6.6, 2.0, 1.8), Vector3(CRAG.x, gate_top + 1.0, s), stone)
	# Houses line the main street and a second row behind it, all facing the street.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 77
	var roofs := [Color("6e4430"), Color("7d4b33"), Color("5e3a28"), Color("4c5a6c"), Color("845034")]
	for side in [-1, 1]:
		for z in [195.0, 165.0, 153.5, 146.0]:
			var offset := 9.5 if z > 170.0 else 11.0
			_house(root, Vector2(CRAG.x + side * offset, z), side * -PI / 2.0, rng.randf_range(4.6, 5.6), rng.randf_range(4.0, 4.6), rng.randf_range(3.0, 3.6), roofs[rng.randi() % roofs.size()])
		for z in [195.0, 166.0, 153.5]:
			_house(root, Vector2(CRAG.x + side * 18.5, z), side * -PI / 2.0, rng.randf_range(4.8, 6.0), rng.randf_range(4.0, 4.6), rng.randf_range(3.0, 3.8), roofs[rng.randi() % roofs.size()])
	_cathedral(root, Vector2(220, TOWN_PLAZA.y), stone, slate)
	_church(root, Vector2(190, TOWN_PLAZA.y), stone, slate)
	_fountain(root, TOWN_PLAZA, stone)
	for at in [Vector2(201.4, 197), Vector2(208.6, 197), Vector2(201.4, 186.5), Vector2(208.6, 169.5)]:
		_lamp(root, at)
	# Farmsteads and a watchtower among the fields outside the gate.
	for farm in [[Vector2(188, 208), 0.0], [Vector2(222, 207), 0.0], [Vector2(170, 230), PI / 2.0], [Vector2(242, 228), -PI / 2.0], [Vector2(184, 250), 0.0], [Vector2(216, 240), PI], [Vector2(196, 222), 0.0], [Vector2(214, 221), PI]]:
		_house(root, farm[0], farm[1], rng.randf_range(5.0, 6.5), rng.randf_range(4.0, 4.8), rng.randf_range(2.8, 3.2), roofs[rng.randi() % 3])
	_round_tower(root, Vector2(240, 212), 2.0, 11.0, Props.rock_material(Color("b9ad98"), 0.4), brown)

## A crenellated wall stepping along the terrain from a to b.
func _wall_run(parent: Node3D, a: Vector2, b: Vector2, stone: Material) -> void:
	var length := a.distance_to(b)
	var count := maxi(1, ceili(length / 3.0))
	var piece := length / count
	var wall_yaw := atan2(-(b.y - a.y), b.x - a.x)
	for i in count:
		var p0 := a.lerp(b, float(i) / count)
		var p1 := a.lerp(b, float(i + 1) / count)
		var center := (p0 + p1) * 0.5
		var h0 := _height(p0.x, p0.y)
		var h1 := _height(p1.x, p1.y)
		var low := minf(h0, h1) - 2.0
		var top := maxf(h0, h1) + 4.0
		_part(parent, "box", Vector3(piece + 0.05, top - low, 1.2), Vector3(center.x, (top + low) * 0.5, center.y), stone, Vector3(0, wall_yaw, 0))
		for m in 2:
			var q := p0.lerp(p1, (m + 0.5) / 2.0)
			_part(parent, "box", Vector3(0.7, 0.6, 1.3), Vector3(q.x, top + 0.3, q.y), stone, Vector3(0, wall_yaw, 0))
		for k in 3:
			_block(p0.lerp(p1, (k + 0.5) / 3.0), Vector2(0.8, 0.8))

func _round_tower(parent: Node3D, at: Vector2, radius: float, height: float, stone: Material, roof: Material) -> void:
	var root := _anchor(parent, at)
	_part(root, "cylinder", Vector3(radius, height + 2.0, radius * 0.92), Vector3(0, height * 0.5 - 1.0, 0), stone)
	_part(root, "cylinder", Vector3(radius + 0.3, 0.5, radius + 0.3), Vector3(0, height, 0), stone)
	_part(root, "cone", Vector3(radius + 0.4, radius * 1.9, 0), Vector3(0, height + 0.25 + radius * 0.95, 0), roof)
	_part(root, "box", Vector3(0.3, 0.9, 0.3), Vector3(0, height * 0.7, radius * 0.95), Props.flat(Color("2c3640")))
	_block(at, Vector2(radius, radius))

## Domed cathedral facing the plaza (front faces local +Z).
func _cathedral(parent: Node3D, at: Vector2, stone: Material, dome: Material) -> void:
	var root := _anchor(parent, at, -PI / 2.0)
	var dark := Props.flat(Color("2c3640"))
	_part(root, "box", Vector3(8.0, 8.0, 9.0), Vector3(0, 3.0, 0), stone)
	_part(root, "cylinder", Vector3(3.0, 2.6, 3.0), Vector3(0, 8.3, 0), stone)
	_part(root, "dome", Vector3(3.3, 3.3, 0), Vector3(0, 9.6, 0), dome)
	_part(root, "cylinder", Vector3(0.5, 1.2, 0.5), Vector3(0, 13.4, 0), stone)
	_part(root, "cone", Vector3(0.65, 1.4, 0), Vector3(0, 14.7, 0), dome)
	_part(root, "box", Vector3(6.0, 5.6, 1.6), Vector3(0, 1.8, 5.2), stone)
	_part(root, "prism", Vector3(6.4, 1.6, 1.8), Vector3(0, 5.4, 5.2), stone)
	_part(root, "box", Vector3(1.8, 3.0, 0.1), Vector3(0, 1.5, 6.05), Props.flat(Color("5a3f2c")))
	for x in [-2.2, 2.2]:
		_part(root, "box", Vector3(0.9, 1.8, 0.1), Vector3(x, 3.6, 6.05), dark)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(root, "cylinder", Vector3(0.75, 9.5, 0.7), Vector3(sx * 4.0, 3.75, sz * 4.5), stone)
			_part(root, "cone", Vector3(0.95, 2.4, 0), Vector3(sx * 4.0, 9.7, sz * 4.5), dome)
	_block(at, Vector2(5.4, 4.6))

## Small church with a west steeple (front faces local +Z).
func _church(parent: Node3D, at: Vector2, stone: Material, slate: Material) -> void:
	var root := _anchor(parent, at, PI / 2.0)
	var plaster := Props.flat(Color("efe4cc"))
	_part(root, "box", Vector3(5.6, 2.0, 9.4), Vector3(0, -0.3, 0), stone)
	_part(root, "box", Vector3(5.2, 5.0, 9.0), Vector3(0, 3.0, 0), plaster)
	_part(root, "prism", Vector3(6.2, 2.8, 9.6), Vector3(0, 6.9, 0), Props.flat(Color("74492f"), 0.8))
	_part(root, "box", Vector3(2.8, 10.0, 2.8), Vector3(0, 5.0, -4.6), stone)
	_part(root, "box", Vector3(0.5, 1.4, 0.1), Vector3(0, 8.0, -3.15), Props.flat(Color("2c3640")))
	_part(root, "cone", Vector3(2.1, 6.5, 0), Vector3(0, 13.25, -4.6), slate)
	_part(root, "box", Vector3(1.3, 2.2, 0.1), Vector3(0, 1.6, 4.55), Props.flat(Color("5a3f2c")))
	_block(at, Vector2(6.0, 3.0))

func _fountain(parent: Node3D, at: Vector2, stone: Material) -> void:
	var root := _anchor(parent, at)
	var water := Props.flat(Color("4f8fa6"), 0.15)
	_part(root, "cylinder", Vector3(2.2, 0.8, 2.2), Vector3(0, 0.2, 0), stone)
	_part(root, "cylinder", Vector3(1.95, 0.1, 1.95), Vector3(0, 0.58, 0), water)
	_part(root, "cylinder", Vector3(0.35, 1.8, 0.35), Vector3(0, 1.3, 0), stone)
	_part(root, "cylinder", Vector3(0.5, 0.3, 0.9), Vector3(0, 2.2, 0), stone)
	_part(root, "cylinder", Vector3(0.75, 0.06, 0.75), Vector3(0, 2.36, 0), water)
	_block(at, Vector2(2.2, 2.2))

func _build_village(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "WindmillVillage"
	parent.add_child(root)
	var roofs := [Color("b4573a"), Color("8a5a3c"), Color("4e6680"), Color("a8483a")]
	var houses := [[Vector2(310, 247), 0.0, 8.0, 5.5], [Vector2(338, 274), 0.0, 7.0, 5.0], [Vector2(318, 279), PI / 2, 7.0, 5.0],
		[Vector2(352, 258), PI / 2, 7.0, 5.0], [Vector2(325, 236), 0.0, 8.0, 5.0], [Vector2(300, 254), PI / 2, 6.0, 4.6]]
	for i in houses.size():
		var h: Array = houses[i]
		_house(root, h[0], h[1], h[2], h[3], 3.4, roofs[i % roofs.size()])
	_windmill(root, Vector2(346, 239), -0.73)
	# Well on the plaza.
	var well := _anchor(root, VILLAGE)
	var stone := Props.rock_material(Color("9a968c"), 0.35)
	_part(well, "cylinder", Vector3(1.3, 1.0, 1.3), Vector3(0, 0.5, 0), stone)
	_part(well, "cylinder", Vector3(1.0, 0.1, 1.0), Vector3(0, 0.95, 0), Props.flat(Color("2e4d5c"), 0.2))
	for side in [-1, 1]:
		_part(well, "box", Vector3(0.18, 2.4, 0.18), Vector3(side * 1.1, 1.6, 0), Props.flat(Color("5a3f2c")))
	_part(well, "prism", Vector3(2.9, 0.8, 1.8), Vector3(0, 3.1, 0), Props.flat(Color("8a5a3c")))
	_block(VILLAGE, Vector2(1.4, 1.4))
	for at in [Vector2(318, 262), Vector2(332, 259), Vector2(325, 252)]:
		_lamp(root, at)
	# Barrels and crates by the doors.
	var wood := Props.flat(Color("8b6440"))
	for at in [Vector2(313, 251.5), Vector2(314.2, 251.8), Vector2(341, 278), Vector2(354.5, 262)]:
		var barrel := _anchor(root, at)
		_part(barrel, "cylinder", Vector3(0.42, 1.0, 0.42), Vector3(0, 0.5, 0), wood)
		for y in [0.2, 0.8]: _part(barrel, "cylinder", Vector3(0.44, 0.07, 0.44), Vector3(0, y, 0), Props.flat(Color("3b3430"), 0.5))
		_block(at, Vector2(0.45, 0.45))

func _windmill(parent: Node3D, at: Vector2, yaw_angle: float) -> void:
	var root := _anchor(parent, at, yaw_angle)
	root.name = "Windmill"
	var stone := Props.rock_material(Color("a29d92"), 0.3)
	_part(root, "cylinder", Vector3(3.4, 2.0, 3.3), Vector3(0, 0.4, 0), stone)
	_part(root, "cylinder", Vector3(3.0, 10.5, 2.2), Vector3(0, 6.4, 0), Props.flat(Color("ece0c6")))
	_part(root, "cylinder", Vector3(2.65, 0.3, 2.65), Vector3(0, 6.0, 0), Props.flat(Color("5a3f2c")))
	_part(root, "cone", Vector3(2.9, 4.2, 0), Vector3(0, 13.7, 0), Props.flat(Color("a8483a"), 0.8))
	_part(root, "box", Vector3(1.2, 2.2, 0.2), Vector3(0, 1.9, 2.95), Props.flat(Color("7b5639")), Vector3(0.13, 0, 0))
	var hub := Node3D.new()
	hub.position = Vector3(0, 11.6, 2.9)
	root.add_child(hub)
	_part(hub, "cylinder", Vector3(0.45, 0.9, 0.45), Vector3.ZERO, Props.flat(Color("4a3424")), Vector3(PI / 2, 0, 0))
	var sail := Props.flat(Color("f1e8d4"))
	var frame := Props.flat(Color("6a4a30"))
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = k * PI / 2.0
		arm.position.z = 0.5
		hub.add_child(arm)
		_part(arm, "box", Vector3(0.28, 8.0, 0.18), Vector3(0, 4.2, 0), frame)
		_part(arm, "box", Vector3(1.7, 6.2, 0.06), Vector3(0.95, 4.9, 0.05), sail)
	spinning.append(hub)
	_block(at, Vector2(3.4, 3.4))

func _build_ruins(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "MistRuins"
	parent.add_child(root)
	var stone := Props.rock_material(Color("d4d2c8"), 0.85)
	var base := _height(RUINS.x, RUINS.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 404
	# Arches: two pillars and a lintel; the first spans the approach road.
	var arches := [[Vector2(88, 231), 1.02, 7.0], [Vector2(62, 216), 0.25, 8.5], [Vector2(80, 210), -0.2, 6.5], [Vector2(63, 236), 1.25, 7.5]]
	for i in arches.size():
		var a: Array = arches[i]
		var node := _anchor(root, a[0], a[1])
		var span: float = a[2]
		var tall := 7.0 + i * 0.8
		for side in [-1, 1]:
			_part(node, "box", Vector3(1.4, tall, 1.4), Vector3(side * span * 0.5, tall * 0.5 - 0.5, 0), stone)
			var p: Vector2 = a[0] + Vector2(side * span * 0.5, 0).rotated(-a[1])
			_block(p, Vector2(0.8, 0.8))
		if i != 2:
			_part(node, "box", Vector3(span + 1.8, 1.2, 1.6), Vector3(0, tall - 0.1, 0), stone)
		else:
			_part(node, "box", Vector3(span * 0.6, 1.2, 1.6), Vector3(-span * 0.25, tall - 0.1, 0), stone, Vector3(0, 0, 0.12))
	# A ring of broken columns around the plaza.
	for k in 9:
		var angle := k * TAU / 9.0 + 0.2
		var at := RUINS + Vector2(cos(angle), sin(angle)) * 10.5
		var tall := rng.randf_range(1.2, 6.5)
		var column := _anchor(root, at)
		_part(column, "cylinder", Vector3(0.75, tall, 0.65), Vector3(0, tall * 0.5 - 0.3, 0), stone)
		_part(column, "box", Vector3(1.8, 0.5, 1.8), Vector3(0, 0.0, 0), stone)
		_block(at, Vector2(0.9, 0.9))
	for k in 3:
		var at := RUINS + Vector2(12.0 + k * 2.5, -10.0 + k * 1.0)
		var wall := _anchor(root, at, 0.4)
		_part(wall, "box", Vector3(3.2, rng.randf_range(1.5, 4.5), 1.0), Vector3(0, 1.0, 0), stone)
		_block(at, Vector2(1.6, 1.6))
	# Glowing crystal on a stepped pedestal.
	var shrine := _anchor(root, RUINS, 0.0, base)
	_part(shrine, "cylinder", Vector3(2.6, 0.6, 2.6), Vector3(0, 0.2, 0), stone)
	_part(shrine, "cylinder", Vector3(1.8, 0.6, 1.8), Vector3(0, 0.8, 0), stone)
	_block(RUINS, Vector2(2.4, 2.4))
	crystal = Node3D.new()
	crystal.position = Vector3(0, 4.2, 0)
	shrine.add_child(crystal)
	var glow := Props.flat(Color("7fe3ff"), 0.1, Color("39b8ff"))
	glow.emission_energy_multiplier = 1.6
	_part(crystal, "cone", Vector3(1.1, 3.6, 0), Vector3(0, 1.8, 0), glow)
	_part(crystal, "cone", Vector3(1.1, 2.4, 0), Vector3(0, -1.2, 0), glow, Vector3(PI, 0, 0))
	var light := OmniLight3D.new()
	light.light_color = Color("74d4ff")
	light.light_energy = 1.6
	light.omni_range = 14.0
	crystal.add_child(light)

func _build_roadside(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Roadside"
	parent.add_child(root)
	_lamp(root, Vector2(154.5, 297))
	_lamp(root, Vector2(176, 279.5))
	_lamp(root, Vector2(203, 236))
	_lamp(root, Vector2(209, 228))
	_signpost(root, Vector2(167.5, 279), 0.8)
	_signpost(root, Vector2(196, 243), -0.4)
	var wood := Props.flat(Color("8b6440"))
	for at in [Vector2(155.5, 306), Vector2(156.4, 307.1), Vector2(156.8, 305.6)]:
		var barrel := _anchor(root, at)
		_part(barrel, "cylinder", Vector3(0.42, 1.0, 0.42), Vector3(0, 0.5, 0), wood)
		for y in [0.2, 0.8]: _part(barrel, "cylinder", Vector3(0.44, 0.07, 0.44), Vector3(0, y, 0), Props.flat(Color("3b3430"), 0.5))
		_block(at, Vector2(0.45, 0.45))
	# Rail fences along stretches of the main and eastern roads.
	var posts: Array[Transform3D] = []
	var rails: Array[Transform3D] = []
	for run: Array in [[0, 6, 26, 1.0], [1, 8, 32, -1.0], [2, 6, 18, 1.0]]:
		var dense: Array = path_points[run[0]]
		var half: float = PATHS[run[0]][0]
		var previous := Vector3.INF
		for i in range(run[1], mini(run[2], dense.size() - 1), 2):
			var a: Vector2 = dense[i]
			var direction: Vector2 = (dense[i + 1] - a).normalized()
			var p: Vector2 = a + Vector2(-direction.y, direction.x) * (half + 1.3) * float(run[3])
			var point := Vector3(p.x, _height(p.x, p.y), p.y)
			posts.append(Transform3D(Basis.IDENTITY, point + Vector3(0, 0.55, 0)))
			_block(p, Vector2(0.25, 0.25))
			if previous != Vector3.INF:
				var span := point - previous
				var basis := Basis.looking_at(span.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, span.length()))
				for y in [0.45, 0.85]:
					rails.append(Transform3D(basis, previous.lerp(point, 0.5) + Vector3(0, y, 0)))
				for s in 3:
					var q := previous.lerp(point, (s + 0.5) / 3.0)
					_block(Vector2(q.x, q.z), Vector2(0.25, 0.25))
			previous = point
	_multimesh(root, _shape("box", Vector3(0.16, 1.1, 0.16)), posts, wood, "FencePosts")
	_multimesh(root, _shape("box", Vector3(0.08, 0.1, 1.0)), rails, wood, "FenceRails")

func _signpost(parent: Node3D, at: Vector2, yaw_angle: float) -> void:
	var root := _anchor(parent, at, yaw_angle)
	var wood := Props.flat(Color("7a5536"))
	_part(root, "box", Vector3(0.18, 2.4, 0.18), Vector3(0, 1.2, 0), wood)
	_part(root, "box", Vector3(1.3, 0.3, 0.06), Vector3(0.5, 2.0, 0), Props.flat(Color("b48a5c")))
	_part(root, "box", Vector3(1.1, 0.3, 0.06), Vector3(-0.4, 1.6, 0.02), Props.flat(Color("b48a5c")), Vector3(0, 0.5, 0))
	_block(at, Vector2(0.3, 0.3))

func _multimesh(parent: Node3D, mesh: Mesh, transforms: Array, material: Material, node_name: String, shadows := true, range_end := 0.0) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.visibility_range_end = range_end
	if not shadows: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

# --- Nature ------------------------------------------------------------------

## Rock slabs stacked along the mesa cliffs, leaving the ramps open.
func _build_cliffs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 17
	var transforms: Array = [[], [], [], []]
	for index in MESAS.size():
		var mesa: Array = MESAS[index]
		var lo: Vector2 = mesa[0] - mesa[1] - Vector2(8, 8)
		var hi: Vector2 = mesa[0] + mesa[1] + Vector2(8, 8)
		var top: float = mesa[2]
		var z := lo.y
		while z < hi.y:
			var x := lo.x
			while x < hi.x:
				var p := Vector2(x + rng.randf_range(-0.8, 0.8), z + rng.randf_range(-0.8, 0.8))
				var m := _mesa_mask(p, index)
				x += 2.3
				if m < 0.15 or m > 0.85 or _near_ramp(p, 2.0): continue
				var low := _base(p)
				if top - low < 2.0: continue
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.8, 2.8), (top - low) * rng.randf_range(0.75, 0.95), rng.randf_range(1.8, 2.8)))
				transforms[rng.randi_range(0, 3)].append(Transform3D(basis, Vector3(p.x, low - 0.6, p.y)))
			z += 2.3
	var root := Node3D.new()
	root.name = "Cliffs"
	add_child(root)
	for v in 4:
		_multimesh(root, Props.mesh("rock", v), transforms[v], Props.rock_material(Color("8a929e"), 0.8), "CliffRock_%d" % v)

func _near_ramp(p: Vector2, margin: float) -> bool:
	for ramp: Array in RAMPS:
		var a: Vector2 = ramp[0]
		var ab: Vector2 = ramp[1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < ramp[2] + 5.0 + margin: return true
	return false

func _build_trees_and_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 5
	var chunks: Dictionary = {}
	var spacing := 4.0
	var z := 0.0
	while z < SIZE:
		var x := 0.0
		while x < SIZE:
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.75, 1.25)
			var angle := rng.randf() * TAU
			x += spacing
			var h := _height(p.x, p.y)
			if h < LAKE + 1.0 or h > 66.0 or _path_distance(p.x, p.y) < 3.0 or _slope(p.x, p.y) > 0.8: continue
			if _clear(p) or _near_ramp(p, 0.0): continue
			var forest := noise.get_noise_2d(p.x * 0.9 + 1234.0, p.y * 0.9 - 77.0) + (1.0 - smoothstep(70.0, 125.0, p.y)) * 0.3
			var tree_chance := 0.018 + smoothstep(0.02, 0.3, forest) * 0.6
			var kind := ""
			var variant := 0
			if roll < tree_chance:
				# Broadleaf trees are left out for now; drawing the same random number keeps
				# every other tree and rock where it was.
				if not (h > 26.0 or forest > 0.12 or pick < 0.25):
					rng.randf()
					continue
				kind = "conifer"
				variant = int(pick * 30.0) % 3
				obstacles.append(Rect2(p - Vector2(0.45, 0.45) * size, Vector2(0.9, 0.9) * size))
			elif roll < tree_chance + 0.025:
				kind = "rock"
				variant = int(pick * 40.0) % 4
				size *= 1.1 if pick < 0.7 else 2.2
				obstacles.append(Rect2(p - Vector2(0.7, 0.7) * size, Vector2(1.4, 1.4) * size))
			else:
				continue
			var key := Vector2i(floori(p.x / 64.0), floori(p.y / 64.0))
			if not chunks.has(key): chunks[key] = {}
			var mesh_key := "%s_%d" % [kind, variant]
			if not chunks[key].has(mesh_key): chunks[key][mesh_key] = []
			var basis := Basis(Vector3.UP, angle).scaled(Vector3(size, size * (rng.randf_range(0.6, 0.9) if kind == "rock" else rng.randf_range(0.9, 1.15)), size))
			chunks[key][mesh_key].append(Transform3D(basis, Vector3(p.x, h - (0.35 * size if kind == "rock" else 0.1), p.y)))
		z += spacing
	var root := Node3D.new()
	root.name = "Forest"
	add_child(root)
	for key: Vector2i in chunks:
		var chunk := Node3D.new()
		chunk.name = "Forest_%d_%d" % [key.x, key.y]
		root.add_child(chunk)
		for mesh_key: String in chunks[key]:
			var kind := mesh_key.get_slice("_", 0)
			var material: Material = Props.rock_material(Color("8d939c"), 0.75) if kind == "rock" else Props.foliage_material()
			_multimesh(chunk, Props.mesh(kind, int(mesh_key.get_slice("_", 1))), chunks[key][mesh_key], material, mesh_key)

func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 91
	var root := Node3D.new()
	root.name = "Meadow"
	add_child(root)
	var cell := 20
	for cz in range(0, SIZE, cell):
		for cx in range(0, SIZE, cell):
			var groups: Array = [[], [], [], []]
			for z in range(cz, cz + cell):
				for x in range(cx, cx + cell):
					for k in 3:
						var px := x + rng.randf()
						var pz := z + rng.randf()
						var roll := rng.randf()
						var size := rng.randf_range(0.8, 1.3)
						var angle := rng.randf() * TAU
						if roll > 0.72: continue
						var h := _height(px, pz)
						if h < LAKE + 0.5 or h > 50.0: continue
						var road := _path_distance(px, pz)
						if road < -0.2 or (road < 0.8 and roll > 0.3): continue
						if _slope(px, pz) > 0.65 or _plaza_weight(Vector2(px, pz)) > 0.3 or _field_weight(Vector2(px, pz)) > 0.3: continue
						var group := 0 if roll < 0.45 else 1
						if roll > 0.69: group = 2 + int(angle * 10.0) % 2
						groups[group].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(size, size, size)), Vector3(px, h - 0.03, pz)))
			var detail := Node3D.new()
			detail.name = "Meadow_%d_%d" % [cx, cz]
			root.add_child(detail)
			for g in 4:
				_multimesh(detail, Props.mesh("grass" if g < 2 else "flower", g % 2), groups[g], Props.foliage_material(), "Grass_%d" % g, false, 70.0)

func _build_labels(parent: Node3D) -> void:
	for entry in [["ルミエール城", CRAG, 44.0], ["城下町", TOWN_PLAZA, 16.0], ["鏡の湖", Vector2(150, 160), 6.0], ["風車の丘", VILLAGE, 20.0], ["白霧の遺跡", RUINS, 16.0], ["見晴らしの丘", SPAWN_HILL, 9.0], ["北嶺 アルヴァ", Vector2(300, 30), 22.0]]:
		var label := Label3D.new()
		label.text = entry[0]
		var p: Vector2 = entry[1]
		label.position = Vector3(p.x, maxf(_height(p.x, p.y), LAKE) + entry[2], p.y)
		label.font_size = 42
		label.pixel_size = 0.03
		label.visibility_range_begin = 45.0
		label.modulate = Color("fff2cb")
		label.outline_modulate = Color("243e47")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(label)

# --- Characters, camera and regions -----------------------------------------

func _spawn_characters() -> void:
	story = {}
	cleared = true
	player = Explorer.new()
	if player_model: player.model_scene = player_model
	player.use_3d = use_3d_player
	player.name = "Explorer"
	add_child(player)
	var spawn := Vector2(player_spawn_position.x, player_spawn_position.z)
	player.position = Vector3(spawn.x, _surface(spawn.x, spawn.y) + 0.05, spawn.y)
	player.world_facing = Vector3(0.3, 0, -1).normalized()
	# Roster switching (B / V / L3) as in JRPGWorldSample, without placing the roster in the field.
	for index in character_roster.size():
		if character_roster[index] == player.model_scene:
			player_roster_index = index
	if character_text and player.model:
		character_text.text = "操作キャラ：" + player.model.display_name
	encounter_marker = Node3D.new()
	encounter_marker.visible = false
	add_child(encounter_marker)
	encounter_position = Vector3(-1000, 0, -1000)

func _preset(index: int) -> void:
	overview = true
	match index:
		1:
			focus = Vector3(SIZE * 0.5, 10, SIZE * 0.55)
			yaw = 0.35
			pitch = 0.7
			distance = SIZE * 1.15
		2:
			focus = Vector3(VILLAGE.x, 34, VILLAGE.y)
			yaw = 0.95
			pitch = 0.32
			distance = 46
		3:
			focus = Vector3(CRAG.x, 26, 168)
			yaw = 0.0
			pitch = 0.42
			distance = 120
		4:
			focus = Vector3(RUINS.x, 30, RUINS.y)
			yaw = 0.7
			pitch = 0.3
			distance = 38
	_update_camera()

func _region() -> String:
	var p := Vector2(player.position.x, player.position.z)
	if _mesa_mask(p, 2) > 0.5: return "ルミエール城"
	if TOWN_RECT.grow(1.0).has_point(p): return "城下町ルミエール"
	if _mesa_mask(p, 0) > 0.5: return "風車の丘"
	if _mesa_mask(p, 1) > 0.5: return "白霧の遺跡"
	if p.y < 95.0: return "北嶺の麓"
	if p.distance_to(SPAWN_HILL) < 40.0: return "見晴らしの丘"
	if ((p - LAKE_CENTER) / LAKE_RADIUS).length() < 1.3: return "鏡の湖畔"
	return "翠風の野"

func _process(delta: float) -> void:
	super._process(delta)
	for hub in spinning: hub.rotation.z += delta * 0.55
	if crystal:
		crystal.rotation.y += delta * 0.6
		crystal.position.y = 4.2 + sin(Time.get_ticks_msec() * 0.0015) * 0.25
	_sync_conditions()
	if mode == "explore" and prompt_text and not prompt_text.text.begins_with("E /"):
		prompt_text.text = "目標 : 丘の上のルミエール城を目指して、開けた野を自由に旅しよう"

## Mirrors FieldWeather's time/weather onto the open-field materials.
func _sync_conditions() -> void:
	if field_weather == null: return
	var key: int = field_weather.time_index * 4 + field_weather.weather_index
	if key == conditions_key: return
	conditions_key = key
	var wet := 1.0 if field_weather.weather_index == 1 else 0.0
	var snow := 0.8 if field_weather.weather_index == 3 else 0.0
	var materials: Array[ShaderMaterial] = Props.shader_materials()
	materials.append_array([terrain_material, lake_material])
	for material in materials:
		material.set_shader_parameter("wetness", wet)
		material.set_shader_parameter("snow_cover", snow)
	lamp_material.emission_energy_multiplier = 3.0 if field_weather.time_index == 3 else (1.2 if field_weather.time_index == 2 else 0.3)
