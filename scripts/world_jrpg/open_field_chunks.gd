extends RefCounted
## Chunk streaming for JRPGWorldSample2 (open_field_world.gd). The field is cut into
## CHUNK (32 m) tiles, and every tile near the explorer (or the camera) is raised step by
## step to the level its distance asks for, then lowered again once it is left behind. A
## tile is released only past its load distance plus `release_margin`, so walking back
## and forth over a boundary never makes a tile flicker in and out.
##   PLAN     heights, biome and water computed once, trees and rocks placed. The dense
##            data may be dropped again; the plan alone feeds the far forest.
##   DATA     the dense height / biome / water window stays cached (collision, queries).
##   TERRAIN  the 1 m terrain mesh (beyond it the far blocks' 8 m mesh).
##   DETAIL   the tree LOD hierarchy, rocks and bushes (beyond it the far forest).
##   GRASS    the grass carpet and its flowers.
## Generation runs as WorkerThreadPool tasks that read only the world's fixed layout and
## their own tile (see open_field_world.gd, "Streaming tiles"); the main thread turns the
## results into nodes in small steps within `frame_budget_ms`. Everything a tile holds is
## a pure function of the world seed and its key, so it comes back identical however
## often and in whatever order it is loaded; `signatures` checks that on every reload.
## Pinned rectangles (pin_rect, e.g. a future battle field) are held at GRASS level.
enum Level { NONE, PLAN, DATA, TERRAIN, DETAIL, GRASS }
## More concurrent tasks than this run slower, not faster: GDScript method calls from
## several threads contend inside the engine (measured: 4 threads ~2x one, 8 slower than 4).
const MAX_THREADS := 4
## Main-thread time a frame may spend sweeping the plan ring (µs).
const SWEEP_BUDGET_US := 1500
const NEIGHBORS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

## A streamed tile. Point windows (gh / vh / water / path) cover the tile plus APRON
## points on each side; open_field_world.gd owns their layout.
class Tile:
	var key: Vector2i
	var x0 := 0
	var z0 := 0
	var gh := PackedFloat32Array()
	var vh := PackedFloat32Array()
	var water := PackedFloat32Array()
	var path := PackedFloat32Array()
	var biome: RefCounted
	var has_data := false
	var planned := false
	## Trees and rocks: [mesh key, Transform3D]; their trunk / boulder obstacles; SRPG cover.
	var trees: Array = []
	var rects: Array[Rect2] = []
	var cover := {}
	## Bushes: [asset, Transform3D], placed with the detail (they read the neighbors' trees).
	var bushes: Array = []
	var bush_cover := {}
	var bushes_planned := false
	var terrain: Node3D
	var detail: Node3D
	var grass: Node3D
	## A worker task is reading or writing this tile; its data must not be dropped.
	var busy := false
	## A finished result is waiting for (or in) its main-thread steps.
	var attaching := false
	## Listed in `wanted`.
	var queued := false
	var pins := 0
	var target: int = Level.NONE
	var keep: int = Level.NONE
	var distance := INF

var host: Node
## Load distances (m, from the explorer, its predicted position and the camera to the
## tile's square).
var grass_radius := 96.0
var detail_radius := 128.0
var terrain_radius := 224.0
var data_radius := 256.0
var plan_radius := 512.0
var release_margin := 32.0
## Seconds of movement the predicted position runs ahead.
var lookahead := 1.2
## How far the camera may trail the explorer and still count as one place (capacity()).
var camera_spread := 32.0
var frame_budget_ms := 3.0
var max_jobs := 4
## Tile grid: keys (0, 0) .. (tiles - 1, tiles - 1).
var tiles_per_side := 0
var tile_size := 32

