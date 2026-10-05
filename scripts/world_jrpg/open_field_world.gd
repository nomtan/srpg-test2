extends "res://scripts/world_jrpg/world.gd"
## JRPGWorldSample2: JRPGWorldSample's explorer, camera, HUD, weather and input on a
## smooth open-field map (crag castle and its walled town, windmill hill, ruins, snow peaks).
## Only the map is replaced; one explorer (switchable through character_roster) roams it
## with no NPCs or encounters.
const Props = preload("res://scripts/world_jrpg/open_field_props.gd")
const Biomes = preload("res://scripts/world_jrpg/open_field_biome.gd")
const Vegetation = preload("res://scripts/world_jrpg/open_field_vegetation.gd")
const TERRAIN_SHADER = preload("res://scripts/world_jrpg/open_field_terrain.gdshader")
const LAKE_SHADER = preload("res://scripts/world_jrpg/open_field_water.gdshader")
## Every tree is drawn as an illustration-style leaf-card tree (Vegetation.CARD_SWAP);
## off restores the solid Phase 2 trees and the procedural blossom tree.
@export var card_trees := true
const LAKE := 10.0
const LAKE_CENTER := Vector2(205, 150)
const LAKE_RADIUS := Vector2(100, 64)
## The castle crowns a rocky crag on the lake's south shore; its walled town runs
## down the slope below it, with farmland beyond the gate.
const CRAG := Vector2(205, 121)
const CRAG_TOP := 44.0
const TOWN_RECT := Rect2(180, 146, 50, 54)
const TOWN_PLAZA := Vector2(205, 178)
## The house/001 manor takes the west back-row lot at z = 166, facing the main street.
const TOWN_MANOR_LOT := Vector2(186.5, 166.0)
const TOWN_MANOR_AT := Vector2(186.5, 167.0)
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

## Designed macro landforms. They give the field its silhouette; noise only adds detail.
## 見晴らしの丘 rises this far above the plain within this radius.
const SPAWN_HILL_RISE := 15.0
const SPAWN_HILL_RADIUS := 62.0
## Ridges: start, end, half width, crest height (tapering away at both ends).
const RIDGES := [
	[Vector2(18, 24), Vector2(80, 182), 52.0, 22.0],
	[Vector2(146, 312), Vector2(40, 372), 30.0, 8.0],
]
## East highland plateau overlooking the lake: center, half extents, rise, edge width.
const PLATEAU := [Vector2(362, 118), Vector2(52, 62), 15.0, 34.0]
## Low wet basin on the lake's south-west bay.
const WETLAND := Vector2(130, 208)
## 北嶺アルヴァ and the far ranges beyond the playable square: position, height, radius.
## The first peak stands right behind the castle on the 見晴らしの丘 sightline.
const PEAKS := [
	[Vector2(330, -320), 235.0, 250.0], [Vector2(215, -235), 150.0, 170.0], [Vector2(455, -260), 175.0, 190.0],
	[Vector2(100, -215), 130.0, 170.0], [Vector2(570, -170), 125.0, 170.0], [Vector2(-50, -175), 110.0, 180.0],
	[Vector2(650, 70), 105.0, 190.0], [Vector2(630, 280), 80.0, 170.0], [Vector2(-170, 130), 85.0, 190.0],
	[Vector2(-160, 330), 65.0, 170.0],
]
## Woodland regions as capsules (start, end, radius); the first follows the west ridge.
const WOODS := [
	[Vector2(18, 24), Vector2(80, 182), 58.0], [Vector2(-20, 42), Vector2(420, 46), 60.0],
	[Vector2(300, 348), Vector2(392, 386), 48.0], [Vector2(18, 292), Vector2(58, 392), 42.0],
]
## Deep-forest core of the west woods: start, end.
const DEEP_CORE := [Vector2(28, 58), Vector2(60, 140)]
const FARMLAND_CENTER := Vector2(205, 232)
const FARMLAND_HALF := Vector2(40, 22)
## Designed view corridors kept free of trees: from, to, half width at each end.
## The first is the hero view: 見晴らしの丘 → meadow → lake → town → castle → Alva.
const SIGHTLINES := [
	[SPAWN_HILL + Vector2(-4, 14), CRAG, 18.0, 36.0],
	[Vector2(52, 118), CRAG, 7.0, 16.0],
	[RUINS, CRAG, 8.0, 18.0],
	[VILLAGE, CRAG, 8.0, 18.0],
	[Vector2(330, 372), Vector2(346, 239), 6.0, 12.0],
	[Vector2(120, 40), CRAG, 6.0, 14.0],
]
## Region names for open country, by biome (landmark regions are matched first).
const REGION_NAMES := {
	Biomes.Biome.PLAINS: "翠風の野", Biomes.Biome.FOREST: "緑陰の森", Biomes.Biome.DEEP_FOREST: "深緑の森",
	Biomes.Biome.HIGHLAND: "東の高原", Biomes.Biome.MOUNTAIN: "北嶺の山腹", Biomes.Biome.WETLAND: "湖畔の湿原",
	Biomes.Biome.FARMLAND: "城下の畑", Biomes.Biome.LAKESHORE: "鏡の湖畔",
}
## Battle-grid conventions: 1 m cells; logical heights snap to 1 m steps.
const CELL_SIZE := 1.0
const HEIGHT_STEP := 1.0
## Visual-only micro relief amplitude at ground_roughness 1.0.
const MICRO_RELIEF := 0.18
## Named viewpoints (from, look-at) for captures and the 5 key; `from` heights are above
## the ground and each viewpoint keeps a small tree-free clearing.
const SHOTS := {
	"hero": [Vector3(147, 5.0, 318), Vector3(207, 36, 128)],
	"plains": [Vector3(200, 3.0, 302), Vector3(346, 34, 239)],
	"forest_edge": [Vector3(122, 3.0, 296), Vector3(30, 22, 336)],
	"forest": [Vector3(56, 2.5, 116), Vector3(205, 50, 121)],
	"lakeshore": [Vector3(150, 2.2, 228), Vector3(220, 40, 121)],
	"highland": [Vector3(372, 3.5, 140), Vector3(205, 40, 125)],
	"mountain": [Vector3(372, 6.0, 72), Vector3(318, 130, -300)],
}

