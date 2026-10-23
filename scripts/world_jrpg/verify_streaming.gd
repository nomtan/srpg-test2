extends SceneTree
## Chunk-streaming checks for JRPGWorldSample2 (open_field_world.gd / open_field_chunks.gd).
##   godot --headless --path . -s res://scripts/world_jrpg/verify_streaming.gd
## Short load distances make the explorer's out-and-back run release and regenerate many
## tiles. Checks: tile counts stay within capacity(); regenerated tiles match their first
## version (heights, trees, bushes, grass); tiles rebuilt in another order match; shared
## edges of neighbor terrain meshes agree (positions and normals); heights are continuous
## across tile edges; the explorer never stands on a tile without heights / obstacles,
## and cannot step onto one; pinned tiles stay at full detail until unpinned.
## Add `-- --field-size=1600` to run it on the extended field.
const SCENE := "res://samples/JRPGWorldSample2.tscn"
const Chunks = preload("res://scripts/world_jrpg/open_field_chunks.gd")
const SPEED := 16.0
var world: Node3D
var failed := false

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failed = true
		push_error("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = (load(SCENE) as PackedScene).instantiate()
	world.grass_radius = 40.0
	world.detail_radius = 64.0
	world.terrain_radius = 80.0
	world.data_radius = 96.0
	world.far_radius = 160.0
	world.release_margin = 16.0
	world.startup_radius = 64.0
	root.add_child(world)
	var chunks: Chunks = world.chunks
	var extent: int = world.extent
	# Out across the field and back over the same ground.
	var far_x := minf(extent - 40.0, 380.0)
	var route: Array[Vector2] = [Vector2(150, 305), Vector2(far_x, 305), Vector2(far_x, 60), Vector2(150, 60), Vector2(150, 305)]
	if extent > 800: route = [Vector2(150, 305), Vector2(1200, 305), Vector2(1200, 1200), Vector2(150, 305)]
	var caps := {"grass": chunks.capacity(chunks.grass_radius), "detail": chunks.capacity(chunks.detail_radius),
		"terrain": chunks.capacity(chunks.terrain_radius), "data": chunks.capacity(chunks.data_radius), "plan": chunks.capacity(chunks.plan_radius)}
	var peaks := {"grass": 0, "detail": 0, "terrain": 0, "data": 0, "plan": 0}
	var unready := 0
	var frames := 0
	for leg in route.size() - 1:
		var a := route[leg]
		var b := route[leg + 1]
		var length := a.distance_to(b)
		var started := Time.get_ticks_usec()
		var travelled := 0.0
		while travelled < length:
			travelled = minf(length, (Time.get_ticks_usec() - started) / 1000000.0 * SPEED)
			var p := a.lerp(b, travelled / length)
			# Like the movement code: only onto ground the streamer has ready.
			if not chunks.walk_ready(p.x, p.y): unready += 1
			world.player.position = Vector3(p.x, world._surface(p.x, p.y) + 0.05, p.y)
			await process_frame
			frames += 1
			var stats := chunks.stats()
			for level in peaks: peaks[level] = maxi(peaks[level], stats[level])
	print("Route: ", frames, " frames; peaks ", peaks, "; capacity ", caps, "; ", chunks.stats())
	for level in peaks:
		check(peaks[level] <= caps[level], "%s tiles peaked at %d, within capacity %d" % [level, peaks[level], caps[level]])
	check(peaks.detail < chunks.tiles_per_side * chunks.tiles_per_side or extent <= 400, "detail tiles stay below the whole field (%d of %d)" % [peaks.detail, chunks.tiles_per_side * chunks.tiles_per_side])
	check(unready == 0, "the explorer was always on generated ground (%d frames not)" % unready)
	var counters: Dictionary = chunks.counters
	check(counters.released_terrain > 0 and counters.released_detail > 0 and counters.released_grass > 0 and counters.dropped_data > 0 and counters.forgotten > 0,
		"tiles were released and regenerated (terrain %d, detail %d, grass %d, data %d, plans %d)" % [counters.released_terrain, counters.released_detail, counters.released_grass, counters.dropped_data, counters.forgotten])
	check(counters.mismatches == 0, "every regenerated tile matched its first version (%d mismatches)" % counters.mismatches)
	check(counters.sync_loads == 0, "nothing had to load synchronously while running (%d)" % counters.sync_loads)
	_check_order(chunks)
	_check_seams(chunks)
	_check_heights(chunks)
	_check_blocking(chunks)
	await _check_pins(chunks)
	print("Streaming: ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)

## Rebuilds tiles from scratch in reverse order, outside the streamer, and compares them
## with the streamer's first versions.
func _check_order(chunks: Chunks) -> void:
	var keys: Array = chunks.signatures.keys().filter(func(key: Vector2i) -> bool: return chunks.signatures[key].has("plan") and chunks.signatures[key].has("grass"))
	keys = keys.slice(0, 12)
	keys.reverse()
	var same := 0
	for key: Vector2i in keys:
		var t := Chunks.Tile.new()
		t.key = key
		t.x0 = key.x * chunks.tile_size
		t.z0 = key.y * chunks.tile_size
		world._tile_data_task(t, true, {})
		var grass := {}
		world._tile_grass_task(t, grass)
		var seen: Dictionary = chunks.signatures[key]
		if hash(t.vh) == seen.data and hash([t.trees, t.rects]) == seen.plan and grass.signature == seen.grass: same += 1
	check(keys.size() >= 8 and same == keys.size(), "%d of %d tiles rebuilt in reverse order match the streamed ones" % [same, keys.size()])

## Neighbor terrain meshes share their edge vertices exactly (position and normal).
func _check_seams(chunks: Chunks) -> void:
	var edges := 0
	var bad := 0
	for t: Chunks.Tile in chunks.tiles.values():
		if t.terrain == null: continue
		for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Chunks.Tile = chunks.tiles.get(t.key + offset)
			if n == null or n.terrain == null: continue
			var mine := _edge(t, offset, true)
			var theirs := _edge(n, offset, false)
			edges += 1
			if mine.size() != theirs.size() or mine.size() == 0: bad += 1
			else:
				for at: Vector2i in mine:
					if not theirs.has(at) or mine[at] != theirs[at]:
						bad += 1
						break
	check(edges >= 4 and bad == 0, "%d shared tile edges match exactly (%d differ)" % [edges, bad])

## Grid vertices on one edge of a tile's terrain mesh: (x, z) -> [height, normal].
func _edge(t: Chunks.Tile, offset: Vector2i, far_side: bool) -> Dictionary:
	var arrays := ((t.terrain as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var line: int = (t.x0 if offset.x != 0 else t.z0) + (32 if far_side else 0)
	var result := {}
	# The grid comes first; the skirt copies after it hang TILE_SKIRT lower.
	var grid: int = (mini(t.x0 + 32, world.extent) - t.x0 + 1) * (mini(t.z0 + 32, world.extent) - t.z0 + 1)
	for i in grid:
		var v := vertices[i]
		if (offset.x != 0 and is_equal_approx(v.x, line)) or (offset.y != 0 and is_equal_approx(v.z, line)):
			result[Vector2i(roundi(v.x), roundi(v.z))] = [v.y, normals[i]]
	return result

## On a shared edge both tiles' cached windows give exactly the same visual and gameplay
## heights, so the surface is continuous wherever a lookup lands.
func _check_heights(chunks: Chunks) -> void:
	var samples := 0
	var differ := 0
	for t: Chunks.Tile in chunks.tiles.values():
		if not t.has_data: continue
		for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Chunks.Tile = chunks.tiles.get(t.key + offset)
			if n == null or not n.has_data: continue
			for i in 64:
				var along := i * 0.5 + 0.13
				var x := float(n.x0) if offset.x != 0 else t.x0 + along
				var z := float(n.z0) if offset.y != 0 else t.z0 + along
				samples += 1
				if world._t_height(t, x, z) != world._t_height(n, x, z) or world._t_gameplay(t, x, z) != world._t_gameplay(n, x, z): differ += 1
	check(samples > 500 and differ == 0, "neighbor tiles agree on %d edge heights (%d differ)" % [samples, differ])

## A tile far from the explorer is not walkable until generated; its heights load on
## demand rather than leaving the explorer to fall.
func _check_blocking(chunks: Chunks) -> void:
	var p: Vector3 = world.player.position
	var target := Vector2(p.x, p.z)
	var away := Vector2(world.extent - 40.0, 40.0) if target.distance_to(Vector2(world.extent - 40.0, 40.0)) > 200.0 else Vector2(40.0, world.extent - 40.0)
	var key := chunks.key_at(away.x, away.y)
	var t: Chunks.Tile = chunks.tiles.get(key)
	check(t == null or not t.planned, "a far tile (%s) is not generated" % key)
	var from := Vector3(away.x - 0.3, 0.0, away.y)
	check(not world._can_walk(Vector3(away.x, 0.0, away.y), from), "stepping onto that tile is refused")
	var h: float = world._surface(away.x, away.y)
	check(is_equal_approx(h, world._expanded_height(away.x, away.y)) or absf(h - world._expanded_height(away.x, away.y)) < 0.25,
		"its surface height loads on demand (%.2f m)" % h)

## Pinned tiles are kept at full detail while the explorer is far away, then released.
func _check_pins(chunks: Chunks) -> void:
	var area := Rect2(world.player.position.x - 10.0, world.player.position.z - 10.0, 20.0, 20.0)
	var id: int = world.pin_battle_area(area)
	var keys: Array[Vector2i] = chunks.pins[id]
	for i in 4: await process_frame
	var away := Vector2(world.player.position.x, world.player.position.z)
	away = Vector2(world.extent - 60.0, 60.0) if away.distance_to(Vector2(world.extent - 60.0, 60.0)) > 250.0 else Vector2(60.0, 60.0)
	world.player.position = Vector3(away.x, world._surface(away.x, away.y), away.y)
	world._warm_around_player()
	for i in 30: await process_frame
	var held := 0
	for key in keys:
		var t: Chunks.Tile = chunks.tiles.get(key)
		if t != null and t.terrain != null and t.detail != null and t.grass != null: held += 1
	check(held == keys.size(), "%d of %d pinned tiles keep detail and grass with the explorer far away" % [held, keys.size()])
	world.release_battle_area(id)
	for i in 30: await process_frame
	var released := 0
	for key in keys:
		var t: Chunks.Tile = chunks.tiles.get(key)
		if t == null or t.detail == null: released += 1
	check(released == keys.size(), "after unpinning, %d of %d tiles are released" % [released, keys.size()])