var tiles: Dictionary = {}
var jobs: Array[Dictionary] = []
## Main-thread steps: [Tile, Callable], run in order within the frame budget.
var steps: Array = []
## Tiles whose target is not met yet, nearest first (refreshed at each retarget).
var wanted: Array[Tile] = []
var wanted_dirty := true
## Where tiles are wanted: the explorer first (it sets the velocity), then e.g. the camera.
var centers: Array[Vector2] = []
var velocity := Vector2.ZERO
## Where and when the targets were last set: near levels (up to DATA) often, the whole
## plan ring (hundreds of tiles on a large field) less often.
var retarget_at: Array[Vector2] = []
var retarget_time := 0.0
var full_retarget_at: Array[Vector2] = []
var full_retarget_time := 0.0
## A plan-ring sweep in progress (see _start_sweep), or empty.
var sweep: Dictionary = {}
## Keys of the tiles holding more than a plan (dense data and up): the only ones that can
## have anything to release.
var near: Dictionary = {}
var pins: Dictionary = {}
var next_pin := 1
## Per key: the signatures a tile produced the first time ("data", "plan", "bushes", "grass").
var signatures: Dictionary = {}
var counters := {"data_jobs": 0, "terrain_jobs": 0, "detail_jobs": 0, "grass_jobs": 0, "sync_loads": 0, "stalls": 0,
	"mismatches": 0, "released_terrain": 0, "released_detail": 0, "released_grass": 0, "dropped_data": 0, "forgotten": 0,
	"max_step_ms": 0.0, "max_frame_ms": 0.0, "max_retarget_ms": 0.0, "max_submit_ms": 0.0, "max_far_ms": 0.0}

func _init(world: Node, extent: int, chunk: int) -> void:
	host = world
	tile_size = chunk
	tiles_per_side = ceili(float(extent) / chunk)
	max_jobs = clampi(OS.get_processor_count() / 4, 1, MAX_THREADS)

func in_field(key: Vector2i) -> bool:
	return key.x >= 0 and key.y >= 0 and key.x < tiles_per_side and key.y < tiles_per_side

func key_at(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori(x / tile_size), 0, tiles_per_side - 1), clampi(floori(z / tile_size), 0, tiles_per_side - 1))

func tile(key: Vector2i) -> Tile:
	var t: Tile = tiles.get(key)
	if t == null:
		t = Tile.new()
		t.key = key
		t.x0 = key.x * tile_size
		t.z0 = key.y * tile_size
		tiles[key] = t
	return t

# --- Queries ------------------------------------------------------------------------

## The tile at (x, z) with its dense data, computed on the spot if it is missing.
func ensure_data(key: Vector2i) -> Tile:
	var t := tile(key)
	if t.has_data: return t
	_finish_job_of(t)
	if not t.has_data:
		counters.sync_loads += 1
		var result := {}
		host._tile_data_task(t, host.obstacles_ready and not t.planned, result)
		_attach_data(t, result)
	return t

## ...with its trees and rocks placed as well.
func ensure_plan(key: Vector2i) -> Tile:
	var t := ensure_data(key)
	if not t.planned:
		_finish_job_of(t)
		if not t.planned:
			counters.sync_loads += 1
			var result := {}
			host._tile_plan_task(t, result)
			_attach_data(t, result)
	return t

## ...with its bushes placed (they read the eight neighbors' trees).
func ensure_bushes(key: Vector2i) -> Tile:
	var t := ensure_plan(key)
	if t.bushes_planned: return t
	for offset in NEIGHBORS:
		if in_field(key + offset): ensure_plan(key + offset)
	_finish_job_of(t)
	if not t.bushes_planned:
		var result := {}
		host._tile_bush_task(t, _neighbor_rects(t), result)
		_store_bushes(t, result)
	return t

## True when the explorer can stand at (x, z): this tile's heights and obstacles and its
## neighbors' obstacles (trunks overhang tile edges) are all in place.
func walk_ready(x: float, z: float) -> bool:
	var key := key_at(x, z)
	var t: Tile = tiles.get(key)
	if t == null or not t.has_data or not t.planned: return false
	for offset in NEIGHBORS:
		var n: Tile = tiles.get(key + offset)
		if in_field(key + offset) and (n == null or not n.planned): return false
	return true