var biome := Biomes.new()
## Height without the visual micro relief; the source for gameplay and the battle grid.
var gameplay_cache := PackedFloat32Array()
var biome_debug_map: ImageTexture
var biome_debug := false
var terrain_panel: PanelContainer
var terrain_text: Label
var path_field := PackedFloat32Array()
var path_points: Array = []
var terrain_material: ShaderMaterial
var lake_material: ShaderMaterial
var lamp_material: StandardMaterial3D
var spinning: Array[Node3D] = []
var crystal: Node3D
var conditions_key := -1
var meshes: Dictionary = {}
## Visual vegetation as SRPG cover, per CELL_SIZE cell: "TREE" under a trunk (also an
## obstacle), "LIGHT" under a bush (walkable). Grass and flowers never affect the grid.
var cover_cells: Dictionary = {}

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
		if arg.begins_with("--view=") and SHOTS.has(arg.get_slice("=", 1)): _shot(arg.get_slice("=", 1))
		if arg == "--debug-biome": _set_biome_debug(true)
		if arg == "--debug-terrain": terrain_panel.visible = true
		if arg == "--hide-hud":
			hud.visible = false
			field_weather.controls.visible = false
		if arg.begins_with("--time="):
			field_weather.apply_conditions(maxi(0, ["morning", "day", "evening", "night"].find(arg.get_slice("=", 1))), field_weather.weather_index)
		if arg.begins_with("--weather="):
			field_weather.apply_conditions(field_weather.time_index, maxi(0, ["clear", "rain", "cloudy", "snow"].find(arg.get_slice("=", 1))))
	if "--dump-maps" in args:
		for arg in args:
			if arg.begins_with("--capture-dir="): _dump_maps(arg.get_slice("=", 1))
	if "--sample-capture" in args:
		# Stray keys or stick drift reaching the capture window must not move the explorer
		# (which would snap the camera back to it); only explore mode reads movement.
		mode = "capture"
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var capture_name := "hill"
		var directory := "user://"
		for arg in args:
			if arg.begins_with("--view="): capture_name = arg.get_slice("=", 1)
			if arg.begins_with("--capture-dir="): directory = arg.get_slice("=", 1)
		for arg in args:
			if arg.begins_with("--time=") or arg.begins_with("--weather="): capture_name += "_" + arg.get_slice("=", 1)
		if biome_debug: capture_name += "_biome"
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

## Macro terrain: a gently swelling plain carrying the designed landforms — 見晴らしの丘
## and its shoulder, the west ridge, the east plateau, the wetland basin, the northern
## foothills and the Alva massif — plus a rim of hills at the map edge. The two noise
## terms are only broad swell and meso detail; they no longer decide the shapes.
func _ground(p: Vector2) -> float:
	var h := 16.0 + noise.get_noise_2d(p.x * 0.22, p.y * 0.22) * 5.0 + noise.get_noise_2d(p.x * 1.4 + 500.0, p.y * 1.4 - 300.0) * 1.2
	h += SPAWN_HILL_RISE * _dome(p.distance_to(SPAWN_HILL) / SPAWN_HILL_RADIUS)
	for ridge: Array in RIDGES:
		h += _ridge(p, ridge)
	h += _plateau(p) * PLATEAU[2]
	h -= 3.5 * _dome(p.distance_to(WETLAND) / 34.0)
	# Forested foothills north of the lake, folded into east-west ridges.
	var north := 1.0 - smoothstep(-10.0, 100.0, p.y)
	var crest := 1.0 - absf(noise.get_noise_2d(p.x * 0.45 + 77.0, p.y * 1.1))
	h += north * north * (24.0 + crest * 30.0)
	h += _peaks(p)
	var edge := minf(minf(p.x, SIZE - p.x), minf(SIZE - p.y, p.y + 40.0))
	var rim := 1.0 - smoothstep(-10.0, 55.0, edge)
	h += rim * rim * (20.0 + noise.get_noise_2d(p.x * 0.7, p.y * 0.7 + 99.0) * 12.0) + maxf(0.0, -edge) * 0.08
	return h

## Rounded cosine bump: 1 at t = 0, 0 from t = 1 on, with a soft crest and foot.
func _dome(t: float) -> float:
	return 0.5 + 0.5 * cos(PI * t) if t < 1.0 else 0.0

func _segment_t(p: Vector2, a: Vector2, b: Vector2) -> float:
	return clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)

func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a.lerp(b, _segment_t(p, a, b)))

func _rect_sdf(p: Vector2, center: Vector2, half: Vector2) -> float:
	var q := (p - center).abs() - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)

