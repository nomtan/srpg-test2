extends SceneTree
## Phase 2 vegetation checks: the 16 Blender-built assets (trees, bushes, grass, flowers)
## as Godot imports them, and the hierarchical-LOD / bush / grass MultiMesh structure.
##   godot --headless --path . -s res://scripts/world_jrpg/verify_vegetation_phase2.gd
## Add `-- --render --capture-dir=<dir>` (without --headless) for the asset captures.
const Vegetation = preload("res://scripts/world_jrpg/open_field_vegetation.gd")
const TERRAIN_SHADER = preload("res://scripts/world_jrpg/open_field_terrain.gdshader")
## Spec heights (§22) with a little room for blade lean and seed / flower heads.
const CLUSTER_HEIGHTS := {"grass_short": Vector2(0.08, 0.16), "grass_normal": Vector2(0.15, 0.35),
	"grass_tall": Vector2(0.3, 0.52), "grass_wild": Vector2(0.2, 0.52),
	"flower_grass_a": Vector2(0.15, 0.35), "flower_grass_b": Vector2(0.25, 0.52)}
var failed := false

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failed = true
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for asset in Vegetation.TREES: _check_tree(asset)
	for asset in Vegetation.BUSHES: _check_bush(asset)
	for asset in Vegetation.GRASSES: _check_grass(asset)
	for asset in Vegetation.FLOWERS: _check_flower(asset)
	_check_instancing()
	var args := OS.get_cmdline_user_args()
	if "--render" in args:
		var directory := "user://"
		for arg in args:
			if arg.begins_with("--capture-dir="): directory = arg.get_slice("=", 1)
		await _render(directory)
	print("Phase 2 vegetation: ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)

## Per-vertex data channels as the shaders read them (r tone, g wind, b phase, a palette).
func _channel_range(mesh: Mesh, surface: int, channel: int) -> Vector2:
	var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
	var lo := INF
	var hi := -INF
	for c in colors:
		lo = minf(lo, c[channel])
		hi = maxf(hi, c[channel])
	return Vector2(lo, hi)

func _surface_named(mesh: Mesh, material: Material) -> int:
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) == material: return s
	return -1

func _check_tree(asset: String) -> void:
	var lods := Vegetation.lod_meshes(asset)
	check(lods.size() == 4, "%s has LOD0-LOD3 (%d meshes)" % [asset, lods.size()])
	if lods.size() < 4: return
	var tris: Array[int] = []
	for mesh in lods: tris.append(Vegetation.triangle_count(mesh))
	print(asset, " triangles: ", tris)
	check(tris[0] >= 2000 and tris[0] <= 6000, "%s LOD0 within 2,000-6,000 triangles (%d)" % [asset, tris[0]])
	check(tris[1] >= 800 and tris[1] <= 2500, "%s LOD1 within 800-2,500 triangles (%d)" % [asset, tris[1]])
	check(tris[2] >= 200 and tris[2] <= 800, "%s LOD2 within 200-800 triangles (%d)" % [asset, tris[2]])
	check(tris[3] < tris[2], "%s LOD3 is coarser than LOD2 (%d)" % [asset, tris[3]])
	var aabb := lods[0].get_aabb()
	print(asset, " LOD0 AABB: ", aabb)
	check(aabb.end.y >= 5.0 and aabb.end.y <= 9.0, "%s height 5-9 m at scale 1 (%.2f m)" % [asset, aabb.end.y])
	check(aabb.position.y > -0.5 and aabb.position.y < 0.0, "%s origin at the trunk base (root flare sinks %.2f m)" % [asset, -aabb.position.y])
	# The landmark oak's crown follows its long limb, so allow it to sit off center.
	var center := aabb.get_center()
	check(Vector2(center.x, center.z).length() < 1.6, "%s crown over the origin (%.2f m off)" % [asset, Vector2(center.x, center.z).length()])
	for level in lods.size():
		var bounds := lods[level].get_aabb()
		check(bounds.end.y > aabb.end.y * 0.9 and bounds.size.x > aabb.size.x * 0.85, "%s LOD%d keeps the LOD0 silhouette envelope" % [asset, level])
		check(_surface_named(lods[level], Vegetation.TRUNK_MATERIAL) >= 0 and _surface_named(lods[level], Vegetation.FOLIAGE_MATERIAL) >= 0, "%s LOD%d uses the shared trunk and foliage materials" % [asset, level])
	var trunk := _surface_named(lods[0], Vegetation.TRUNK_MATERIAL)
	var leaves := _surface_named(lods[0], Vegetation.FOLIAGE_MATERIAL)
	var trunk_wind := _channel_range(lods[0], trunk, 1)
	var arrays := lods[0].surface_get_arrays(trunk)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var trunk_base := 0.0
	for i in verts.size():
		if verts[i].y < 1.5: trunk_base = maxf(trunk_base, colors[i].g)
	check(trunk_base < 0.05, "%s trunk base is anchored (wind weight %.3f below 1.5 m)" % [asset, trunk_base])
	check(trunk_wind.y < 0.5, "%s limbs move less than foliage (max limb weight %.2f)" % [asset, trunk_wind.y])
	var leaf_wind := _channel_range(lods[0], leaves, 1)
	check(leaf_wind.x > 0.25 and leaf_wind.y > 0.85, "%s foliage wind weight %.2f-%.2f" % [asset, leaf_wind.x, leaf_wind.y])
	var tone := _channel_range(lods[0], leaves, 0)
	check(tone.x < 0.2 and tone.y > 0.85, "%s foliage tone spans shadow to highlight (%.2f-%.2f)" % [asset, tone.x, tone.y])
	var phase := _channel_range(lods[0], leaves, 2)
	check(phase.y - phase.x > 0.5, "%s foliage masses carry distinct wind phases" % asset)