## Obstacles of the tiles around (x, z) (only tiles already planned).
func rects_near(x: float, z: float) -> Array[Rect2]:
	var key := key_at(x, z)
	var list: Array[Rect2] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Tile = tiles.get(key + Vector2i(dx, dz))
			if n != null and n.planned: list.append_array(n.rects)
	return list

## Waits for every running task (the world is going away).
func shutdown() -> void:
	for job in jobs: WorkerThreadPool.wait_for_task_completion(job.task)
	jobs.clear()
	steps.clear()

func pending() -> int:
	if wanted_dirty: _refresh_wanted()
	var count := jobs.size() + steps.size() + (0 if sweep.is_empty() else 1)
	for t in wanted:
		if not _complete(t): count += 1
	return count

func detail_count() -> int:
	var count := 0
	for t: Tile in tiles.values():
		if t.detail != null: count += 1
	return count

func stats() -> Dictionary:
	var levels := {"plan": 0, "data": 0, "terrain": 0, "detail": 0, "grass": 0}
	for t: Tile in tiles.values():
		if t.planned: levels.plan += 1
		if t.has_data: levels.data += 1
		if t.terrain != null: levels.terrain += 1
		if t.detail != null: levels.detail += 1
		if t.grass != null: levels.grass += 1
	var result := counters.duplicate()
	result.merge(levels)
	result.tiles = tiles.size()
	result.max_jobs = max_jobs
	return result

## Upper bound on the tiles a level with this load radius holds at once: a tile is kept
## while its square lies within radius + release_margin of the explorer, of its predicted
## position (a sprint's lookahead ahead) or of the camera trailing it.
func capacity(radius: float) -> int:
	var span := ceili(2.0 * (radius + release_margin + lookahead * 20.0 + camera_spread) / tile_size) + 1
	return span * span

# --- Pins -----------------------------------------------------------------------------

## Holds every tile overlapping `rect` (world XZ) at full detail until unpin(id).
func pin_rect(rect: Rect2) -> int:
	var id := next_pin
	next_pin += 1
	var keys: Array[Vector2i] = []
	for kz in range(floori(rect.position.y / tile_size), floori(rect.end.y / tile_size) + 1):
		for kx in range(floori(rect.position.x / tile_size), floori(rect.end.x / tile_size) + 1):
			var key := Vector2i(kx, kz)
			if not in_field(key): continue
			keys.append(key)
			tile(key).pins += 1
	pins[id] = keys
	retarget_at.clear()
	full_retarget_at.clear()
	return id

func unpin(id: int) -> void:
	for key: Vector2i in pins.get(id, []):
		var t: Tile = tiles.get(key)
		if t: t.pins -= 1
	pins.erase(id)
	retarget_at.clear()
	full_retarget_at.clear()

# --- Frame update ---------------------------------------------------------------------

## Streams around `places` (world XZ: the explorer first, then e.g. the camera); call
## once per frame.
func update(places: Array[Vector2], delta: float) -> void:
	var started := Time.get_ticks_usec()
	if not centers.is_empty() and delta > 0.0:
		var step := (places[0] - centers[0]) / delta
		# A teleport is not a velocity; the tiles around the new spot load directly.
		if step.length() < 60.0: velocity = velocity.lerp(step, clampf(delta * 3.0, 0.0, 1.0))
	centers = places
	retarget_time -= delta
	full_retarget_time -= delta
	if sweep.is_empty() and (_moved(full_retarget_at, 24.0) or full_retarget_time <= 0.0): _start_sweep()
	if _moved(retarget_at, 4.0) or retarget_time <= 0.0: _retarget_near()
	if not sweep.is_empty(): _continue_sweep(started + SWEEP_BUDGET_US)
	var at := Time.get_ticks_usec()
	counters.max_retarget_ms = maxf(counters.max_retarget_ms, (at - started) / 1000.0)
	_collect()
	_submit()
	counters.max_submit_ms = maxf(counters.max_submit_ms, (Time.get_ticks_usec() - at) / 1000.0)
	_run_steps(started)
	counters.max_frame_ms = maxf(counters.max_frame_ms, (Time.get_ticks_usec() - started) / 1000.0)