## A long rounded ridge whose crest tapers off toward both ends and is notched by
## ridged noise, so it reads as one landform with a broken skyline.
func _ridge(p: Vector2, ridge: Array) -> float:
	var t := _segment_t(p, ridge[0], ridge[1])
	var d := p.distance_to((ridge[0] as Vector2).lerp(ridge[1], t))
	var half: float = ridge[2]
	if d >= half: return 0.0
	var taper := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.7, 1.0, t))
	var notch := 0.85 + 0.3 * (1.0 - absf(noise.get_noise_2d(p.x * 0.8 + 200.0, p.y * 0.8)))
	return ridge[3] * taper * notch * _dome(d / half)

## 0..1 plateau mask: a flat top whose escarpment edge wanders with noise.
func _plateau(p: Vector2) -> float:
	var sdf := _rect_sdf(p, PLATEAU[0], PLATEAU[1])
	if sdf > PLATEAU[3] * 0.5 + 14.0: return 0.0
	sdf += noise.get_noise_2d(p.x * 1.2 + 50.0, p.y * 1.2) * 14.0
	return 1.0 - smoothstep(-PLATEAU[3] * 0.5, PLATEAU[3] * 0.5, sdf)

## Distinct peaks (the highest wins, leaving saddles between them) broken into crags
## by ridged noise, so the far skyline has a recognizable silhouette.
func _peaks(p: Vector2) -> float:
	var m := 0.0
	for peak: Array in PEAKS:
		var t: float = 1.0 - p.distance_to(peak[0]) / peak[2]
		if t > 0.0: m = maxf(m, peak[1] * pow(t, 1.25))
	if m <= 0.0: return 0.0
	var crag := 1.0 - absf(noise.get_noise_2d(p.x * 0.45 + 40.0, p.y * 0.45 - 90.0))
	return m * (0.8 + 0.32 * crag)

## Visual-only micro relief (about ±0.05–0.18 m), scaled by the biome's ground roughness
## and calmed on roads, plazas and fields. It never reaches the gameplay height.
func _micro(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var calm := (1.0 - _plaza_weight(p)) * smoothstep(-0.5, 2.0, _path_distance(x, z)) * (1.0 - _field_weight(p) * 0.8)
	if calm <= 0.0: return 0.0
	var amplitude := biome.param_smooth(Biomes.Param.GROUND_ROUGHNESS, x, z) * MICRO_RELIEF * calm
	return (noise.get_noise_2d(x * 7.0 + 1300.0, z * 7.0 - 800.0) * 1.5 + noise.get_noise_2d(x * 19.0, z * 19.0 + 77.0) * 0.5) * amplitude

## Gameplay heights first, then biomes (which read them), then the visual heights that
## the terrain mesh, props and the explorer stand on.
func _cache_heights() -> void:
	var started := Time.get_ticks_msec()
	_build_paths()
	var row := SIZE + 2
	gameplay_cache.resize(row * row)
	for z in range(-1, SIZE + 1):
		for x in range(-1, SIZE + 1):
			gameplay_cache[(z + 1) * row + x + 1] = _expanded_height(x, z)
	biome.bake(SIZE, _biome_signals)
	height_cache.resize(row * row)
	for z in range(-1, SIZE + 1):
		for x in range(-1, SIZE + 1):
			var i := (z + 1) * row + x + 1
			var inside := x >= 0 and z >= 0 and x <= SIZE and z <= SIZE
			height_cache[i] = gameplay_cache[i] + (_micro(x, z) if inside else 0.0)
	print("[JRPGWorld2] Heights and biomes baked in ", Time.get_ticks_msec() - started, " ms")

## Landform signals for the biome system (see Biomes.Landform). Noise warps every boundary
## so no biome edge runs straight.
func _biome_signals(x: float, z: float) -> PackedFloat32Array:
	var p := Vector2(x, z)
	var h := get_gameplay_height(x, z)
	var warp := noise.get_noise_2d(x * 1.6 + 611.0, z * 1.6 - 207.0) + noise.get_noise_2d(x * 4.0 - 90.0, z * 4.0 + 33.0) * 0.35
	var s := PackedFloat32Array()
	s.resize(Biomes.LANDFORM_COUNT)
	var town := 1.0 - smoothstep(-2.0, 6.0, _rect_sdf(p, TOWN_RECT.get_center(), TOWN_RECT.size * 0.5 + Vector2(3, 3)) + warp * 4.0)
	var village := 1.0 - smoothstep(24.0, 34.0, p.distance_to(VILLAGE) + warp * 6.0)
	s[Biomes.Landform.SETTLEMENT] = maxf(maxf(town, village), _mesa_mask(p, 2))
	s[Biomes.Landform.RUINS] = 1.0 - smoothstep(28.0, 42.0, p.distance_to(RUINS) + warp * 7.0)
	s[Biomes.Landform.FARMLAND] = maxf(_field_weight(p), 1.0 - smoothstep(-4.0, 8.0, _rect_sdf(p, FARMLAND_CENTER, FARMLAND_HALF) + warp * 6.0))
	var e := ((p - LAKE_CENTER) / LAKE_RADIUS).length() + warp * 0.07
	s[Biomes.Landform.SHORE] = (1.0 - smoothstep(1.0, 1.25, e)) * (1.0 - smoothstep(LAKE + 3.0, LAKE + 7.0, h))
	s[Biomes.Landform.WETLAND] = 1.0 - smoothstep(22.0, 36.0, p.distance_to(WETLAND) + warp * 8.0)
	s[Biomes.Landform.MOUNTAIN] = smoothstep(44.0, 58.0, h + warp * 8.0)
	var forest := 0.0
	for wood: Array in WOODS:
		var radius: float = wood[2]
		forest = maxf(forest, 1.0 - smoothstep(radius * 0.55, radius, _segment_distance(p, wood[0], wood[1]) + warp * 14.0))
	s[Biomes.Landform.FOREST] = forest
	s[Biomes.Landform.DEEP] = 1.0 - smoothstep(10.0, 30.0, _segment_distance(p, DEEP_CORE[0], DEEP_CORE[1]) + warp * 10.0)
	s[Biomes.Landform.HIGHLAND] = maxf(_plateau(p), smoothstep(38.0, 48.0, h + warp * 6.0))
	return s

## 0..1: how far inside a designed view corridor (SIGHTLINES) this point is.
func _sightline_mask(p: Vector2) -> float:
	var mask := 0.0
	for line: Array in SIGHTLINES:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var t := (p - a).dot(b - a) / (b - a).length_squared()
		if t < 0.0 or t > 1.0: continue
		var width := lerpf(line[2], line[3], t)
		mask = maxf(mask, 1.0 - smoothstep(width * 0.6, width, p.distance_to(a.lerp(b, t))))
	return mask

## Density rhythm: clumps, thinner edges and open glades instead of an even spread.
func _density_rhythm(p: Vector2) -> float:
	var clump := smoothstep(-0.25, 0.25, noise.get_noise_2d(p.x * 1.1 + 1234.0, p.y * 1.1 - 77.0))
	var glade := smoothstep(0.2, 0.34, noise.get_noise_2d(p.x * 0.9 - 300.0, p.y * 0.9 + 140.0))
	return lerpf(0.4, 1.45, clump) * (1.0 - 0.85 * glade)

# --- Terrain query API (SRPG foundation) ------------------------------------------
# Gameplay height = macro + meso terrain; visual height = gameplay + micro relief.
# A future battle grid reads gameplay heights in 1 m cells (CELL_SIZE) and can snap
# them to logical steps (HEIGHT_STEP); exploration keeps using the smooth visual surface.

func get_gameplay_height(x: float, z: float) -> float:
	if gameplay_cache.is_empty() or x < -1.0 or z < -1.0 or x >= SIZE or z >= SIZE:
		return _expanded_height(x, z)
	var ix := floori(x)
	var iz := floori(z)
	var row := SIZE + 2
	var i := (iz + 1) * row + ix + 1
	var fx := x - ix
	var top := lerpf(gameplay_cache[i], gameplay_cache[i + 1], fx)
	return lerpf(top, lerpf(gameplay_cache[i + row], gameplay_cache[i + row + 1], fx), z - iz)

func get_visual_height(x: float, z: float) -> float:
	return _height(x, z)

## Gameplay height snapped to HEIGHT_STEP, e.g. 10 m / 11 m / 12 m tiers for battle.
func get_logical_height(x: float, z: float) -> float:
	return snappedf(get_gameplay_height(x, z), HEIGHT_STEP)

func get_biome_at(x: float, z: float) -> int:
	return biome.biome_at(x, z)

## {Biome: weight} at this point, e.g. {PLAINS: 0.65, FOREST: 0.35}.
func get_biome_weights(x: float, z: float) -> Dictionary:
	return biome.weights_at(x, z)

## Gradient (rise / run) of the gameplay height, free of micro relief.
func get_slope_at(x: float, z: float) -> float:
	return Vector2(get_gameplay_height(x + 0.5, z) - get_gameplay_height(x - 0.5, z), get_gameplay_height(x, z + 0.5) - get_gameplay_height(x, z - 0.5)).length()

## Static walkability with the same limits as _can_walk: map bounds, lake, cliff
## steepness and building/tree/rock obstacles.
func is_walkable_at(x: float, z: float) -> bool:
	if x < 2 or z < 2 or x >= SIZE - 2 or z >= SIZE - 2: return false
	if _surface(x, z) < LAKE + 0.2 or _slope(x, z) > 1.05: return false
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(x / CHUNK), floori(z / CHUNK)), []):
		if rect.has_point(Vector2(x, z)): return false
	return true

