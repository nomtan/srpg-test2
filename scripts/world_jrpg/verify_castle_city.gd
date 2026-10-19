extends SceneTree
## Headless checks for JRPGWorldSample3: the explorer's walk from the spawn over the bridge,
## through the gate and up both terraces to the cathedral, plus the solid walls and water.
## godot --headless --path . --script res://scripts/world_jrpg/verify_castle_city.gd
const SCENE = preload("res://samples/JRPGWorldSample3.tscn")
## Waypoints (x, z) walked in order with the explorer's own _can_walk rule.
const ROUTE := [
	Vector2(200, 338), Vector2(200, 316), Vector2(200, 278), Vector2(200, 262), Vector2(200, 242),
	Vector2(196.8, 237), Vector2(196.8, 227), Vector2(200, 224), Vector2(200, 196), Vector2(200, 182),
	Vector2(193, 176), Vector2(192, 160), Vector2(200, 154), Vector2(200, 137.5), Vector2(193.3, 134.7),
	Vector2(190.5, 128), Vector2(193.3, 121.3), Vector2(200, 118.5), Vector2(200, 116.5),
]
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
	else: print("PASS: ", message)

func _initialize() -> void:
	call_deferred("_run")

## Walks a to b in 0.15 m steps; returns how far it got.
func walk(world: Node3D, a: Vector2, b: Vector2) -> Vector2:
	var at := Vector3(a.x, world._surface(a.x, a.y), a.y)
	var steps := ceili(a.distance_to(b) / 0.15)
	for i in steps:
		var q := a.lerp(b, float(i + 1) / steps)
		var next := Vector3(q.x, world._surface(q.x, q.y), q.y)
		if not world._can_walk(next, at): return Vector2(at.x, at.z)
		at = next
	return b

func _run() -> void:
	var world: Node3D = SCENE.instantiate()
	root.add_child(world)
	await process_frame
	# Only the walk rules are under test: roster NPCs stay out of the way.
	world.npcs.clear()
	for i in ROUTE.size() - 1:
		var reached := walk(world, ROUTE[i], ROUTE[i + 1])
		check(reached == ROUTE[i + 1], "walk %s -> %s (stopped at %s)" % [ROUTE[i], ROUTE[i + 1], reached])
	check(absf(world._surface(200, 295) - world.DECK) < 0.01, "bridge deck carries the explorer over the lake")
	check(walk(world, Vector2(200, 295), Vector2(210, 295)).x < 204.0, "bridge parapets keep the explorer on the deck")
	check(walk(world, Vector2(240, 240), Vector2(265, 255)).distance_to(Vector2(265, 255)) > 1.0, "city wall blocks the way out")
	check(walk(world, Vector2(230, 196), Vector2(230, 180)).distance_to(Vector2(230, 180)) > 1.0, "terrace face blocks a climb away from the stairs")
	check(world.get_node_or_null("Aurelia/Gatehouse") != null, "gatehouse built")
	world.queue_free()
	await process_frame
	print("FAILED" if failed else "ALL PASS")
	quit(1 if failed else 0)