## Loads everything up to `radius` around `at` before returning (start-up, teleports).
func warm(at: Vector2, radius: float) -> void:
	centers = [at]
	velocity = Vector2.ZERO
	var normal_jobs := max_jobs
	max_jobs = clampi(OS.get_processor_count() - 1, 1, MAX_THREADS)
	_retarget_near()
	_start_sweep()
	_continue_sweep(INF)
	while true:
		_collect()
		_submit()
		while not steps.is_empty(): _run_step(steps.pop_front())
		var done := true
		for t: Tile in tiles.values():
			if t.distance <= radius and not _complete(t):
				done = false
				break
		if done: break
		if not jobs.is_empty(): OS.delay_usec(500)
	max_jobs = normal_jobs

## Every key in `keys` gets its dense data (not its plan) in parallel; used for the
## landmarks, which are built on the cached heights before obstacles exist.
func prefetch(keys: Array[Vector2i]) -> void:
	var normal_jobs := max_jobs
	max_jobs = clampi(OS.get_processor_count() - 1, 1, MAX_THREADS)
	var queue := keys.duplicate()
	while not queue.is_empty() or not jobs.is_empty():
		while jobs.size() < max_jobs and not queue.is_empty():
			var t := tile(queue.pop_back())
			if not t.has_data and not t.busy: _start_job(t, "data")
		_collect()
		while not steps.is_empty(): _run_step(steps.pop_front())
		if not jobs.is_empty(): OS.delay_usec(500)
	max_jobs = normal_jobs

func _moved(at: Array[Vector2], limit: float) -> bool:
	if at.size() != centers.size(): return true
	for i in at.size():
		if at[i].distance_to(centers[i]) > limit: return true
	return false

func _complete(t: Tile) -> bool:
	return not t.busy and not t.attaching and _satisfied(t)

## Everything the tile's target level asks for is in place.
func _satisfied(t: Tile) -> bool:
	if t.target >= Level.PLAN and not t.planned: return false
	if t.target >= Level.DATA and not t.has_data: return false
	if t.target >= Level.TERRAIN and t.terrain == null: return false
	if t.target >= Level.DETAIL and t.detail == null: return false
	if t.target >= Level.GRASS and t.grass == null: return false
	return true

func _level_for(distance: float, extra: float) -> int:
	if distance <= grass_radius + extra: return Level.GRASS
	if distance <= detail_radius + extra: return Level.DETAIL
	if distance <= terrain_radius + extra: return Level.TERRAIN
	if distance <= data_radius + extra: return Level.DATA
	if distance <= plan_radius + extra: return Level.PLAN
	return Level.NONE

## The explorer, its predicted position and the other centers.
func _places() -> Array[Vector2]:
	var places: Array[Vector2] = centers.duplicate()
	places.append(centers[0] + velocity * lookahead)
	return places

## Distance from the nearest of `places` to the tile's square.
func _distance(key: Vector2i, places: Array[Vector2]) -> float:
	var x0 := float(key.x * tile_size)
	var z0 := float(key.y * tile_size)
	var best := INF
	for p in places:
		var dx := maxf(maxf(x0 - p.x, p.x - x0 - tile_size), 0.0)
		var dz := maxf(maxf(z0 - p.y, p.y - z0 - tile_size), 0.0)
		best = minf(best, dx * dx + dz * dz)
	return sqrt(best)

## Tile keys of the box reaching `reach` around `places`: [x0, z0, x1, z1].
func _box(places: Array[Vector2], reach: float) -> Array[int]:
	var lo: Vector2 = places[0]
	var hi: Vector2 = places[0]
	for p in places:
		lo = lo.min(p)
		hi = hi.max(p)
	return [maxi(0, floori((lo.x - reach) / tile_size)), maxi(0, floori((lo.y - reach) / tile_size)),
		mini(tiles_per_side - 1, floori((hi.x + reach) / tile_size)), mini(tiles_per_side - 1, floori((hi.y + reach) / tile_size))]