func world_position_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.z / CELL_SIZE))

## Cell center on the visible ground, where a unit standing in the cell is placed.
func cell_to_world_position(cell: Vector2i) -> Vector3:
	var x := (cell.x + 0.5) * CELL_SIZE
	var z := (cell.y + 0.5) * CELL_SIZE
	return Vector3(x, get_visual_height(x, z), z)

## Everything a future BattleCell needs for one cell.
func get_cell_info(cell: Vector2i) -> Dictionary:
	var center := cell_to_world_position(cell)
	return {
		"coord": cell, "world_position": center,
		"height": get_gameplay_height(center.x, center.z), "logical_height": get_logical_height(center.x, center.z),
		"biome": get_biome_at(center.x, center.z), "slope": get_slope_at(center.x, center.z),
		"walkable": is_walkable_at(center.x, center.z), "cover": cover_cells.get(cell, "NONE"),
	}

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
	# Named viewpoints (SHOTS) stand in small clearings so their vistas stay open.
	for shot: Array in SHOTS.values():
		var from: Vector3 = shot[0]
		if p.distance_to(Vector2(from.x, from.z)) < 7.0 + margin: return true
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), []):
		if rect.grow(1.0 + margin).has_point(p): return true
	return false

# --- World ------------------------------------------------------------------

func _build_world() -> void:
	var started := Time.get_ticks_msec()
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
	_build_bushes()
	_build_grass()
	_build_labels(landmarks)
	_apply_biome_maps()
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
					var shore := biome.weight(Biomes.Biome.LAKESHORE, x, z) * (1.0 - smoothstep(LAKE + 1.2, LAKE + 3.0, h)) * 0.85
					var sand := maxf(1.0 - smoothstep(LAKE + 0.4, LAKE + 1.6, h), shore) * (1.0 - road)
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

