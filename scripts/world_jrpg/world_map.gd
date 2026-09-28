extends "res://scripts/world_jrpg/world.gd"
## JRPGWorldSample terrain, landmarks and villagers without its explorer, camera, HUD or input.
## The tactical scene owns those systems and reads this map through apply_to_grid().

@export var spawn_villagers := true
var villager_cells: Array[Vector2i] = []

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	_cache_heights()
	_build_world()
	if spawn_villagers: _spawn_villagers()

func _process(_delta: float) -> void:
	pass

func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass

func _spawn_villagers() -> void:
	story = JSON.parse_string(FileAccess.get_file_as_string(story_path))
	for data: Dictionary in story.npcs:
		var actor := Actor.new()
		actor.palette_name = data.palette
		add_child(actor)
		var point := Vector2(data.position[0], data.position[1])
		actor.position = Vector3(point.x, _surface(point.x, point.y) + 0.05, point.y)
		var label := Label3D.new()
		label.text = data.name
		label.position.y = 2.9
		label.font_size = 24
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		actor.add_child(label)
		villager_cells.append(Vector2i(floori(point.x), floori(point.y)))

## Rebuilds every grid cell from this terrain. Gameplay height is rounded to whole
## steps for jump/LOS rules, while visual_height keeps the exact half-step surface.
func apply_to_grid(grid: GridSystem) -> void:
	for grid_pos: Vector2i in grid.cells:
		var cell := grid.get_cell(grid_pos)
		var center := Vector2(grid_pos.x + 0.5, grid_pos.y + 0.5)
		var surface := _surface(center.x, center.y)
		var level := clampi(roundi(surface), GridSystem.MIN_HEIGHT, GridSystem.MAX_HEIGHT)
		var terrain := _terrain_at(grid_pos.x, grid_pos.y, surface)
		match terrain:
			"water":
				cell.set_surface("water", level, false, 2)
				cell.visual_height = WATER + 0.075
			"lava":
				cell.set_surface("lava", level)
				cell.visual_height = surface
			"obstacle":
				cell.set_surface("obstacle", level, false)
				cell.blocks_movement = true
				cell.blocks_line_of_sight = true
				cell.visual_height = surface
			_:
				cell.set_surface(terrain, level)
				cell.visual_height = surface
		if level != roundi(surface) and terrain != "water":
			# Peaks above the tactical height range stay visible but out of play.
			cell.walkable = false
			cell.blocks_movement = true
	for villager in villager_cells:
		var cell := grid.get_cell(villager)
		if cell:
			cell.walkable = false
			cell.blocks_movement = true
	grid.refresh_surface_levels()

func _terrain_at(x: int, z: int, surface: float) -> String:
	if surface < WATER: return "water"
	if _volcanic(x, z) and Vector2(x + 0.5 - 24, z + 0.5 - 22).length() < 5: return "lava"
	if _blocked(Vector2(x + 0.5, z + 0.5)): return "obstacle"
	if surface > _height(x, z) + 0.01: return "bridge"
	if _volcanic(x, z): return "basalt"
	if _path(x, z): return "road"
	if surface > 21 or (surface > 15 and x < 128): return "snow"
	if surface < 3.5 or absf(x - _river(z)) < 6: return "sand"
	return "grass"

func _blocked(point: Vector2) -> bool:
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(point.x / CHUNK), floori(point.y / CHUNK)), []):
		if rect.has_point(point): return true
	return false