## Sets a tile's target level (what to load) and keep level (what to hold on to), at most
## `cap`; pins hold it at GRASS. A tile whose target is not met joins `wanted`.
func _set_target(t: Tile, d: float, cap: int) -> void:
	t.distance = d
	t.target = mini(_level_for(d, 0.0), cap)
	t.keep = mini(_level_for(d, release_margin), cap)
	if t.pins > 0:
		t.target = Level.GRASS
		t.keep = Level.GRASS
	if t.target != Level.NONE and not t.queued and not _satisfied(t):
		t.queued = true
		wanted.append(t)
		wanted_dirty = true

## The ring up to the data level, and every tile still holding more than a plan, get their
## targets now: it is small, and it is what the explorer walks on and sees up close.
func _retarget_near() -> void:
	retarget_at = centers.duplicate()
	retarget_time = 0.5
	var places := _places()
	var reach := data_radius + release_margin
	var box := _box(places, reach)
	var seen := {}
	for kz in range(box[1], box[3] + 1):
		for kx in range(box[0], box[2] + 1):
			var key := Vector2i(kx, kz)
			var d := _distance(key, places)
			if d > reach: continue
			seen[key] = true
			_set_target(tile(key), d, Level.GRASS)
	for key: Vector2i in near.keys():
		# Left the near ring: back to the plan ring's levels.
		if not seen.has(key) and tiles.has(key): _set_target(tiles[key], _distance(key, places), Level.PLAN)
	_release()
	wanted_dirty = true

## Starts a sweep over the plan ring beyond the near ring. It runs a few rows a frame
## (_continue_sweep): on a large field the ring holds over a thousand tiles.
func _start_sweep() -> void:
	full_retarget_at = centers.duplicate()
	full_retarget_time = 2.0
	var places := _places()
	var box := _box(places, plan_radius + release_margin)
	sweep = {"places": places, "box": box, "row": box[1], "seen": {}}

func _continue_sweep(deadline: float) -> void:
	var places: Array[Vector2] = sweep.places
	var box: Array[int] = sweep.box
	var seen: Dictionary = sweep.seen
	var inner := data_radius + release_margin
	var reach := plan_radius + release_margin
	while sweep.row <= box[3]:
		var kz: int = sweep.row
		sweep.row = kz + 1
		for kx in range(box[0], box[2] + 1):
			var key := Vector2i(kx, kz)
			var d := _distance(key, places)
			if d > reach and not tiles.has(key): continue
			seen[key] = true
			# The near ring is _retarget_near's.
			if d > inner: _set_target(tile(key), d, Level.PLAN)
		if Time.get_ticks_usec() > deadline: return
	# Swept: tiles past the ring are let go, and those holding nothing are forgotten.
	var forget: Array[Vector2i] = []
	for t: Tile in tiles.values():
		if not seen.has(t.key) and not near.has(t.key): _set_target(t, INF, Level.NONE)
		if t.keep == Level.NONE and not t.busy and not t.attaching and not near.has(t.key): forget.append(t.key)
	for key in forget:
		var t: Tile = tiles[key]
		if t.planned: host._forget_tile(t)
		t.queued = false
		tiles.erase(key)
		counters.forgotten += 1
	sweep = {}