## House/001 model on a stone plinth that absorbs the slope; its arched front (+Z) faces yaw_angle.
func _manor(parent: Node3D, at: Vector2, yaw_angle: float) -> void:
	var half := Vector2(0.95, 0.78) * MANOR_SCALE
	var lo := INF
	var hi := -INF
	for dz in range(-ceili(half.y), ceili(half.y) + 1):
		for dx in range(-ceili(half.x), ceili(half.x) + 1):
			var p := at + Vector2(clampf(dx, -half.x, half.x), clampf(dz, -half.y, half.y)).rotated(-yaw_angle)
			var h := _height(p.x, p.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var floor_y := hi + 0.15
	var root := _anchor(parent, at, yaw_angle, floor_y)
	root.name = "Manor"
	var plinth := floor_y - lo + 0.6
	_part(root, "box", Vector3(half.x * 2.0 + 0.4, plinth, half.y * 2.0 + 0.4), Vector3(0, -plinth * 0.5, 0), Props.rock_material(Color("8f8d86"), 0.3))
	var manor := MANOR_MODEL.instantiate() as Node3D
	manor.scale = Vector3.ONE * MANOR_SCALE
	# The mesh is centred on its origin; lift its base (y = -0.65) onto the plinth.
	manor.position.y = 0.65 * MANOR_SCALE
	root.add_child(manor)
	var extent := (half + Vector2(0.2, 0.2)).rotated(-yaw_angle).abs()
	_block(at, extent)

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
			if Vector2(CRAG.x + side * 18.5, z) == TOWN_MANOR_LOT:
				# Draw the cottage's random numbers anyway so every other house keeps its look.
				for i in 3: rng.randf()
				rng.randi()
				_manor(root, TOWN_MANOR_AT, PI / 2.0)
				continue
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

## Trees and boulders from the biome table: density, broadleaf/conifer mix and size come
## from the blended BiomeData; density rhythm clumps them into groves and glades, and the
## designed sightlines stay open. Trees are the Blender-built Phase 2 set with
## hierarchical LOD (Vegetation.add_tree_chunk): broadleaf A/B/C in the woods, oaks
## favoured on open land, conifer A/B. Blossom trees and boulders are still procedural.
func _build_trees_and_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 5
	var chunks: Dictionary = {}
	var spacing := 4.0
	var grid := biome.param_grid
	var counts := {}
	var z := 0.0
	while z < SIZE:
		var x := 0.0
		while x < SIZE:
			# Every random number is drawn up front so a skipped spot never shifts the rest.
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.75, 1.25)
			var angle := rng.randf() * TAU
			var stretch := rng.randf()
			x += spacing
			var h := _height(p.x, p.y)
			if h < LAKE + 1.0 or _path_distance(p.x, p.y) < 3.0: continue
			if _clear(p) or _near_ramp(p, 0.0): continue
			var c := biome.cell(p.x, p.y)
			if h < grid[c + Biomes.Param.MIN_HEIGHT] or h > grid[c + Biomes.Param.MAX_HEIGHT]: continue
			var slope := get_slope_at(p.x, p.y)
			var open := 1.0 - _sightline_mask(p)
			var tree_chance := grid[c + Biomes.Param.TREE_DENSITY] * _density_rhythm(p)
			# Small broadleaf groves dot the plains.
			var grove := smoothstep(0.28, 0.42, noise.get_noise_2d(p.x * 1.5 + 911.0, p.y * 1.5 - 45.0))
			tree_chance += biome.weight(Biomes.Biome.PLAINS, p.x, p.y) * grove * 0.4
			tree_chance *= open * (1.0 - smoothstep(grid[c + Biomes.Param.MAX_SLOPE] - 0.1, grid[c + Biomes.Param.MAX_SLOPE], slope))
			var rock_chance := (grid[c + Biomes.Param.ROCK_DENSITY] + 0.05 * smoothstep(0.35, 0.75, slope)) * lerpf(0.4, 1.0, open)
			var kind := ""
			var variant := 0
			if roll < tree_chance:
				# Authored assets keep their designed silhouette within 0.85-1.15.
				var variation := remap(size, 0.75, 1.25, 0.85, 1.15) * grid[c + Biomes.Param.TREE_SCALE]
				var broadleaf := grid[c + Biomes.Param.BROADLEAF_WEIGHT]
				var conifer := grid[c + Biomes.Param.CONIFER_WEIGHT] + smoothstep(32.0, 56.0, h) * 0.6
				size *= grid[c + Biomes.Param.TREE_SCALE] * lerpf(0.85, 1.1, stretch)
				# Variants are hashed from the draws above, never drawn, so the layout is stable.
				var shape := fmod(pick * 211.0, 1.0)
				var trunk := 0.45
				if pick * (broadleaf + conifer) < conifer:
					# The broad, drooping spruce (B) takes over toward the highlands.
					kind = "conifer_b" if shape < 0.35 + 0.3 * smoothstep(30.0, 50.0, h) else "conifer_a"
					if card_trees: kind = Vegetation.CARD_SWAP[kind]
					size = variation
				else:
					# Blossom trees are rare accents in the open meadows and on the shore.
					var meadow := biome.weight(Biomes.Biome.PLAINS, p.x, p.y) + biome.weight(Biomes.Biome.LAKESHORE, p.x, p.y)
					var open_land := meadow + biome.weight(Biomes.Biome.FARMLAND, p.x, p.y) + biome.weight(Biomes.Biome.HIGHLAND, p.x, p.y)
					if fmod(pick * 97.0, 1.0) < 0.06 * meadow:
						kind = Vegetation.CARD_SWAP["blossom"] if card_trees else "broadleaf"
						variant = 2
						trunk = 0.5
						if card_trees: size = variation
					else:
						# Oaks stand on open land; the woods are broadleaf A / B / C.
						var oak := fmod(pick * 53.0, 1.0) < 0.1 + 0.45 * clampf(open_land, 0.0, 1.0)
						kind = ("oak_b" if shape < 0.3 else "oak_a") if oak else ["broadleaf_a", "broadleaf_b", "broadleaf_c"][int(shape * 3.0)]
						trunk = 0.65 if oak else 0.45
						if card_trees: kind = Vegetation.CARD_SWAP[kind]
						size = variation
				obstacles.append(Rect2(p - Vector2(trunk, trunk) * size, Vector2(trunk, trunk) * 2.0 * size))
				cover_cells[world_position_to_cell(Vector3(p.x, 0, p.y))] = "TREE"
			elif roll < tree_chance + rock_chance:
				kind = "rock"
				variant = int(pick * 40.0) % 4
				size *= 1.1 if pick < 0.7 else 2.2
				obstacles.append(Rect2(p - Vector2(0.7, 0.7) * size, Vector2(1.4, 1.4) * size))
			else:
				continue
			counts[kind] = counts.get(kind, 0) + 1
			var key := Vector2i(floori(p.x / Vegetation.COARSE_CHUNK), floori(p.y / Vegetation.COARSE_CHUNK))
			if not chunks.has(key): chunks[key] = {}
			var mesh_key := kind if Vegetation.SCENES.has(kind) else "%s_%d" % [kind, variant]
			if not chunks[key].has(mesh_key): chunks[key][mesh_key] = []
			var tall := lerpf(0.6, 0.9, stretch) if kind == "rock" else lerpf(0.95, 1.05, stretch) if Vegetation.SCENES.has(kind) else lerpf(0.9, 1.15, stretch)
			var basis := Basis(Vector3.UP, angle).scaled(Vector3(size, size * tall, size))
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
			if Vegetation.SCENES.has(mesh_key):
				Vegetation.add_tree_chunk(chunk, mesh_key, chunks[key][mesh_key])
				continue
			var kind := mesh_key.get_slice("_", 0)
			var material: Material = Props.rock_material(Color("8d939c"), 0.75) if kind == "rock" else Props.foliage_material()
			_multimesh(chunk, Props.mesh(kind, int(mesh_key.get_slice("_", 1))), chunks[key][mesh_key], material, mesh_key)
	print("[JRPGWorld2] Vegetation: ", counts)