func _check_bush(asset: String) -> void:
	var lods := Vegetation.lod_meshes(asset)
	check(lods.size() == 3, "%s has LOD0-LOD2 (%d meshes)" % [asset, lods.size()])
	if lods.size() < 3: return
	var tris: Array[int] = []
	for mesh in lods: tris.append(Vegetation.triangle_count(mesh))
	print(asset, " triangles: ", tris)
	check(tris[0] <= 2500 and tris[1] < tris[0] and tris[2] < tris[1], "%s LODs get coarser within 2,500 triangles" % asset)
	var aabb := lods[0].get_aabb()
	check(aabb.end.y >= 0.4 and aabb.end.y <= 1.35, "%s height 0.4-1.2 m (%.2f m)" % [asset, aabb.end.y])
	for level in lods.size():
		check(_surface_named(lods[level], Vegetation.FOLIAGE_MATERIAL) >= 0, "%s LOD%d uses the shared foliage material" % [asset, level])
	var leaves := _surface_named(lods[0], Vegetation.FOLIAGE_MATERIAL)
	check(_channel_range(lods[0], leaves, 1).y < 0.5, "%s sways less than a tree crown" % asset)
	var tone := _channel_range(lods[0], leaves, 0)
	check(tone.x < 0.25 and tone.y > 0.8, "%s foliage tone spans shadow to highlight (%.2f-%.2f)" % [asset, tone.x, tone.y])

## Shared grass / flower cluster checks; returns the mesh for the material checks.
func _check_cluster(asset: String) -> Mesh:
	var lods := Vegetation.lod_meshes(asset)
	check(lods.size() == 1, "%s is one cluster mesh" % asset)
	var mesh := lods[0]
	var tris := Vegetation.triangle_count(mesh)
	print(asset, " triangles: ", tris)
	check(tris <= 140, "%s stays light for MultiMesh (%d triangles)" % [asset, tris])
	var aabb := mesh.get_aabb()
	var heights: Vector2 = CLUSTER_HEIGHTS[asset]
	check(aabb.end.y >= heights.x and aabb.end.y <= heights.y, "%s height %.2f-%.2f m (%.2f m)" % [asset, heights.x, heights.y, aabb.end.y])
	check(absf(aabb.position.y) < 0.01, "%s origin at the cluster root" % asset)
	var root_wind := 0.0
	var tip_wind := 0.0
	var phases := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var leaf_surface := mesh.surface_get_material(surface) == Vegetation.GRASS_MATERIAL
		for i in verts.size():
			if verts[i].y < 0.005: root_wind = maxf(root_wind, colors[i].g)
			tip_wind = maxf(tip_wind, colors[i].g)
			if leaf_surface: phases[snappedf(colors[i].b, 0.0001)] = true
	check(root_wind == 0.0 and tip_wind > 0.99, "%s roots pinned (weight %.2f), tips free (%.2f)" % [asset, root_wind, tip_wind])
	# Every blade / stem carries its own wind phase.
	check(phases.size() >= 8 and phases.size() <= 20, "%s has 8-20 blades and stems (%d)" % [asset, phases.size()])
	return mesh

func _check_grass(asset: String) -> void:
	var mesh := _check_cluster(asset)
	check(mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == Vegetation.GRASS_MATERIAL, "%s uses the shared grass material" % asset)