## Lets go of what the near ring's tiles no longer keep: grass, then trees and bushes, then
## the terrain mesh, then the dense data.
func _release() -> void:
	var details: Array[Tile] = []
	var terrains: Array[Tile] = []
	for key: Vector2i in near.keys():
		var t: Tile = tiles[key]
		if t.attaching: continue
		if t.grass != null and t.keep < Level.GRASS:
			host._release_grass(t)
			t.grass = null
			counters.released_grass += 1
		if t.detail != null and t.keep < Level.DETAIL: details.append(t)
		if t.terrain != null and t.keep < Level.TERRAIN: terrains.append(t)
	# The far forest and terrain take the tiles back before their own nodes go away, so
	# nothing ever leaves a hole for a frame.
	if not details.is_empty():
		host._release_details(details)
		for t in details:
			t.detail = null
			counters.released_detail += 1
	if not terrains.is_empty():
		host._release_terrains(terrains)
		for t in terrains:
			t.terrain = null
			counters.released_terrain += 1
	for key: Vector2i in near.keys():
		var t: Tile = tiles[key]
		if t.busy or t.attaching or t.terrain != null or t.detail != null or t.grass != null: continue
		if t.has_data and t.keep < Level.DATA: _drop_data(t)
		if not t.has_data: near.erase(key)

func _drop_data(t: Tile) -> void:
	t.gh = PackedFloat32Array()
	t.vh = PackedFloat32Array()
	t.water = PackedFloat32Array()
	t.path = PackedFloat32Array()
	t.biome = null
	t.has_data = false
	counters.dropped_data += 1

## Drops the tiles whose target is met (or gone) from `wanted` and orders the rest nearest
## first, by a native sort of (distance, index) keys: a scripted comparison over a large
## field's plan ring would cost milliseconds.
func _refresh_wanted() -> void:
	wanted_dirty = false
	var list: Array[Tile] = []
	var order := PackedInt64Array()
	for t in wanted:
		if t.target == Level.NONE or _satisfied(t) or tiles.get(t.key) != t:
			t.queued = false
			continue
		order.append((mini(int(t.distance * 16.0), 1 << 30) << 20) | list.size())
		list.append(t)
	order.sort()
	wanted.clear()
	for key in order: wanted.append(list[key & 0xfffff])

## Starts the next missing step of the nearest wanted tiles: data (and plan), then the
## terrain mesh, then trees and bushes (once every neighbor is planned), then grass.
func _submit() -> void:
	if wanted_dirty: _refresh_wanted()
	var i := 0
	while jobs.size() < max_jobs and i < wanted.size():
		var t := wanted[i]
		i += 1
		if t.busy or t.attaching or t.target == Level.NONE or _satisfied(t): continue
		if not t.planned or (t.target >= Level.DATA and not t.has_data):
			_start_job(t, "data")
		elif t.target >= Level.TERRAIN and t.terrain == null:
			_start_job(t, "terrain")
		elif t.target >= Level.DETAIL and t.detail == null:
			# Bushes avoid the neighbors' trunks: every neighbor must be planned first.
			var ready := true
			for offset in NEIGHBORS:
				var key := t.key + offset
				if not in_field(key): continue
				var n := tile(key)
				if n.planned: continue
				ready = false
				if n.target == Level.NONE:
					n.target = Level.PLAN
					n.keep = maxi(n.keep, Level.PLAN)
					n.distance = t.distance + 1.0
					wanted_dirty = true
				if not n.busy and jobs.size() < max_jobs: _start_job(n, "data")
			if ready: _start_job(t, "detail")
		elif t.target >= Level.GRASS and t.grass == null:
			_start_job(t, "grass")

func _neighbor_rects(t: Tile) -> Array[Rect2]:
	var list: Array[Rect2] = []
	list.append_array(t.rects)
	for offset in NEIGHBORS:
		var n: Tile = tiles.get(t.key + offset)
		if n != null: list.append_array(n.rects)
	return list

func _start_job(t: Tile, kind: String) -> void:
	t.busy = true
	var result := {}
	var task: Callable
	match kind:
		"data":
			counters.data_jobs += 1
			# The plan waits for the landmarks' obstacles (see open_field_world.gd _ready).
			task = host._tile_data_task.bind(t, host.obstacles_ready and not t.planned, result)
		"terrain":
			counters.terrain_jobs += 1
			task = host._tile_terrain_task.bind(t, result)
		"detail":
			counters.detail_jobs += 1
			task = host._tile_detail_task.bind(t, _neighbor_rects(t), result)
		"grass":
			counters.grass_jobs += 1
			task = host._tile_grass_task.bind(t, result)
	jobs.append({"tile": t, "kind": kind, "result": result, "task": WorkerThreadPool.add_task(task, false, "Tile %s %s" % [kind, t.key])})