## Bushes along forest edges, in the understory and on road verges (Blender-built
## bush A / B / C). Walkable light cover: no obstacle, recorded in cover_cells.
func _build_bushes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7
	var grid := biome.param_grid
	var chunks: Dictionary = {}
	var counts := {}
	var spacing := 3.0
	var z := 0.0
	while z < SIZE:
		var x := 0.0
		while x < SIZE:
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.85, 1.15)
			var angle := rng.randf() * TAU
			x += spacing
			var h := _height(p.x, p.y)
			var road := _path_distance(p.x, p.y)
			if h < LAKE + 0.8 or road < 2.0 or _clear(p) or _near_ramp(p, 0.0): continue
			var c := biome.cell(p.x, p.y)
			if h > grid[c + Biomes.Param.MAX_HEIGHT] or _slope(p.x, p.y) > 0.6: continue
			if _plaza_weight(p) > 0.3 or _field_weight(p) > 0.3: continue
			# Densest where the woods thin out (forest edge), some understory inside, a few
			# on the road verges; sightlines thin them but low shrubs rarely block a view.
			var trees := grid[c + Biomes.Param.TREE_DENSITY] * _density_rhythm(p)
			var edge := smoothstep(0.04, 0.22, trees) * (1.0 - smoothstep(0.7, 1.1, trees))
			var verge := (1.0 - smoothstep(4.0, 7.0, road)) * (1.0 - biome.weight(Biomes.Biome.SETTLEMENT, p.x, p.y))
			var chance := (0.4 * edge + 0.12 * smoothstep(0.5, 1.0, trees) + 0.1 * verge) * lerpf(0.5, 1.0, 1.0 - _sightline_mask(p))
			if roll >= chance: continue
			var deep := biome.weight(Biomes.Biome.DEEP_FOREST, p.x, p.y) + biome.weight(Biomes.Biome.FOREST, p.x, p.y) * 0.5
			var asset := "bush_c" if pick < 0.2 + 0.4 * deep else ("bush_b" if pick < 0.55 + 0.3 * verge else "bush_a")
			counts[asset] = counts.get(asset, 0) + 1
			var key := Vector2i(floori(p.x / Vegetation.COARSE_CHUNK), floori(p.y / Vegetation.COARSE_CHUNK))
			if not chunks.has(key): chunks[key] = {}
			if not chunks[key].has(asset): chunks[key][asset] = []
			chunks[key][asset].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * size), Vector3(p.x, h - 0.05, p.y)))
			var cell := world_position_to_cell(Vector3(p.x, 0, p.y))
			if not cover_cells.has(cell): cover_cells[cell] = "LIGHT"
		z += spacing
	var root := Node3D.new()
	root.name = "Bushes"
	add_child(root)
	for key: Vector2i in chunks:
		var chunk := Node3D.new()
		chunk.name = "Bushes_%d_%d" % [key.x, key.y]
		root.add_child(chunk)
		for asset: String in chunks[key]:
			Vegetation.add_bush_chunk(chunk, asset, chunks[key][asset])
	print("[JRPGWorld2] Bushes: ", counts)