func _check_flower(asset: String) -> void:
	var mesh := _check_cluster(asset)
	var petals := _surface_named(mesh, Vegetation.FLOWER_MATERIAL)
	check(mesh.get_surface_count() == 2 and _surface_named(mesh, Vegetation.GRASS_MATERIAL) >= 0 and petals >= 0, "%s uses the shared grass + flower materials" % asset)
	if petals < 0: return
	var palette := _channel_range(mesh, petals, 3)
	check(palette.x == palette.y, "%s petals carry one palette (alpha %.2f)" % [asset, palette.x])

func _check_instancing() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var transforms: Array = []
	for i in 40:
		transforms.append(Transform3D(Basis(), Vector3(fmod(i * 7.3, 32.0), 0, fmod(i * 3.1, 32.0))))
	Vegetation.add_tree_chunk(parent, "broadleaf_a", transforms)
	var far: MultiMeshInstance3D = parent.get_node("broadleaf_a_LOD2")
	var farthest: MultiMeshInstance3D = parent.get_node("broadleaf_a_LOD3")
	check(far.multimesh.instance_count == 40 and farthest.multimesh.instance_count == 40, "far LODs hold the whole cell")
	check(far.visibility_range_begin == Vegetation.LOD2_FROM and far.visibility_range_end == farthest.visibility_range_begin, "LOD2 -> LOD3 bands meet")
	check(farthest.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "LOD3 casts no shadow")
	var near_count := [0, 0]
	var parented := true
	for node: MultiMeshInstance3D in parent.get_children():
		for level in 2:
			if node.name.begins_with("broadleaf_a_LOD%d_" % level):
				near_count[level] += node.multimesh.instance_count
				parented = parented and node.get_node(node.visibility_parent) == far
	check(near_count[0] == 40 and near_count[1] == 40, "fine LOD0/LOD1 cells cover every tree once")
	check(parented, "fine cells draw only while their LOD2 parent is inside its begin distance")
	var bushes := Node3D.new()
	root.add_child(bushes)
	Vegetation.add_bush_chunk(bushes, "bush_a", transforms)
	var bands: Array[MultiMeshInstance3D] = []
	for level in 3: bands.append(bushes.get_node("bush_a_LOD%d" % level))
	check(bands[0].visibility_range_end == bands[1].visibility_range_begin and bands[1].visibility_range_end == bands[2].visibility_range_begin, "bush LOD bands meet")
	check(bands[2].visibility_range_end == Vegetation.BUSH_LOD2_END, "bushes end at %d m" % Vegetation.BUSH_LOD2_END)
	check(bands[0].cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and bands[1].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "only near bushes cast shadows")
	var grass := Node3D.new()
	root.add_child(grass)
	var clumps: Array = []
	for i in 101: clumps.append(Transform3D(Basis(), Vector3(i * 0.2, 0, 0)))
	Vegetation.add_grass_chunk(grass, "grass_normal", clumps)
	var near: MultiMeshInstance3D = grass.get_node("grass_normal")
	var mid: MultiMeshInstance3D = grass.get_node("grass_normal_mid")
	check(near.multimesh.instance_count == 101 and mid.multimesh.instance_count == 51, "mid-distance grass keeps every other clump")
	check(near.visibility_range_end == mid.visibility_range_begin and mid.visibility_range_end == Vegetation.GRASS_FAR, "grass bands meet and end at %d m" % Vegetation.GRASS_FAR)
	check(near.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "grass casts no shadow")
	parent.queue_free()
	bushes.queue_free()
	grass.queue_free()

# --- Captures ----------------------------------------------------------------------------

var camera: Camera3D