func _collect() -> void:
	var i := 0
	while i < jobs.size():
		var job := jobs[i]
		if not WorkerThreadPool.is_task_completed(job.task):
			i += 1
			continue
		jobs.remove_at(i)
		_finish(job)

## Waits for the job running on `t`, if any, and takes its result in.
func _finish_job_of(t: Tile) -> void:
	for i in jobs.size():
		if jobs[i].tile == t:
			var job: Dictionary = jobs[i]
			jobs.remove_at(i)
			_finish(job)
			break
	# Steps queued for this tile run now, so its state is settled.
	if t.attaching:
		var rest: Array = []
		for step: Array in steps:
			if step[0] == t: _run_step(step)
			else: rest.append(step)
		steps = rest

func _finish(job: Dictionary) -> void:
	WorkerThreadPool.wait_for_task_completion(job.task)
	var t: Tile = job.tile
	t.busy = false
	var level: int = {"terrain": Level.TERRAIN, "detail": Level.DETAIL, "grass": Level.GRASS}.get(job.kind, Level.NONE)
	if job.kind == "data":
		_attach_data(t, job.result)
		return
	if job.kind == "detail": _store_bushes(t, job.result)
	# Left behind while it was being built: the result is dropped.
	if t.keep < level: return
	t.attaching = true
	var list: Array[Callable] = []
	match job.kind:
		"terrain": list = host._terrain_steps(t, job.result)
		"detail": list = host._detail_steps(t, job.result)
		"grass": list = host._grass_steps(t, job.result)
	for step in list: steps.append([t, step])
	steps.append([t, _attached.bind(t)])

func _attached(t: Tile) -> void:
	t.attaching = false

## Takes a finished data / plan task in: the flags flip here, on the main thread, so
## queries never see a half-written tile.
func _attach_data(t: Tile, result: Dictionary) -> void:
	var seen: Dictionary = signatures.get(t.key, {})
	if result.get("data", false):
		t.has_data = true
		near[t.key] = true
		_check(seen, "data", hash(t.vh))
	if result.get("planned", false):
		t.planned = true
		_check(seen, "plan", hash([t.trees, t.rects]))
	signatures[t.key] = seen
	host._attach_data(t, result)

func _store_bushes(t: Tile, result: Dictionary) -> void:
	if not result.has("bushes") or t.bushes_planned: return
	t.bushes = result.bushes
	t.bush_cover = result.bush_cover
	t.bushes_planned = true
	var seen: Dictionary = signatures.get(t.key, {})
	_check(seen, "bushes", hash(t.bushes))
	signatures[t.key] = seen

## Records a tile product's signature the first time and counts any later difference.
func _check(seen: Dictionary, what: String, value: int) -> void:
	if seen.has(what) and seen[what] != value:
		counters.mismatches += 1
		push_error("Tile signature changed on reload: %s" % what)
	seen[what] = value

func record_grass(t: Tile, value: int) -> void:
	var seen: Dictionary = signatures.get(t.key, {})
	_check(seen, "grass", value)
	signatures[t.key] = seen

func _run_steps(started: int) -> void:
	var budget := int(frame_budget_ms * 1000.0)
	# At least one step a frame, so a slow step can never stall the queue.
	while not steps.is_empty():
		_run_step(steps.pop_front())
		if Time.get_ticks_usec() - started >= budget: break

func _run_step(step: Array) -> void:
	var at := Time.get_ticks_usec()
	(step[1] as Callable).call()
	counters.max_step_ms = maxf(counters.max_step_ms, (Time.get_ticks_usec() - at) / 1000.0)