## Grass clumps and wildflowers, all Blender-built clusters with shader wind. Density per
## biome; within it the cluster type follows the ground: short grass on verges, slopes
## and thin ground, tall / wild grass where it is wet or rocky, and flowers gathered into
## drifts of one kind (star flowers A, cool spikes B where it is wetter).
func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 91
	var root := Node3D.new()
	root.name = "Meadow"
	add_child(root)
	var grid := biome.param_grid
	var cell := 20
	var counts := {}
	for cz in range(0, SIZE, cell):
		for cx in range(0, SIZE, cell):
			var groups := {}
			for z in range(cz, cz + cell):
				for x in range(cx, cx + cell):
					var c := biome.cell(x + 0.5, z + 0.5)
					var drift := lerpf(0.15, 3.0, smoothstep(0.05, 0.4, noise.get_noise_2d(x * 2.2 + 70.0, z * 2.2 - 31.0)))
					var flower_p := 0.03 * grid[c + Biomes.Param.FLOWER_DENSITY] * drift
					var grass_p := minf(0.69 * grid[c + Biomes.Param.GRASS_DENSITY], 1.0 - flower_p)
					var wet := grid[c + Biomes.Param.WETNESS]
					var tall_share := 0.33 + 0.5 * wet
					var top := grid[c + Biomes.Param.MAX_HEIGHT]
					# Per-cell patches: which flower a drift is, where tall grass turns wild,
					# and short-grass lawns that break up the meadow.
					var flower_b := noise.get_noise_2d(x * 1.3 + 300.0, z * 1.3 - 80.0) > 0.12 - 0.5 * wet
					var wild := noise.get_noise_2d(x * 1.7 - 150.0, z * 1.7 + 60.0) > 0.18 - 0.6 * grid[c + Biomes.Param.ROCKINESS]
					var lawn := noise.get_noise_2d(x * 1.9 + 520.0, z * 1.9 + 210.0) > 0.3 or grid[c + Biomes.Param.GRASS_DENSITY] < 0.45
					for k in 3:
						var px := x + rng.randf()
						var pz := z + rng.randf()
						var roll := rng.randf()
						var size := rng.randf_range(0.8, 1.3)
						var angle := rng.randf() * TAU
						if roll >= flower_p + grass_p: continue
						var h := _height(px, pz)
						if h < LAKE + 0.5 or h > top: continue
						var road := _path_distance(px, pz)
						if road < -0.2 or (road < 0.8 and roll > 0.3): continue
						var slope := _slope(px, pz)
						if slope > 0.65 or _plaza_weight(Vector2(px, pz)) > 0.3 or _field_weight(Vector2(px, pz)) > 0.3: continue
						var asset := ""
						if roll < flower_p:
							asset = "flower_grass_b" if flower_b else "flower_grass_a"
						elif fmod(roll * 13.7, 1.0) < tall_share and road > 2.0:
							asset = "grass_wild" if wild else "grass_tall"
						elif lawn or road < 2.2 or slope > 0.45:
							asset = "grass_short"
						else:
							asset = "grass_normal"
						if not groups.has(asset): groups[asset] = []
						groups[asset].append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * remap(size, 0.8, 1.3, 0.85, 1.15)), Vector3(px, h - 0.03, pz)))
			var detail := Node3D.new()
			detail.name = "Meadow_%d_%d" % [cx, cz]
			root.add_child(detail)
			for asset: String in groups:
				counts[asset] = counts.get(asset, 0) + groups[asset].size()
				Vegetation.add_grass_chunk(detail, asset, groups[asset])
	print("[JRPGWorld2] Grass: ", counts)

## Hands the baked biome tint/debug maps to every open-field shader material.
func _apply_biome_maps() -> void:
	var tint := biome.tint_texture()
	biome_debug_map = biome.debug_texture()
	var surface := biome.surface_texture()
	for material in _field_materials():
		material.set_shader_parameter("biome_map", tint)
		material.set_shader_parameter("biome_debug_map", biome_debug_map)
		material.set_shader_parameter("biome_surface_map", surface)
		material.set_shader_parameter("biome_uv_scale", biome.uv_scale())
		material.set_shader_parameter("biome_uv_offset", biome.uv_offset())
		material.set_shader_parameter("biome_extent", float(SIZE))
		material.set_shader_parameter("biome_enabled", 1.0)

func _field_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = Props.shader_materials()
	materials.append_array(Vegetation.shader_materials())
	materials.append(terrain_material)
	return materials

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
		5:
			_shot("hero")
			return
	_update_camera()

## Frames a named SHOTS view. The orbit focus sits 20 m along the line of sight so the
## distance-scaled fog matches what the explorer sees in play.
func _shot(shot_name: String) -> void:
	var shot: Array = SHOTS[shot_name]
	var from: Vector3 = shot[0]
	from.y += maxf(_height(from.x, from.z), LAKE)
	var direction := ((shot[1] as Vector3) - from).normalized()
	overview = true
	distance = 20.0
	focus = from + direction * distance
	yaw = atan2(-direction.x, -direction.z)
	pitch = asin(-direction.y)
	_update_camera()