func _render(directory: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	# Same lighting as the open field at midday (world.gd / field_weather.gd).
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("467da9")
	sky.sky_horizon_color = Color("c7deea")
	sky.ground_horizon_color = Color("b9c7b0")
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bccddd")
	environment.ambient_light_energy = 0.43
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_color = Color("fff5dc")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	stage.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(320, 320)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	# The terrain shader reads vertex COLOR as road / sand / plaza / field weights: all zero.
	var arrays := plane.get_mesh_arrays()
	var blank := PackedColorArray()
	blank.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	blank.fill(Color(0, 0, 0, 0))
	arrays[Mesh.ARRAY_COLOR] = blank
	var ground_mesh := ArrayMesh.new()
	ground_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ground.mesh = ground_mesh
	var terrain := ShaderMaterial.new()
	terrain.shader = TERRAIN_SHADER
	terrain.set_shader_parameter("lake_level", -100.0)
	ground.material_override = terrain
	stage.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 52
	stage.add_child(camera)
	get_root().size = Vector2i(1600, 900)
	# 1. LOD0..LOD3 lineups: the quality standard and one of each new tree family.
	for asset in ["broadleaf_a", "oak_a", "conifer_a"]:
		var lineup := _lineup(stage, asset, Vegetation.lod_meshes(asset), 12.0 if asset == "oak_a" else 9.0)
		var wide := 1.35 if asset == "oak_a" else 1.0
		await _shoot(directory, "%s_lods" % asset, Vector3(0, 4.5, 26 * wide), Vector3(0, 4.0, 0))
		lineup.queue_free()
	# 2. Broadleaf A hero close-up, slightly from below like the explore camera.
	var single := _lineup(stage, "broadleaf_a", [Vegetation.lod_meshes("broadleaf_a")[0]], 0.0)
	await _shoot(directory, "broadleaf_a_single", Vector3(4.0, 3.0, 11.5), Vector3(0, 4.2, 0))
	single.queue_free()
	# 3. Every tree at LOD0, then the bushes, grass and flower clusters side by side.
	var trees: Array[Mesh] = []
	for asset in Vegetation.TREES: trees.append(Vegetation.lod_meshes(asset)[0])
	var forest := _lineup(stage, "trees", trees, 12.5)
	await _shoot(directory, "trees_lineup", Vector3(0, 6.0, 62), Vector3(0, 4.0, 0))
	forest.queue_free()
	var shrubs: Array[Mesh] = []
	for asset in Vegetation.BUSHES: shrubs.append(Vegetation.lod_meshes(asset)[0])
	var shrub_row := _lineup(stage, "bushes", shrubs, 2.8)
	await _shoot(directory, "bushes", Vector3(0, 1.8, 6.2), Vector3(0, 0.45, 0))
	shrub_row.queue_free()
	var clusters: Array[Mesh] = []
	for asset in Vegetation.GRASSES + Vegetation.FLOWERS: clusters.append(Vegetation.lod_meshes(asset)[0])
	var cluster_row := _lineup(stage, "clusters", clusters, 0.55)
	await _shoot(directory, "grass_types", Vector3(0, 0.55, 1.6), Vector3(0, 0.15, 0))
	cluster_row.queue_free()
	# 4. Meadow patches at the explore camera height: grass mix with flower drifts,
	# then a forest edge of trees and bushes.
	var patch := Node3D.new()
	stage.add_child(patch)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var groups := {}
	for i in 12000:
		var p := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		var s := rng.randf_range(0.85, 1.15)
		var patchy := sin(p.x * 0.35) * cos(p.y * 0.3)
		var asset := "grass_normal"
		if patchy > 0.55 and rng.randf() < 0.25: asset = "flower_grass_a" if p.x < 0 else "flower_grass_b"
		elif patchy < -0.5: asset = "grass_tall" if p.y < 0 else "grass_wild"
		elif rng.randf() < 0.3: asset = "grass_short"
		if not groups.has(asset): groups[asset] = []
		groups[asset].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, -0.03, p.y)))
	for asset: String in groups: Vegetation.add_grass_chunk(patch, asset, groups[asset])
	var stand := {}
	for at in [Vector3(-6, 0, -14), Vector3(5, 0, -22), Vector3(13, 0, -9), Vector3(-15, 0, -24), Vector3(19, 0, -27)]:
		var asset: String = Vegetation.TREES[int(absf(at.x + at.z)) % Vegetation.TREES.size()]
		if not stand.has(asset): stand[asset] = []
		stand[asset].append(Transform3D(Basis(Vector3.UP, at.x), at))
	for asset: String in stand: Vegetation.add_tree_chunk(patch, asset, stand[asset])
	var shrubs_at := {}
	for i in 14:
		var at := Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-24, -8))
		var asset: String = Vegetation.BUSHES[i % 3]
		if not shrubs_at.has(asset): shrubs_at[asset] = []
		shrubs_at[asset].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))
	for asset: String in shrubs_at: Vegetation.add_bush_chunk(patch, asset, shrubs_at[asset])
	await _shoot(directory, "grass_closeup", Vector3(0, 1.6, 6), Vector3(0, 0.6, -6))
	await _shoot(directory, "grass_meadow", Vector3(0, 5.5, 14), Vector3(0, 1.0, -10))
	stage.queue_free()

## Meshes in a row along X, `spacing` apart, centered on the origin.
func _lineup(stage: Node3D, row_name: String, meshes: Array, spacing: float) -> Node3D:
	var row := Node3D.new()
	row.name = row_name
	stage.add_child(row)
	for i in meshes.size():
		var item := MeshInstance3D.new()
		item.mesh = meshes[i]
		item.position = Vector3((i - (meshes.size() - 1) * 0.5) * spacing, 0, 0)
		row.add_child(item)
	return row

func _shoot(directory: String, capture_name: String, from: Vector3, target: Vector3) -> void:
	camera.position = from
	camera.look_at(target)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join("vegetation_%s.png" % capture_name)
	get_root().get_texture().get_image().save_png(path)
	print("Captured ", path)
