extends SceneTree
## Startup / memory / frame-time benchmark for JRPGWorldSample2 that runs the same way on
## the pre-streaming and the streaming open field, so the two can be compared directly.
##   godot --path . --resolution 1920x1080 -s res://scripts/world_jrpg/bench_open_field.gd -- [options]
## Options: --route=loop|east (the east route needs --field-size=1600), --speed=16 (m/s),
## --out=<file.json>; any other user args (e.g. --field-size=1600) reach the world as usual.
## The explorer is moved along the route by the clock (vsync off, uncapped), so the world
## streams exactly as when running there; the camera follows as in play.
const SCENE := "res://samples/JRPGWorldSample2.tscn"
const ROUTES := {
	# Around the 400 m field: west woods, the northern foothills, the plateau, the village.
	"loop": [Vector2(150, 305), Vector2(80, 250), Vector2(60, 120), Vector2(150, 60), Vector2(300, 60),
		Vector2(370, 140), Vector2(330, 300), Vector2(220, 250), Vector2(150, 305)],
	# Out of the designed square into the extended field and back.
	"east": [Vector2(150, 305), Vector2(150, 700), Vector2(700, 1300), Vector2(1400, 1300), Vector2(1400, 600), Vector2(700, 520)],
}
var world: Node3D
var results := {}

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name): return arg.get_slice("=", 1)
	return fallback

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var started := Time.get_ticks_usec()
	var scene := load(SCENE) as PackedScene
	world = scene.instantiate()
	root.add_child(world)
	results.startup_ms = (Time.get_ticks_usec() - started) / 1000.0
	results.streaming = world.get("streamed") == true
	# Let the streaming world finish its initial ring (the old world is complete already).
	var settle := Time.get_ticks_usec()
	while results.streaming and world.chunks.pending() > 0 and Time.get_ticks_usec() - settle < 60000000:
		await process_frame
	results.settle_ms = (Time.get_ticks_usec() - settle) / 1000.0
	for i in 30: await process_frame
	results.memory_after_start = _memory()
	results.idle = await _measure_idle(300)
	results.route = await _run_route(ROUTES[_arg("route", "loop")], float(_arg("speed", "16")))
	results.memory_after_route = _memory()
	print("BENCH ", JSON.stringify(results))
	var out := _arg("out", "")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  "))
	quit()

func _memory() -> Dictionary:
	return {
		"static_mb": OS.get_static_memory_usage() / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}

## Frame times while the explorer stands at the spawn, looking toward the castle.
func _measure_idle(frames: int) -> Dictionary:
	var times := PackedFloat32Array()
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var stats := _stats(times)
	stats.draw_calls = draws / frames
	return stats

func _run_route(points: Array, speed: float) -> Dictionary:
	var lengths := PackedFloat32Array([0.0])
	for i in points.size() - 1: lengths.append(lengths[-1] + (points[i] as Vector2).distance_to(points[i + 1]))
	var total := lengths[-1]
	var times := PackedFloat32Array()
	var draws := 0.0
	var max_draws := 0.0
	var max_nodes := 0.0
	var max_static := 0.0
	var peaks := {}
	var hitches: Array = []
	var previous := {}
	var started := Time.get_ticks_usec()
	var last := started
	var travelled := 0.0
	while travelled < total:
		travelled = minf(total, (Time.get_ticks_usec() - started) / 1000000.0 * speed)
		var leg := 0
		while leg < points.size() - 2 and lengths[leg + 1] < travelled: leg += 1
		var a: Vector2 = points[leg]
		var b: Vector2 = points[leg + 1]
		var p := a.lerp(b, (travelled - lengths[leg]) / maxf(lengths[leg + 1] - lengths[leg], 0.001))
		world.player.position = Vector3(p.x, world._surface(p.x, p.y) + 0.05, p.y)
		world.player.world_facing = Vector3(b.x - a.x, 0, b.y - a.y).normalized()
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		# Counters only (cheap); tile levels are counted every tenth frame.
		var counters: Dictionary = world.chunks.counters.duplicate() if results.streaming else {}
		if times[-1] > 50.0 and hitches.size() < 20:
			# Where it happened, how much of it was the scripts' process step, and what the
			# streamer did in the frame before.
			var changed := {}
			for key in counters:
				if previous.has(key) and counters[key] != previous[key]: changed[key] = counters[key] - previous[key]
			hitches.append({"ms": times[-1], "at": [roundi(p.x), roundi(p.y)], "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "changed": changed})
		previous = counters
		last = now
		var d := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		draws += d
		max_draws = maxf(max_draws, d)
		max_nodes = maxf(max_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		max_static = maxf(max_static, OS.get_static_memory_usage() / 1048576.0)
		if results.streaming and times.size() % 10 == 0:
			var levels: Dictionary = world.chunks.stats()
			for level in ["plan", "data", "terrain", "detail", "grass"]: peaks[level] = maxi(peaks.get(level, 0), levels[level])
	var stats := _stats(times)
	stats.metres = total
	stats.draw_calls = draws / times.size()
	stats.max_draw_calls = max_draws
	stats.max_nodes = max_nodes
	stats.max_static_mb = max_static
	stats.hitches = hitches
	if results.streaming:
		stats.peak_tiles = peaks
		stats.streaming = world.chunks.stats()
	return stats

func _stats(times: PackedFloat32Array) -> Dictionary:
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	var hitches := 0
	for t in times:
		sum += t
		if t > 50.0: hitches += 1
	return {
		"frames": times.size(), "avg_ms": sum / times.size(),
		"p50_ms": sorted[int(sorted.size() * 0.5)], "p95_ms": sorted[int(sorted.size() * 0.95)],
		"p99_ms": sorted[int(sorted.size() * 0.99)], "max_ms": sorted[-1], "hitches_over_50ms": hitches,
	}