## Top-down 1 px = 1 m map: biome debug colors over a hillshade, sightlines in white.
func _dump_maps(directory: String) -> void:
	var image := Image.create_empty(SIZE + 1, SIZE + 1, false, Image.FORMAT_RGB8)
	var debug := biome_debug_map.get_image()
	var light := Vector3(-1, 2, -1).normalized()
	for z in SIZE + 1:
		for x in SIZE + 1:
			var normal := Vector3(_cached(x - 1, z) - _cached(x + 1, z), 2.0, _cached(x, z - 1) - _cached(x, z + 1)).normalized()
			var color := debug.get_pixel(mini(x >> 1, debug.get_width() - 1), mini(z >> 1, debug.get_height() - 1))
			if _cached(x, z) < LAKE: color = Color("1d3f66")
			color = color * lerpf(0.45, 1.15, maxf(normal.dot(light), 0.0))
			if _sightline_mask(Vector2(x, z)) > 0.5: color = color.lerp(Color.WHITE, 0.25)
			image.set_pixel(x, z, color)
	for rect in obstacles:
		var center := rect.get_center()
		if center.x >= 0 and center.y >= 0 and center.x <= SIZE and center.y <= SIZE:
			image.set_pixel(int(center.x), int(center.y), Color.WHITE)
	image.save_png(directory.path_join("open_field_map_biome.png"))

func _set_biome_debug(on: bool) -> void:
	biome_debug = on
	for material in _field_materials():
		material.set_shader_parameter("biome_debug", 1.0 if on else 0.0)

func _setup_hud() -> void:
	super._setup_hud()
	for label: Label in hud.find_children("*", "Label", true, false):
		if label.text.begins_with("WASD"):
			label.text += "
5 : 絶景（見晴らしの丘）　F3 : バイオーム表示　F4 : 地形情報"
	terrain_panel = _panel(Vector2.ZERO)
	terrain_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	terrain_panel.offset_left = -284
	terrain_panel.offset_right = -20
	terrain_panel.offset_top = 420
	terrain_text = Label.new()
	terrain_text.add_theme_font_size_override("font_size", 15)
	terrain_panel.add_child(terrain_text)
	terrain_panel.visible = false

func _update_terrain_hud() -> void:
	var p: Vector3 = player.position
	var weights := get_biome_weights(p.x, p.z)
	var ids := weights.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return weights[a] > weights[b])
	var shares: Array[String] = []
	for id: int in ids.slice(0, 3):
		shares.append("%s %.2f" % [Biomes.NAMES[id], weights[id]])
	var cell := world_position_to_cell(p)
	terrain_text.text = "Biome: %s
  %s
Cell: (%d, %d)
Visual Height: %.2fm
Gameplay Height: %.2fm
Logical Height: %.0fm
Slope: %.2f
Walkable: %s" % [
		Biomes.NAMES[get_biome_at(p.x, p.z)], " / ".join(shares), cell.x, cell.y,
		get_visual_height(p.x, p.z), get_gameplay_height(p.x, p.z), get_logical_height(p.x, p.z),
		get_slope_at(p.x, p.z), str(is_walkable_at(p.x, p.z))]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and mode == "explore":
		match event.keycode:
			KEY_F3:
				_set_biome_debug(not biome_debug)
				get_viewport().set_input_as_handled()
				return
			KEY_F4:
				terrain_panel.visible = not terrain_panel.visible
				get_viewport().set_input_as_handled()
				return
			KEY_5:
				_preset(5)
				get_viewport().set_input_as_handled()
				return
	super._unhandled_input(event)

func _region() -> String:
	var p := Vector2(player.position.x, player.position.z)
	if _mesa_mask(p, 2) > 0.5: return "ルミエール城"
	if TOWN_RECT.grow(1.0).has_point(p): return "城下町ルミエール"
	if _mesa_mask(p, 0) > 0.5: return "風車の丘"
	if _mesa_mask(p, 1) > 0.5: return "白霧の遺跡"
	if p.y < 95.0: return "北嶺の麓"
	if p.distance_to(SPAWN_HILL) < 40.0: return "見晴らしの丘"
	if ((p - LAKE_CENTER) / LAKE_RADIUS).length() < 1.3: return "鏡の湖畔"
	return REGION_NAMES.get(get_biome_at(p.x, p.y), "翠風の野")

func _process(delta: float) -> void:
	super._process(delta)
	for hub in spinning: hub.rotation.z += delta * 0.55
	if crystal:
		crystal.rotation.y += delta * 0.6
		crystal.position.y = 4.2 + sin(Time.get_ticks_msec() * 0.0015) * 0.25
	_sync_conditions()
	if terrain_panel.visible: _update_terrain_hud()
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
	materials.append_array(Vegetation.shader_materials())
	materials.append_array([terrain_material, lake_material])
	for material in materials:
		material.set_shader_parameter("wetness", wet)
		material.set_shader_parameter("snow_cover", snow)
	# Wind for the Phase 2 vegetation: livelier in rain and cloud, calmer in snow.
	var wind := [1.0, 1.7, 1.3, 0.6][field_weather.weather_index] as float
	for material in Vegetation.shader_materials():
		material.set_shader_parameter("wind_strength", wind)
	# Aerial perspective: distant land fades toward a cool, time-of-day haze.
	var haze := [Color(0.74, 0.79, 0.86), Color(0.60, 0.73, 0.88), Color(0.78, 0.68, 0.68), Color(0.10, 0.14, 0.24)][field_weather.time_index] as Color
	if field_weather.weather_index != 0: haze = haze.lerp(Color(0.62, 0.66, 0.70) if field_weather.time_index != 3 else Color(0.12, 0.14, 0.2), 0.6)
	terrain_material.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))
	lamp_material.emission_energy_multiplier = 3.0 if field_weather.time_index == 3 else (1.2 if field_weather.time_index == 2 else 0.3)
