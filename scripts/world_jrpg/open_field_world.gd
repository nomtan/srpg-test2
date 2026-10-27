extends "res://scripts/world_jrpg/world.gd"
## JRPGWorldSample2: JRPGWorldSample's explorer, camera, HUD, weather and input on a
## smooth open-field map (crag castle and its walled town, windmill hill, ruins, snow peaks).
## Only the map is replaced; one explorer (switchable through character_roster) roams it
## with no NPCs or encounters. The field streams in 32 m tiles around the explorer (see
## "Streaming tiles" and open_field_chunks.gd); landmarks, water and the far terrain ring
## are built once.
const Props = preload("res://scripts/world_jrpg/open_field_props.gd")
const Biomes = preload("res://scripts/world_jrpg/open_field_biome.gd")
const Vegetation = preload("res://scripts/world_jrpg/open_field_vegetation.gd")
const Meadow = preload("res://scripts/world_jrpg/open_field_meadow.gd")
const Chunks = preload("res://scripts/world_jrpg/open_field_chunks.gd")
const TERRAIN_SHADER = preload("res://scripts/world_jrpg/open_field_terrain.gdshader")
const LAKE_SHADER = preload("res://scripts/world_jrpg/open_field_water.gdshader")
const RIVER_SHADER = preload("res://scripts/world_jrpg/open_field_river.gdshader")
const SPARRING_SCENE = preload("res://scenes/characters/tripo_roster/charcter001.tscn")
const HitFx = preload("res://scripts/world_jrpg/sword_hit_fx.gd")
# How far in front of a struck target (toward the attacker) its hit effect shows.
const HIT_FX_INSET := 0.35
# Hit-stop on a connecting sword-and-shield blow: the attack, everything it struck and the hit effect freeze this long.
const HIT_STOP := 0.15
# On-screen turn of the horizontal slash's hit effect (degrees, counterclockwise): its long points lie closer to the swing.
const SLASH_HIT_TILT := -45.0
# Sparring partner stands this far ahead of the spawn; melee reaches it within MELEE_REACH,
# arrows within BOW_REACH, both only inside the attacker's forward cone.
const SPARRING_OFFSET := 2.5
const MELEE_REACH := 3.0
const BOW_REACH := 30.0
# Field enemies stand in a row centred this far ahead of the spawn, ENEMY_SPACING apart.
const ENEMY_OFFSET := 7.5
const ENEMY_SPACING := 3.2
## Every tree is a low-poly, static anime tree (Vegetation.TOON_SWAP). Off falls back to
## card_trees.
@export var toon_trees := true
## Every tree is drawn as an illustration-style leaf-card tree (Vegetation.CARD_SWAP);
## off restores the solid Phase 2 trees and the procedural blossom tree.
@export var card_trees := true
## Broadleaves and oaks are the seed-driven illustration trees (Vegetation.SEED_TREES, one
## of twelve at random), conifers the seed conifers (Vegetation.SEED_CONIFERS); the blossom
## accents give way to seed broadleaves too.
@export var seed_trees := false
## Grass carpet and flower clusters bend in the wind. Off holds them still (and skips the
## wind math on the GPU); on restores the sway and the gust bands rolling over the meadow.
@export var grass_sway := false
## Enemies (scenes/characters/enemies) placed in a row ahead of the spawn. They flinch, guard and
## fall to the explorer's blows like the sparring partner.
@export var field_enemies: Array[PackedScene] = []
## The first field enemy of each kind (enemy_id) cycles through all of its motions on its own,
## labelled with the clip.
@export var enemy_demo := true
## Streaming (see "Streaming tiles" and open_field_chunks.gd): the field is generated in
## CHUNK tiles around the explorer instead of all at once.
@export_group("Streaming")
## Side (m) of the square field that is streamed and walkable. The designed landforms
## fill the first SIZE (400) m; a larger field carries on into the hills, coast and sea
## beyond them at full detail. Rounded up to whole FAR_STEP cells.
@export var field_size := SIZE
## Load distances (m from the explorer, from where it will be stream_lookahead seconds
## ahead, and from the camera, to a tile's square) for the grass and flowers; the trees,
## rocks and bushes; the 1 m terrain; the cached height / biome / water data; the tree
## plan behind the far forest. The grass, bush and tree-LOD draw ranges end inside them,
## so what is drawn matches the whole-field build. A tile is released only release_margin
## beyond its load distance.
@export var grass_radius := 96.0
@export var detail_radius := 128.0
@export var terrain_radius := 224.0
@export var data_radius := 256.0
@export var far_radius := 512.0
@export var release_margin := 32.0
@export var stream_lookahead := 1.2
## Main-thread time per frame for turning finished tiles into nodes (at least one step).
@export var stream_budget_ms := 3.0
## Worker tasks generating tiles at once (0 = a quarter of the CPU threads, 1 to 4).
@export var stream_jobs := 0
## Everything within this distance of the explorer is loaded before play starts.
@export var startup_radius := 128.0
@export_group("")
const LAKE := 10.0
const LAKE_CENTER := Vector2(205, 150)
const LAKE_RADIUS := Vector2(100, 64)
## 碧の海 fills the east and south-east and runs on past the map edge to the horizon.
const SEA := 2.0
## Coastline from north to south; the sea lies on its east side. Sea cliffs flank the
## river mouth below the plateau; elsewhere sandy beaches run up into the hills.
const COAST := [
	Vector2(600, -260), Vector2(470, -40), Vector2(405, 110), Vector2(380, 190), Vector2(386, 232),
	Vector2(360, 298), Vector2(298, 330), Vector2(245, 362), Vector2(200, 420), Vector2(130, 720),
]
## Water up to an explorer's waist is walkable shallows; anything deeper blocks.
const WADE_DEPTH := 0.9
## Rivers: control points (source first), half width at source and mouth, valley wall
## slope, valley width beyond the banks, waterfall step, the still water it ends in, name.
## 白瀬川 tumbles down the northern foothills into the lake in a chain of falls; 碧瀬川
## leaves the lake eastward and drops off the sea cliffs into 碧の海.
const RIVERS := [
	[[Vector2(300, 12), Vector2(293, 30), Vector2(272, 50), Vector2(260, 72), Vector2(252, 92), Vector2(250, 108)], 3.0, 5.5, 0.8, 10.0, 5.0, LAKE, "白瀬川"],
	[[Vector2(282, 160), Vector2(305, 180), Vector2(330, 192), Vector2(356, 197), Vector2(382, 201), Vector2(410, 206)], 6.5, 8.0, 0.3, 22.0, 4.0, SEA, "碧瀬川"],
]
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
	[Vector2(-170, 130), 85.0, 190.0], [Vector2(-160, 330), 65.0, 170.0],
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
	# Eye-level look into the plains meadow, for the grass carpet.
	"meadow": [Vector3(200, 1.7, 302), Vector3(222, 13.5, 296)],
	"forest_edge": [Vector3(122, 3.0, 296), Vector3(30, 22, 336)],
	"forest": [Vector3(56, 2.5, 116), Vector3(205, 50, 121)],
	"lakeshore": [Vector3(150, 2.2, 228), Vector3(220, 40, 121)],
	"highland": [Vector3(372, 3.5, 140), Vector3(205, 40, 125)],
	"mountain": [Vector3(372, 6.0, 72), Vector3(318, 130, -300)],
	# 白瀬川's chain of falls from below, and 碧瀬川 dropping off the sea cliffs.
	"falls": [Vector3(250, 3.0, 104), Vector3(263, 24, 64)],
	"river_mouth": [Vector3(424, 7.0, 236), Vector3(384, 6, 203)],
	"coast": [Vector3(262, 4.0, 318), Vector3(352, 2, 372)],
}

var biome := Biomes.new()
## Whole-map height without the visual micro relief (the castle city's dense mode; the
## streamed field keeps it per tile); the source for gameplay and the battle grid.
var gameplay_cache := PackedFloat32Array()
var biome_debug_map: ImageTexture
var biome_debug := false
var terrain_panel: PanelContainer
var terrain_text: Label
var path_field := PackedFloat32Array()
var path_points: Array = []
var terrain_material: ShaderMaterial
var lake_material: ShaderMaterial
var sea_material: ShaderMaterial
var river_material: ShaderMaterial
## Baked rivers (see _build_rivers).
var rivers: Array[Dictionary] = []
## Whole-map water surface per grid point (the castle city's dense mode; the streamed field
## keeps it per tile).
var water_cache := PackedFloat32Array()
## The sea side of COAST, closed far out of sight; decides which side of the coast a point is.
var sea_polygon := PackedVector2Array(COAST + [Vector2(130, 1600), Vector2(1800, 1600), Vector2(1800, -1200), Vector2(700, -1200)])
var lamp_material: StandardMaterial3D
var spinning: Array[Node3D] = []
var crystal: Node3D
var conditions_key := -1
var meshes: Dictionary = {}
## Visual vegetation as SRPG cover, per CELL_SIZE cell: "TREE" under a trunk (also an
## obstacle), "LIGHT" under a bush (walkable). Grass and flowers never affect the grid.
## The streamed field keeps it per tile (see _cover_at).
var cover_cells: Dictionary = {}
var sparring_partner: Node3D
var enemies: Array[Node3D] = []
## Streaming state: the field side in use, the tile streamer, the rivers and roads split
## into per-tile buckets, the far terrain blocks and which tiles they leave out.
var streamed := false
var extent := SIZE
var chunks: Chunks
## The landmarks' obstacles are indexed, so tiles may place their trees (see _clear).
var obstacles_ready := false
## Per tile key, the river / road segment rows whose box reaches the tile's window.
var river_buckets: Dictionary = {}
var path_buckets: Dictionary = {}
var far_blocks: Dictionary = {}
## Tiles whose 1 m terrain / whose trees are attached: the far blocks leave them out.
var far_excluded: Dictionary = {}
var forest_excluded: Dictionary = {}
## Tiles whose biome patch is in the shader maps.
var patched: Dictionary = {}
var terrain_root: Node3D
var field_root: Node3D
var meadow_root: Node3D
var far_root: Node3D
var biome_flush_wait := 0.0
## The design tables flattened into packed rows for the per-point functions: worker
## threads reading the nested constant arrays would all contend for the same reference
## counts. Rows: MESAS (center, half extents, top), RAMPS (start, end, half width, mesa),
## RIDGES (start, end, half width, crest), PEAKS (position, height, radius), WOODS (start,
## end, radius), SIGHTLINES (from, to, half widths), PLAZAS (center, radius), FIELDS
## (center, half extents), and the spots kept open (center, radius): CLEARINGS and SHOTS.
var mesa_rows := _rows(MESAS)
var ramp_rows := _rows(RAMPS)
var ridge_rows := _rows(RIDGES)
var peak_rows := _rows(PEAKS)
var wood_rows := _rows(WOODS)
var sightline_rows := _rows(SIGHTLINES)
var plaza_rows := _rows(PLAZAS)
var field_rows := _rows(FIELDS)
var open_rows := _open_rows()
## Rivers flattened for the carving: per sample (all rivers in a row) its river, half
## width, water level, channel depth and ribbon fade; per river its first sample, valley
## width and wall slope. Segment rows: box lo x, lo z, hi x, hi z, a, b, first and last
## sample. Road segment rows: box lo x, lo z, hi x, hi z, a, b, half width.
var river_of := PackedInt32Array()
var river_width := PackedFloat32Array()
var river_level := PackedFloat32Array()
var river_depth := PackedFloat32Array()
var river_fade := PackedFloat32Array()
var river_first := PackedInt32Array()
var river_valley := PackedFloat32Array()
var river_slope := PackedFloat32Array()
var river_rows := PackedFloat64Array()
var path_rows := PackedFloat64Array()

func _ready() -> void:
	noise.seed = world_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 3
	var args := OS.get_cmdline_user_args()
	_start_streaming(args)
	_build_world()
	_setup_view()
	# The forest and town are draw-heavy: two shadow splits over a shorter reach, matched to
	# the tree LODs that still cast.
	field_weather.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	field_weather.sun.directional_shadow_max_distance = Vegetation.SHADOW_REACH
	_setup_hud()
	_spawn_characters()
	_warm_around_player()
	_focus_player()
	# Look over the explorer's shoulder toward the lake castle.
	yaw = -0.3
	pitch = 0.3
	distance = 16.0
	_update_camera()
	for arg in args:
		if arg == "--view=overview": _preset(1)
		if arg == "--view=village": _preset(2)
		if arg == "--view=castle": _preset(3)
		if arg == "--view=ruins": _preset(4)
		if arg.begins_with("--view=") and SHOTS.has(arg.get_slice("=", 1)): _shot(arg.get_slice("=", 1))
		if arg.begins_with("--spawn="):
			# --spawn=x,z puts the explorer there (e.g. to check wading in the shallows).
			var at := arg.get_slice("=", 1).split_floats(",")
			player.position = Vector3(at[0], 0.0, at[1])
			_warm_around_player()
			player.position.y = _surface(at[0], at[1]) + 0.05
			_focus_player()
			_update_camera()
		if arg == "--debug-biome": _set_biome_debug(true)
		if arg == "--debug-terrain": terrain_panel.visible = true
		if arg == "--hide-hud":
			hud.visible = false
			field_weather.controls.visible = false
		if arg.begins_with("--time="):
			field_weather.apply_conditions(maxi(0, ["morning", "day", "evening", "night"].find(arg.get_slice("=", 1))), field_weather.weather_index)
		if arg.begins_with("--weather="):
			field_weather.apply_conditions(field_weather.time_index, maxi(0, ["clear", "rain", "cloudy", "snow"].find(arg.get_slice("=", 1))))
		if arg.begins_with("--season="):
			field_weather.apply_conditions(field_weather.time_index, field_weather.weather_index, maxi(0, ["spring", "summer", "autumn", "winter"].find(arg.get_slice("=", 1))))
	if "--dump-maps" in args:
		for arg in args:
			if arg.begins_with("--capture-dir="): _dump_maps(arg.get_slice("=", 1))
	if "--sample-capture" in args:
		# Stray keys or stick drift reaching the capture window must not move the explorer
		# (which would snap the camera back to it); only explore mode reads movement.
		mode = "capture"
		await get_tree().create_timer(2.0).timeout
		# A capture shows the field as it settles: everything queued is in place first.
		while chunks.pending() > 0: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture_name := "hill"
		var directory := "user://"
		for arg in args:
			if arg.begins_with("--view="): capture_name = arg.get_slice("=", 1)
			if arg.begins_with("--capture-dir="): directory = arg.get_slice("=", 1)
		for arg in args:
			if arg.begins_with("--time=") or arg.begins_with("--weather=") or arg.begins_with("--season="): capture_name += "_" + arg.get_slice("=", 1)
		if biome_debug: capture_name += "_biome"
		get_viewport().get_texture().get_image().save_png(directory.path_join("open_field_%s.png" % capture_name))
		get_tree().quit()

## Lays out the fixed rivers and roads and sets the streamer up. Command-line overrides:
## --field-size=<m>, --stream=<grass>,<detail>,<terrain>,<data>,<far> (radii), --stream-margin=<m>,
## --stream-jobs=<n>, --stream-budget=<ms>, --startup-radius=<m>.
func _start_streaming(args: PackedStringArray) -> void:
	var started := Time.get_ticks_msec()
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--field-size="): field_size = int(value)
		if arg.begins_with("--stream="):
			var radii := value.split_floats(",")
			grass_radius = radii[0]
			detail_radius = radii[1]
			terrain_radius = radii[2]
			data_radius = radii[3]
			far_radius = radii[4]
		if arg.begins_with("--stream-margin="): release_margin = float(value)
		if arg.begins_with("--stream-jobs="): stream_jobs = int(value)
		if arg.begins_with("--stream-budget="): stream_budget_ms = float(value)
		if arg.begins_with("--startup-radius="): startup_radius = float(value)
	streamed = true
	extent = ceili(maxf(field_size, CHUNK) / FAR_STEP) * FAR_STEP
	_build_paths()
	_build_rivers()
	biome.init_maps(extent)
	chunks = Chunks.new(self, extent, CHUNK)
	chunks.grass_radius = grass_radius
	chunks.detail_radius = detail_radius
	chunks.terrain_radius = terrain_radius
	chunks.data_radius = data_radius
	chunks.plan_radius = far_radius
	chunks.release_margin = release_margin
	chunks.lookahead = stream_lookahead
	chunks.frame_budget_ms = stream_budget_ms
	if stream_jobs > 0: chunks.max_jobs = stream_jobs
	print("[JRPGWorld2] Streaming a %d m field in %d x %d tiles (grass %d / detail %d / terrain %d / data %d / far %d m, %d jobs); layout in %d ms" % [
		extent, chunks.tiles_per_side, chunks.tiles_per_side, grass_radius, detail_radius, terrain_radius, data_radius, far_radius, chunks.max_jobs, Time.get_ticks_msec() - started])

static func _rows(table: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for row: Array in table:
		for value: Variant in row:
			if value is Vector2: rows.append_array([value.x, value.y])
			else: rows.append(float(value))
	return rows

static func _open_rows() -> PackedFloat32Array:
	var rows := _rows(CLEARINGS)
	# Named viewpoints (SHOTS) stand in small clearings so their vistas stay open.
	for shot: Array in SHOTS.values():
		var from: Vector3 = shot[0]
		rows.append_array([from.x, from.z, 7.0])
	return rows

## Waits for every running tile task, so none outlives the world it reads.
func _exit_tree() -> void:
	if chunks: chunks.shutdown()

## Loads every tile within startup_radius of the explorer before play goes on.
func _warm_around_player() -> void:
	var started := Time.get_ticks_msec()
	chunks.warm(Vector2(player.position.x, player.position.z), startup_radius)
	print("[JRPGWorld2] Tiles around the explorer ready in ", Time.get_ticks_msec() - started, " ms: ", chunks.stats())

# --- Height field -----------------------------------------------------------

func _expanded_height(x: float, z: float) -> float:
	return _apply_river(Vector2(x, z), _landform_height(x, z))

## Landforms before the river valleys are cut; the rivers' fall profiles are read from it.
func _landform_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _base(p)
	for i in mesa_rows.size() / 5:
		var m := _mesa_mask(p, i)
		if m > 0.0:
			h = maxf(h, lerpf(h, mesa_rows[i * 5 + 4] + noise.get_noise_2d(x * 3.0, z * 3.0) * 0.6, m))
	for i in ramp_rows.size() / 6:
		h = _apply_ramp(p, h, i)
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
	for i in ridge_rows.size() / 6:
		h += _ridge(p, i)
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
	return _apply_sea(p, h)

## Signed distance to the coastline, positive out at sea; noise makes it wander.
func _coast_distance(p: Vector2) -> float:
	var best := INF
	for i in COAST.size() - 1:
		best = minf(best, _segment_distance(p, COAST[i], COAST[i + 1]))
	var side := 1.0 if Geometry2D.is_point_in_polygon(p, sea_polygon) else -1.0
	return best * side + noise.get_noise_2d(p.x * 0.8 + 1700.0, p.y * 0.8) * 7.0

## Sea floor shelving off the coast; sea cliffs around the river mouth, beaches with the
## land rising behind them elsewhere.
func _apply_sea(p: Vector2, h: float) -> float:
	var d := _coast_distance(p)
	var seabed := maxf(SEA + 1.0 - d * 0.14, SEA - 24.0)
	# Flat sand, then slopes up the hinterland; past ~60 m it climbs steeply enough to
	# leave the far ranges untouched.
	var land := SEA + 1.0 - d * 0.05 + maxf(-d - 18.0, 0.0) * 0.45 + maxf(-d - 60.0, 0.0) * 2.0
	var beach := minf(h, seabed if d > 0.0 else land)
	var cliff_foot := minf(seabed, SEA - 2.5)
	var cliff := minf(h, lerpf(cliff_foot, h, 1.0 - smoothstep(-6.0, -1.0, d)))
	return lerpf(beach, cliff, smoothstep(80.0, 130.0, p.y) * (1.0 - smoothstep(225.0, 275.0, p.y)))

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
func _ridge(p: Vector2, index: int) -> float:
	var k := index * 6
	var a := Vector2(ridge_rows[k], ridge_rows[k + 1])
	var b := Vector2(ridge_rows[k + 2], ridge_rows[k + 3])
	var t := _segment_t(p, a, b)
	var d := p.distance_to(a.lerp(b, t))
	var half := ridge_rows[k + 4]
	if d >= half: return 0.0
	var taper := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.7, 1.0, t))
	var notch := 0.85 + 0.3 * (1.0 - absf(noise.get_noise_2d(p.x * 0.8 + 200.0, p.y * 0.8)))
	return ridge_rows[k + 5] * taper * notch * _dome(d / half)

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
	for k in range(0, peak_rows.size(), 4):
		var t := 1.0 - p.distance_to(Vector2(peak_rows[k], peak_rows[k + 1])) / peak_rows[k + 3]
		if t > 0.0: m = maxf(m, peak_rows[k + 2] * pow(t, 1.25))
	if m <= 0.0: return 0.0
	var crag := 1.0 - absf(noise.get_noise_2d(p.x * 0.45 + 40.0, p.y * 0.45 - 90.0))
	return m * (0.8 + 0.32 * crag)

## Landform signals for the biome system (see Biomes.Landform). Noise warps every boundary
## so no biome edge runs straight.
## `h` is the gameplay height at the point.
func _biome_signals(x: float, z: float, h: float) -> PackedFloat32Array:
	var p := Vector2(x, z)
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
	var coast := (1.0 - smoothstep(-30.0, -8.0, _coast_distance(p) + warp * 6.0)) * (1.0 - smoothstep(SEA + 3.0, SEA + 8.0, h))
	s[Biomes.Landform.SHORE] = maxf(s[Biomes.Landform.SHORE], coast)
	s[Biomes.Landform.WETLAND] = 1.0 - smoothstep(22.0, 36.0, p.distance_to(WETLAND) + warp * 8.0)
	s[Biomes.Landform.MOUNTAIN] = smoothstep(44.0, 58.0, h + warp * 8.0)
	var forest := 0.0
	for k in range(0, wood_rows.size(), 5):
		var radius := wood_rows[k + 4]
		var d := _segment_distance(p, Vector2(wood_rows[k], wood_rows[k + 1]), Vector2(wood_rows[k + 2], wood_rows[k + 3]))
		forest = maxf(forest, 1.0 - smoothstep(radius * 0.55, radius, d + warp * 14.0))
	s[Biomes.Landform.FOREST] = forest
	s[Biomes.Landform.DEEP] = 1.0 - smoothstep(10.0, 30.0, _segment_distance(p, DEEP_CORE[0], DEEP_CORE[1]) + warp * 10.0)
	s[Biomes.Landform.HIGHLAND] = maxf(_plateau(p), smoothstep(38.0, 48.0, h + warp * 6.0))
	return s

## 0..1: how far inside a designed view corridor (SIGHTLINES) this point is.
func _sightline_mask(p: Vector2) -> float:
	var mask := 0.0
	for k in range(0, sightline_rows.size(), 6):
		var a := Vector2(sightline_rows[k], sightline_rows[k + 1])
		var b := Vector2(sightline_rows[k + 2], sightline_rows[k + 3])
		var t := (p - a).dot(b - a) / (b - a).length_squared()
		if t < 0.0 or t > 1.0: continue
		var width := lerpf(sightline_rows[k + 4], sightline_rows[k + 5], t)
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
# Every query loads the tile it reads first if the streamer has not (see _data_tile).

func get_gameplay_height(x: float, z: float) -> float:
	if streamed:
		if x < -1.0 or z < -1.0 or x >= extent or z >= extent: return _expanded_height(x, z)
		return _t_gameplay(_data_tile(x, z), x, z)
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
	if streamed: return (_data_tile(x, z).biome as Biomes.Patch).biome_at(x, z)
	return biome.biome_at(x, z)

## {Biome: weight} at this point, e.g. {PLAINS: 0.65, FOREST: 0.35}.
func get_biome_weights(x: float, z: float) -> Dictionary:
	if streamed: return (_data_tile(x, z).biome as Biomes.Patch).weights_at(x, z)
	return biome.weights_at(x, z)

## Gradient (rise / run) of the gameplay height, free of micro relief.
func get_slope_at(x: float, z: float) -> float:
	return Vector2(get_gameplay_height(x + 0.5, z) - get_gameplay_height(x - 0.5, z), get_gameplay_height(x, z + 0.5) - get_gameplay_height(x, z - 0.5)).length()

## Static walkability with the same limits as _can_walk: map bounds, water deeper than
## the waist, cliff steepness and building/tree/rock obstacles.
func is_walkable_at(x: float, z: float) -> bool:
	if x < 2 or z < 2 or x >= extent - 2 or z >= extent - 2: return false
	if _water_depth(x, z) > WADE_DEPTH or _slope(x, z) > 1.05: return false
	if streamed:
		var key := chunks.key_at(x, z)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if chunks.in_field(key + Vector2i(dx, dz)): chunks.ensure_plan(key + Vector2i(dx, dz))
	return not _obstacle_at(Vector2(x, z))

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
		"walkable": is_walkable_at(center.x, center.z), "cover": _cover_at(cell),
		"water_depth": maxf(_water_depth(center.x, center.z), 0.0),
	}

## SRPG cover in a cell: "TREE" under a trunk, "LIGHT" under a bush, else "NONE".
func _cover_at(cell: Vector2i) -> String:
	if not streamed: return cover_cells.get(cell, "NONE")
	var t := chunks.ensure_bushes(chunks.key_at((cell.x + 0.5) * CELL_SIZE, (cell.y + 0.5) * CELL_SIZE))
	return t.cover.get(cell, t.bush_cover.get(cell, "NONE"))

## Keeps every tile overlapping `rect` (world XZ) at full detail and never releases it
## until release_battle_area(id): a battle field stays put while units move over it.
func pin_battle_area(rect: Rect2) -> int:
	return chunks.pin_rect(rect)

func release_battle_area(id: int) -> void:
	chunks.unpin(id)

## 1 on the mesa top, 0 outside, across a ~4 m cliff band with a wobbly outline.
func _mesa_mask(p: Vector2, index: int) -> float:
	var k := index * 5
	var q := (p - Vector2(mesa_rows[k], mesa_rows[k + 1])).abs() - Vector2(mesa_rows[k + 2], mesa_rows[k + 3]) + Vector2(14, 14)
	var sdf := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 14.0
	if sdf > 9.0: return 0.0
	sdf += noise.get_noise_2d(p.x * 2.2 + index * 300.0, p.y * 2.2) * 6.0
	return 1.0 - smoothstep(-2.0, 2.0, sdf)

func _apply_ramp(p: Vector2, h: float, index: int) -> float:
	var k := index * 6
	var a := Vector2(ramp_rows[k], ramp_rows[k + 1])
	var ab := Vector2(ramp_rows[k + 2], ramp_rows[k + 3]) - a
	var width := ramp_rows[k + 4]
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := p.distance_to(a + ab * t)
	if d > width + 5.0: return h
	var ramp_height := lerpf(_base(a), mesa_rows[int(ramp_rows[k + 5]) * 5 + 4], smoothstep(0.0, 1.0, t))
	return lerpf(h, ramp_height, 1.0 - smoothstep(width, width + 5.0, d))

## Elliptical lake distance: < 1 is open water, the shore lies around 1.0-1.3.
func _lake_e(p: Vector2) -> float:
	return ((p - LAKE_CENTER) / LAKE_RADIUS).length() + noise.get_noise_2d(p.x * 0.6 + 900.0, p.y * 0.6) * 0.16

func _apply_lake(p: Vector2, h: float) -> float:
	var e := _lake_e(p)
	if e < 1.5: h = lerpf(LAKE - 7.0, h, smoothstep(0.72, 1.32, e))
	return h

# --- Rivers and water ---------------------------------------------------------

## Lays each river out as 1 m samples and gives it a stepped water profile: the running
## minimum of the banks below the source, snapped down to whole fall steps, so every reach
## sits a little below its banks and drops to the next one in a waterfall. A ford (shallow
## across the whole bed) sits in the middle of the longest reach. The samples are then
## split into segments for the valley carving (_index_rivers).
func _build_rivers() -> void:
	for spec: Array in RIVERS:
		var points := _resample(_smooth(spec[0]), 1.0)
		var count := points.size()
		var step: float = spec[5]
		var end: float = spec[6]
		var widths := PackedFloat32Array()
		var levels := PackedFloat32Array()
		# A river leaving the lake starts at the lake's level; one from the hills at its spring.
		var run := LAKE if end == SEA else INF
		for i in count:
			var c: Vector2 = points[i]
			var width: float = lerpf(spec[1], spec[2], float(i) / (count - 1)) * lerpf(0.45, 1.0, smoothstep(0.0, 16.0, i))
			var side := _river_side(points, i) * width
			var bank := minf(_landform_height(c.x, c.y), minf(_landform_height(c.x + side.x, c.y + side.y), _landform_height(c.x - side.x, c.y - side.y)))
			if end == SEA and _lake_e(c) < 1.5: bank = LAKE + 0.6
			run = minf(run, bank - 0.6)
			widths.append(width)
			levels.append(maxf(end, end + floorf((run - end) / step + 0.001) * step))
		# Ford in the middle of the longest reach above the end water, clear of lake and sea.
		var ford := -100.0
		var longest := 0
		var start := -1
		for i in count + 1:
			var usable := i < count and levels[i] > end + 0.01 and _lake_e(points[i]) > 1.3 and _coast_distance(points[i]) < -12.0
			if usable and start >= 0 and is_equal_approx(levels[i], levels[start]): continue
			if start >= 0 and i - start > longest:
				longest = i - start
				ford = start + longest * 0.5
			start = i if usable else -1
		var depths := PackedFloat32Array()
		var foams := PackedFloat32Array()
		var fades := PackedFloat32Array()
		var foam := 0.0
		for i in count:
			var c: Vector2 = points[i]
			depths.append(lerpf(2.4, 0.6, 1.0 - smoothstep(3.0, 6.0, absf(i - ford))))
			if i > 0: foam = maxf(foam - 0.14, clampf((levels[i - 1] - levels[i]) / 3.0, 0.0, 1.0))
			foams.append(foam)
			# Fade in at the spring and out where the river runs into the lake or the sea.
			var spring := 1.0 if end == SEA else smoothstep(0.0, 5.0, i)
			fades.append(spring * smoothstep(0.75, 0.98, _lake_e(c)) * (1.0 - smoothstep(2.0, 14.0, _coast_distance(c))))
		rivers.append({"name": spec[7], "points": points, "widths": widths, "levels": levels, "depths": depths,
			"foams": foams, "fades": fades, "slope": spec[3], "valley": spec[4], "ford": ford})
		var falls := 0
		for i in range(1, count):
			if levels[i] < levels[i - 1]: falls += 1
		print("[JRPGWorld2] River ", spec[7], ": ", count, " m, ", falls, " falls, ", levels[0], " m -> ", levels[count - 1], " m, ford at ", str(points[int(ford)]) if ford >= 0.0 else "none")
	_index_rivers()

## Flattens the rivers (see river_of) and splits them into the two-sample segments the
## carving measures from, each with the box of grid points it may claim (the reach of its
## channel and valley), bucketed per tile.
func _index_rivers() -> void:
	for r in rivers.size():
		var river := rivers[r]
		var points: Array = river.points
		var widths: PackedFloat32Array = river.widths
		var valley: float = river.valley
		var first := river_of.size()
		river_first.append(first)
		river_valley.append(valley)
		river_slope.append(river.slope)
		for i in points.size():
			river_of.append(r)
			river_width.append(widths[i])
			river_level.append((river.levels as PackedFloat32Array)[i])
			river_depth.append((river.depths as PackedFloat32Array)[i])
			river_fade.append((river.fades as PackedFloat32Array)[i])
		for i in range(0, points.size() - 1, 2):
			var j := mini(i + 2, points.size() - 1)
			var a: Vector2 = points[i]
			var b: Vector2 = points[j]
			var reach := widths[i] + valley + 1.0
			var lo := Vector2i(maxi(0, floori(minf(a.x, b.x) - reach)), maxi(0, floori(minf(a.y, b.y) - reach)))
			var hi := Vector2i(mini(extent, ceili(maxf(a.x, b.x) + reach)), mini(extent, ceili(maxf(a.y, b.y) + reach)))
			_bucket(river_buckets, river_rows.size() / RIVER_ROW, lo, hi)
			river_rows.append_array([lo.x, lo.y, hi.x, hi.y, a.x, a.y, b.x, b.y, first + i, first + j])

## Files segment `index` under every tile whose window (the tile plus APRON) its box
## (lo..hi) reaches, so a tile finds every segment for its points in its own bucket.
func _bucket(buckets: Dictionary, index: int, lo: Vector2i, hi: Vector2i) -> void:
	for kz in range(ceili((lo.y - CHUNK - APRON) / float(CHUNK)), floori((hi.y + APRON) / float(CHUNK)) + 1):
		for kx in range(ceili((lo.x - CHUNK - APRON) / float(CHUNK)), floori((hi.x + APRON) / float(CHUNK)) + 1):
			var key := Vector2i(kx, kz)
			if not buckets.has(key): buckets[key] = PackedInt32Array()
			var list: PackedInt32Array = buckets[key]
			list.append(index)
			buckets[key] = list

func _bucket_at(buckets: Dictionary, x: int, z: int) -> PackedInt32Array:
	return buckets.get(Vector2i(floori(x / float(CHUNK)), floori(z / float(CHUNK))), PackedInt32Array())

## Unit vector across the river at sample i.
func _river_side(points: Array, i: int) -> Vector2:
	var tangent: Vector2 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
	return Vector2(-tangent.y, tangent.x)

## Evenly spaced points along a dense polyline.
func _resample(points: Array, spacing: float) -> Array:
	var out: Array = [points[0]]
	var carry := 0.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		var t := spacing - carry
		while t <= length:
			out.append(a.lerp(b, t / length))
			t += spacing
		carry = length - (t - spacing)
	return out

## The river sample nearest the grid point (x, z) and its distance as (sample, distance),
## sample -1 away from rivers: of the segments in `bucket` whose box holds the point, the
## first (in river and sample order) at the smallest distance. A pure function of the
## point; `bucket` is any tile bucket whose window holds it (see _bucket).
func _river_hit(x: int, z: int, bucket: PackedInt32Array) -> Vector2:
	if not streamed or x < 0 or z < 0 or x > extent or z > extent: return Vector2(-1, INF)
	var best := INF
	var sample := -1
	var p := Vector2(x, z)
	for s in bucket:
		var k := s * RIVER_ROW
		if x < river_rows[k] or z < river_rows[k + 1] or x > river_rows[k + 2] or z > river_rows[k + 3]: continue
		var a := Vector2(river_rows[k + 4], river_rows[k + 5])
		var b := Vector2(river_rows[k + 6], river_rows[k + 7])
		var t := _segment_t(p, a, b)
		var d := p.distance_to(a.lerp(b, t))
		if d < best:
			best = d
			sample = int(river_rows[k + 8]) + roundi(t * (river_rows[k + 9] - river_rows[k + 8]))
	return Vector2(sample, best)

## The river sample nearest the grid point at (x, z) as [river, sample, distance], or []
## away from rivers.
func _river_at(x: float, z: float) -> Array:
	var hit := _river_hit(roundi(x), roundi(z), _bucket_at(river_buckets, roundi(x), roundi(z)))
	if hit.x < 0.0: return []
	var r := river_of[int(hit.x)]
	return [rivers[r], int(hit.x) - river_first[r], hit.y]

## Cuts the channel (a deep middle, wadeable margins) and its valley walls.
func _apply_river(p: Vector2, h: float) -> float:
	var x := roundi(p.x)
	var z := roundi(p.y)
	return _carve_river(h, _river_hit(x, z, _bucket_at(river_buckets, x, z)))

## _apply_river with the river lookup (_river_hit) already made.
func _carve_river(h: float, hit: Vector2) -> float:
	if hit.x < 0.0: return h
	var s := int(hit.x)
	var d := hit.y
	var width := river_width[s]
	var valley := river_valley[river_of[s]]
	if d > width + valley: return h
	var level := river_level[s]
	var target: float
	if d < width:
		target = level - 0.2 - (river_depth[s] - 0.2) * (1.0 - smoothstep(width * 0.2, width, d))
	else:
		target = level - 0.2 + (d - width) * river_slope[river_of[s]]
	return lerpf(minf(h, target), h, smoothstep(width + valley * 0.6, width + valley, d))

## Water surface at a grid point: the sea everywhere low, the lake in its basin, rivers in
## their channels. `hit` is _river_hit at the same point.
func _water_from(x: int, z: int, hit: Vector2) -> float:
	var level := SEA
	if _lake_e(Vector2(x, z)) < 1.45: level = LAKE
	if hit.x >= 0.0 and hit.y < river_width[int(hit.x)] + 2.0:
		level = maxf(level, river_level[int(hit.x)])
	return level

func _water_level(x: float, z: float) -> float:
	if streamed:
		if x < 0.0 or z < 0.0 or x > extent or z > extent: return SEA
		return _t_water_level(_data_tile(x, z), x, z)
	if water_cache.is_empty() or x < 0.0 or z < 0.0 or x > SIZE or z > SIZE: return SEA
	return water_cache[clampi(roundi(z), 0, SIZE) * (SIZE + 1) + clampi(roundi(x), 0, SIZE)]

## How deep the water stands over the visible ground (negative on dry land).
func _water_depth(x: float, z: float) -> float:
	return _water_level(x, z) - _height(x, z)

## Smooth bilinear lookup of the cached height field.
func _height(x: float, z: float) -> float:
	if streamed:
		if x < -1.0 or z < -1.0 or x >= extent or z >= extent: return _expanded_height(x, z)
		return _t_height(_data_tile(x, z), x, z)
	if height_cache.is_empty() or x < -1.0 or z < -1.0 or x >= SIZE or z >= SIZE:
		return _expanded_height(x, z)
	var ix := floori(x)
	var iz := floori(z)
	var row := SIZE + 2
	var i := (iz + 1) * row + ix + 1
	var fx := x - ix
	var top := lerpf(height_cache[i], height_cache[i + 1], fx)
	return lerpf(top, lerpf(height_cache[i + row], height_cache[i + row + 1], fx), z - iz)

## A height for the camera clearance: exact where the tile is cached, the gameplay height
## elsewhere, never loading a tile for it.
func _height_estimate(x: float, z: float) -> float:
	if not streamed: return _height(x, z)
	var t: Chunks.Tile = chunks.tiles.get(chunks.key_at(x, z))
	if t != null and t.has_data and x >= -1.0 and z >= -1.0 and x < extent and z < extent: return _t_height(t, x, z)
	return _expanded_height(x, z)

func _surface(x: float, z: float) -> float:
	return _height(x, z)

func _slope(x: float, z: float) -> float:
	return Vector2(_height(x + 0.5, z) - _height(x - 0.5, z), _height(x, z + 0.5) - _height(x, z - 0.5)).length()

## Up-facing terrain normal from the height field, over the same 1 m span as _slope.
func _ground_normal(x: float, z: float) -> Vector3:
	return Vector3(_height(x - 0.5, z) - _height(x + 0.5, z), 1.0, _height(x, z - 0.5) - _height(x, z + 0.5)).normalized()

func _cached(ix: int, iz: int) -> float:
	if streamed:
		if ix < -1 or iz < -1 or ix > extent or iz > extent: return _expanded_height(ix, iz)
		var t := _data_tile(ix, iz)
		return t.vh[_t_index(t, ix, iz)]
	if ix < -1 or iz < -1 or ix > SIZE or iz > SIZE: return _expanded_height(ix, iz)
	return height_cache[(iz + 1) * (SIZE + 2) + ix + 1]

func _can_walk(p: Vector3, from: Vector3) -> bool:
	if p.x < 2 or p.z < 2 or p.x >= extent - 2 or p.z >= extent - 2: return false
	if streamed and not chunks.walk_ready(p.x, p.z):
		# Never onto ground whose heights or obstacles are not generated yet: the streamer
		# puts the nearest tiles first, so the explorer waits at most a moment at the edge.
		chunks.counters.stalls += 1
		return false
	var h := _surface(p.x, p.z)
	# Shallows are wadeable up to the waist; deeper water blocks.
	if _water_level(p.x, p.z) - h > WADE_DEPTH: return false
	var run := Vector2(p.x - from.x, p.z - from.z).length()
	# Cliffs and steep mountainsides block; ordinary hills are freely walkable.
	if run > 0.0001 and absf(h - _surface(from.x, from.z)) / run > 1.05: return false
	if _obstacle_at(Vector2(p.x, p.z)): return false
	for npc in npcs:
		if p.distance_to(npc.actor.position) < 0.7: return false
	return true

## Building, wall, trunk and boulder bounds at p.
func _obstacle_at(p: Vector2) -> bool:
	for rect: Rect2 in obstacle_chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), []):
		if rect.has_point(p): return true
	if streamed:
		for rect in chunks.rects_near(p.x, p.y):
			if rect.has_point(p): return true
	return false

# --- Roads ------------------------------------------------------------------

## Smooths the roads and splits them into segments, each with the box of grid points whose
## road distance it may lower (6 m around it), bucketed per tile for _path_query.
func _build_paths() -> void:
	for path: Array in PATHS:
		var half: float = path[0]
		var dense := _smooth(path[1])
		path_points.append(dense)
		for i in dense.size() - 1:
			var a: Vector2 = dense[i]
			var b: Vector2 = dense[i + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(6, 6)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(6, 6)
			var box_lo := Vector2i(maxi(0, floori(lo.x)), maxi(0, floori(lo.y)))
			var box_hi := Vector2i(mini(extent, ceili(hi.x)), mini(extent, ceili(hi.y)))
			_bucket(path_buckets, path_rows.size() / PATH_ROW, box_lo, box_hi)
			path_rows.append_array([box_lo.x, box_lo.y, box_hi.x, box_hi.y, a.x, a.y, b.x, b.y, half])

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

## Signed distance from a grid point to the nearest road edge (negative on the road);
## 50 m wherever no road segment reaches. `bucket` as for _river_hit.
func _path_query(x: int, z: int, bucket: PackedInt32Array) -> float:
	var best := 50.0
	var p := Vector2(x, z)
	for s in bucket:
		var k := s * PATH_ROW
		if x < path_rows[k] or z < path_rows[k + 1] or x > path_rows[k + 2] or z > path_rows[k + 3]: continue
		var a := Vector2(path_rows[k + 4], path_rows[k + 5])
		var ab := Vector2(path_rows[k + 6], path_rows[k + 7]) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - path_rows[k + 8])
	return best

## Signed distance to the nearest road edge (negative on the road).
func _path_distance(x: float, z: float) -> float:
	if streamed: return _t_path(_data_tile(x, z), x, z)
	var ix := clampi(roundi(x), 0, SIZE)
	var iz := clampi(roundi(z), 0, SIZE)
	return path_field[iz * (SIZE + 1) + ix]

func _plaza_weight(p: Vector2) -> float:
	var weight := 0.0
	for k in range(0, plaza_rows.size(), 3):
		var center := Vector2(plaza_rows[k], plaza_rows[k + 1])
		var r := plaza_rows[k + 2]
		if p.distance_to(center) > r + 4.0: continue
		var d := p.distance_to(center) + noise.get_noise_2d(p.x * 4.0, p.y * 4.0) * 2.0
		weight = maxf(weight, 1.0 - smoothstep(r - 1.5, r + 1.0, d))
	return weight

func _field_weight(p: Vector2) -> float:
	var weight := 0.0
	for k in range(0, field_rows.size(), 4):
		var q := (p - Vector2(field_rows[k], field_rows[k + 1])).abs() - Vector2(field_rows[k + 2], field_rows[k + 3])
		weight = maxf(weight, 1.0 - smoothstep(-0.8, 0.6, maxf(q.x, q.y)))
	return weight

## Ground kept open: clearings and viewpoints (open_rows), and a metre around `rects`
## (the landmarks' obstacles of p's tile, and for bushes the trunks around it).
func _clear(p: Vector2, rects: Array, margin := 0.0) -> bool:
	for k in range(0, open_rows.size(), 3):
		if p.distance_to(Vector2(open_rows[k], open_rows[k + 1])) < open_rows[k + 2] + margin: return true
	for rect: Rect2 in rects:
		if rect.grow(1.0 + margin).has_point(p): return true
	return false

# --- World ------------------------------------------------------------------

## Areas whose landmarks are built on the visual heights at start-up: castle, town, farms
## and roadside; the windmill village; the ruins. Their tiles load first, in parallel.
const LANDMARK_AREAS := [Rect2(140, 100, 125, 215), Rect2(285, 225, 80, 65), Rect2(40, 195, 65, 50)]

## The fixed world: far terrain, water, landmarks, cliffs and labels. Terrain detail,
## trees, bushes and grass stream in per tile (see "Streaming tiles").
func _build_world() -> void:
	var started := Time.get_ticks_msec()
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	lamp_material = Props.flat(Color("ffd58a"), 0.5, Color("ffb54d"))
	chunks.prefetch(_landmark_tiles())
	var prefetched := Time.get_ticks_msec()
	_build_far_terrain()
	_build_lake()
	_build_sea()
	_build_river_meshes()
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	_build_castle(landmarks)
	_build_town(landmarks)
	_build_village(landmarks)
	_build_ruins(landmarks)
	_build_roadside(landmarks)
	_index_obstacles()
	# Trees and bushes keep clear of the landmarks' obstacles, so they wait for them.
	obstacles_ready = true
	_build_cliffs()
	terrain_root = Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	field_root = Node3D.new()
	field_root.name = "Field"
	add_child(field_root)
	meadow_root = Node3D.new()
	meadow_root.name = "Meadow"
	add_child(meadow_root)
	_build_labels(landmarks)
	_apply_biome_maps()
	_preload_vegetation()
	print("[JRPGWorld2] Built the fixed world in ", Time.get_ticks_msec() - started, " ms (landmark tiles ", prefetched - started, " ms); seed=", world_seed)

## Loads every vegetation mesh the tiles can ask for (and splits the leaf cards) now, so
## a kind met for the first time while streaming never stalls a frame.
func _preload_vegetation() -> void:
	var dummy := Node3D.new()
	var assets := {}
	for kind in Vegetation.TREES + ([] if seed_trees else ["blossom"]):
		for roll in 16: assets[_tree_asset(kind, roll / 16.0) if kind != "blossom" or toon_trees or card_trees else ""] = true
	assets.erase("")
	var one := [Transform3D()]
	for asset: String in assets:
		Vegetation.add_tree_chunk(dummy, asset, one)
		Vegetation.add_far_trees(dummy, asset, one)
	for asset in Vegetation.BUSHES: Vegetation.add_bush_chunk(dummy, asset, one)
	for asset in Vegetation.FLOWERS: Vegetation.add_grass_chunk(dummy, asset, one, [Vector3.UP])
	Meadow.add_cell(dummy, one, [Vector3.UP], "Grass")
	for v in 4: Props.mesh("rock", v)
	dummy.free()

func _landmark_tiles() -> Array[Vector2i]:
	var areas: Array = LANDMARK_AREAS.duplicate()
	for entry: Array in LABELS: areas.append(Rect2(entry[1], Vector2.ONE))
	var keys: Array[Vector2i] = []
	for area: Rect2 in areas:
		for kz in range(floori(area.position.y / CHUNK), floori(area.end.y / CHUNK) + 1):
			for kx in range(floori(area.position.x / CHUNK), floori(area.end.x / CHUNK) + 1):
				var key := Vector2i(kx, kz)
				if chunks.in_field(key) and not key in keys: keys.append(key)
	return keys

## Runs body(index) for every index below count on the worker pool and waits for all.
func _parallel(count: int, body: Callable) -> void:
	if count <= 0: return
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(body, count, Chunks.MAX_THREADS, true, "JRPGWorld2"))

## Far terrain at FAR_STEP: a fixed ring of hills and ranges around the field, and inside
## it one mesh per FAR_BLOCK x FAR_BLOCK tiles covering every tile whose 1 m terrain is not
## attached, with skirts against the attached ones (_rebuild_far_terrain).
func _build_far_terrain() -> void:
	far_root = Node3D.new()
	far_root.name = "FarField"
	add_child(far_root)
	_build_far_ring()
	var side := ceili(float(chunks.tiles_per_side) / FAR_BLOCK)
	var blocks: Array[Dictionary] = []
	for bz in side:
		for bx in side: blocks.append({"key": Vector2i(bx, bz)})
	_parallel(blocks.size(), func(i: int) -> void: _far_block_arrays(blocks[i]))
	for block in blocks:
		var key: Vector2i = block.key
		var terrain := MeshInstance3D.new()
		terrain.name = "FarTerrain_%d_%d" % [key.x, key.y]
		terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far_root.add_child(terrain)
		var forest := Node3D.new()
		forest.name = "FarForest_%d_%d" % [key.x, key.y]
		far_root.add_child(forest)
		block.terrain = terrain
		block.forest = forest
		block.terrain_dirty = true
		block.forest_dirty = false
		far_blocks[key] = block
	_update_far()

## Coarse hills and ranges beyond the field, so the horizon is never empty. Like the
## blocks it samples the gameplay heights; it reaches one FAR_STEP into the field, 0.4 m
## low, under the blocks' edges.
func _build_far_ring() -> void:
	var step := FAR_STEP
	var lo := -480
	var count := (extent + 960) / step + 1
	var rows: Array[Dictionary] = []
	for j in count: rows.append({})
	_parallel(count, func(j: int) -> void:
		var heights := PackedFloat32Array()
		var depths := PackedFloat32Array()
		heights.resize(count)
		depths.resize(count)
		var z := float(lo + j * step)
		for i in count:
			var x := float(lo + i * step)
			var inside := x >= 0 and x <= extent and z >= 0 and z <= extent
			# Deep inside, the blocks cover the field; the ring's normals need two steps in.
			if inside and x > 2 * step and z > 2 * step and x < extent - 2 * step and z < extent - 2 * step: continue
			var h := _expanded_height(x, z) - 0.4 if inside else _expanded_height(x, z)
			# Inland the far hills keep clear of the lake level; seaward they shelve under the sea.
			if not inside and _coast_distance(Vector2(x, z)) < -40.0: h = maxf(h, LAKE + 2.0)
			heights[i] = h
			depths[i] = (_water_from(int(x), int(z), _river_hit(int(x), int(z), _bucket_at(river_buckets, int(x), int(z)))) if inside else SEA) - h
		rows[j].heights = heights
		rows[j].depths = depths)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for j in count:
		for i in count:
			vertices.append(Vector3(lo + i * step, (rows[j].heights as PackedFloat32Array)[i], lo + j * step))
			colors.append(Color(0, 0, 0, 0))
			uvs.append(Vector2((rows[j].depths as PackedFloat32Array)[i], 0.0))
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
			if x >= step and x + step <= extent - step and z >= step and z + step <= extent - step: continue
			var k := j * count + i
			indices.append_array([k, k + 1, k + count, k + 1, k + count + 1, k + count])
	var far := MeshInstance3D.new()
	far.name = "FarTerrain"
	far.mesh = _array_mesh(vertices, normals, colors, indices, terrain_material, uvs)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_root.add_child(far)

## Worker task: one far block's vertex data at FAR_STEP (gameplay heights, the terrain
## shader's road / sand / plaza / field weights, water depth), plus a copy of every vertex
## FAR_SKIRT lower for the skirts.
func _far_block_arrays(block: Dictionary) -> void:
	var key: Vector2i = block.key
	var x0 := key.x * FAR_BLOCK * CHUNK
	var z0 := key.y * FAR_BLOCK * CHUNK
	var nx := (mini(x0 + FAR_BLOCK * CHUNK, extent) - x0) / FAR_STEP + 1
	var nz := (mini(z0 + FAR_BLOCK * CHUNK, extent) - z0) / FAR_STEP + 1
	var row := nx + 2
	var heights := PackedFloat32Array()
	heights.resize(row * (nz + 2))
	for j in nz + 2:
		for i in row: heights[j * row + i] = _expanded_height(x0 + (i - 1) * FAR_STEP, z0 + (j - 1) * FAR_STEP)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for j in nz:
		for i in nx:
			var x := x0 + i * FAR_STEP
			var z := z0 + j * FAR_STEP
			var k := (j + 1) * row + i + 1
			var h := heights[k]
			vertices.append(Vector3(x, h, z))
			var normal := Vector3(heights[k - 1] - heights[k + 1], 2.0 * FAR_STEP, heights[k - row] - heights[k + row])
			normals.append(normal.normalized())
			var above := h - _water_from(x, z, _river_hit(x, z, _bucket_at(river_buckets, x, z)))
			var road := 1.0 - smoothstep(-0.4, 1.0, _path_query(x, z, _bucket_at(path_buckets, x, z)) + noise.get_noise_2d(x * 5.0, z * 5.0) * 0.8)
			var shore := Biomes.compose(_biome_signals(x, z, h))[Biomes.Biome.LAKESHORE] * (1.0 - smoothstep(1.2, 3.0, above)) * 0.85
			# Same steepness measure as the 1 m tiles (height change over 2 m).
			var steep := smoothstep(1.4, 2.4, Vector2(normal.x, normal.z).length() / FAR_STEP)
			var sand := maxf(1.0 - smoothstep(0.4, 1.6, above), shore) * (1.0 - road) * (1.0 - steep)
			colors.append(Color(road, sand, _plaza_weight(Vector2(x, z)), _field_weight(Vector2(x, z)) * (1.0 - road)))
			uvs.append(Vector2(-above, 0.0))
	for v in nx * nz:
		vertices.append(vertices[v] - Vector3(0, FAR_SKIRT, 0))
		normals.append(normals[v])
		colors.append(colors[v])
		uvs.append(uvs[v])
	block.nx = nx
	block.nz = nz
	block.vertices = vertices
	block.normals = normals
	block.colors = colors
	block.uvs = uvs

## The far block's mesh over its tiles without attached terrain; along an edge shared
## with an attached tile a two-sided skirt hangs down, closing the crack between the
## coarse and the 1 m surface.
func _rebuild_far_terrain(block: Dictionary) -> void:
	block.terrain_dirty = false
	var nx: int = block.nx
	var nz: int = block.nz
	var per := CHUNK / FAR_STEP
	var indices := PackedInt32Array()
	var bkey: Vector2i = block.key
	for tz in FAR_BLOCK:
		for tx in FAR_BLOCK:
			var key := bkey * FAR_BLOCK + Vector2i(tx, tz)
			if not chunks.in_field(key) or far_excluded.has(key): continue
			var i0 := tx * per
			var j0 := tz * per
			var i1 := mini(i0 + per, nx - 1)
			var j1 := mini(j0 + per, nz - 1)
			for j in range(j0, j1):
				for i in range(i0, i1):
					var k := j * nx + i
					indices.append_array([k, k + 1, k + nx, k + 1, k + nx + 1, k + nx])
			if far_excluded.has(key + Vector2i(-1, 0)): _far_skirt(indices, nx * nz, j0 * nx + i0, j1 * nx + i0, nx)
			if far_excluded.has(key + Vector2i(1, 0)): _far_skirt(indices, nx * nz, j0 * nx + i1, j1 * nx + i1, nx)
			if far_excluded.has(key + Vector2i(0, -1)): _far_skirt(indices, nx * nz, j0 * nx + i0, j0 * nx + i1, 1)
			if far_excluded.has(key + Vector2i(0, 1)): _far_skirt(indices, nx * nz, j1 * nx + i0, j1 * nx + i1, 1)
	var terrain: MeshInstance3D = block.terrain
	terrain.mesh = null if indices.is_empty() else _array_mesh(block.vertices, block.normals, block.colors, indices, terrain_material, block.uvs)

## A two-sided vertical strip from grid vertex `from` to `to` (advancing by `stride`) down
## to the skirt copies `skirt` vertices later.
func _far_skirt(indices: PackedInt32Array, skirt: int, from: int, to: int, stride: int) -> void:
	var a := from
	while a < to:
		var b := a + stride
		indices.append_array([a, b, a + skirt, b, b + skirt, a + skirt, a, a + skirt, b, b, a + skirt, b + skirt])
		a = b

## The far block's lightweight forest: the farthest tree LOD (and the rocks) of every
## planned tile whose own trees are not attached, without shadows.
func _rebuild_far_forest(block: Dictionary) -> void:
	block.forest_dirty = false
	var root: Node3D = block.forest
	for child in root.get_children(): child.free()
	var groups := {}
	var bkey: Vector2i = block.key
	for tz in FAR_BLOCK:
		for tx in FAR_BLOCK:
			var key := bkey * FAR_BLOCK + Vector2i(tx, tz)
			var t: Chunks.Tile = chunks.tiles.get(key)
			if t == null or not t.planned or forest_excluded.has(key): continue
			for entry: Array in t.trees: (groups.get_or_add(entry[0], []) as Array).append(entry[1])
	for mesh_key: String in groups:
		if Vegetation.has_asset(mesh_key):
			Vegetation.add_far_trees(root, mesh_key, groups[mesh_key])
			continue
		var kind := mesh_key.get_slice("_", 0)
		_multimesh(root, Props.mesh(kind, int(mesh_key.get_slice("_", 1))), groups[mesh_key], _plant_material(kind), mesh_key, false)

func _plant_material(kind: String) -> Material:
	return Props.rock_material(Color("8d939c"), 0.75) if kind == "rock" else Props.foliage_material()

func _far_block_of(key: Vector2i) -> Dictionary:
	return far_blocks.get(Vector2i(floori(key.x / float(FAR_BLOCK)), floori(key.y / float(FAR_BLOCK))), {})

## Flags the far block holding tile `key` for a rebuild: its terrain (and the neighbor
## blocks', whose skirts may face the tile) and / or its forest.
func _mark_far(key: Vector2i, terrain: bool, forest: bool) -> void:
	var block := _far_block_of(key)
	if block.is_empty(): return
	if forest: block.forest_dirty = true
	if not terrain: return
	block.terrain_dirty = true
	for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var other := _far_block_of(key + offset)
		if not other.is_empty(): other.terrain_dirty = true

## Rebuilds the far blocks flagged since the last frame: every terrain (an index rebuild),
## and one forest per frame unless `all`.
func _update_far(all := false) -> void:
	var forests := 1
	for block: Dictionary in far_blocks.values():
		if block.terrain_dirty: _rebuild_far_terrain(block)
		if block.forest_dirty and (all or forests > 0):
			_rebuild_far_forest(block)
			forests -= 1

## Depth below `level` and river-ribbon fade on the grid lo + (i, j) * step, worked out on
## the worker pool from the gameplay heights: the lake and sea surfaces' vertex data.
## `lake` keeps only the points under the lake; otherwise ground far inland is skipped.
func _water_grid(lo: Vector2i, step: int, count: Vector2i, level: float, lake: bool) -> Array:
	var rows: Array[Dictionary] = []
	for j in count.y: rows.append({})
	_parallel(count.y, func(j: int) -> void:
		var row_depths := PackedFloat32Array()
		var row_fades := PackedFloat32Array()
		var z := lo.y + j * step
		for i in count.x:
			var x := lo.x + i * step
			var inside := x >= 0 and z >= 0 and x <= extent and z <= extent
			var depth := -10.0
			var hit := _river_hit(x, z, _bucket_at(river_buckets, x, z))
			if lake:
				if inside and _water_from(x, z, hit) == LAKE: depth = level - _carve_river(_landform_height(x, z), hit)
			elif _coast_distance(Vector2(x, z)) > -45.0:
				depth = level - _carve_river(_landform_height(x, z), hit)
			row_depths.append(depth)
			row_fades.append(_ribbon_fade(x, z) if inside else 0.0)
		rows[j].depths = row_depths
		rows[j].fades = row_fades)
	var depths := PackedFloat32Array()
	var fades := PackedFloat32Array()
	for row in rows:
		depths.append_array(row.depths)
		fades.append_array(row.fades)
	return [depths, fades]

## The lake surface over its basin. COLOR.r carries depth / 8 for the water shader, so the
## shallows stay clear and the middle turns opaque blue; COLOR.g hands the surface over to a
## river ribbon fading in over it (see _ribbon_fade).
func _build_lake() -> void:
	lake_material = ShaderMaterial.new()
	lake_material.shader = LAKE_SHADER
	var step := 2
	var lo := Vector2i.ZERO
	var size := Vector2i(SIZE / step + 1, SIZE / step + 1)
	var depths := PackedFloat32Array()
	var fades := PackedFloat32Array()
	if streamed:
		# Only the basin: the shore lies inside 1.45 lake radii, wobble included.
		var reach := LAKE_RADIUS * 1.75
		lo = Vector2i(maxi(0, floori((LAKE_CENTER.x - reach.x) / step)), maxi(0, floori((LAKE_CENTER.y - reach.y) / step))) * step
		var hi := Vector2i(mini(extent / step, ceili((LAKE_CENTER.x + reach.x) / step)), mini(extent / step, ceili((LAKE_CENTER.y + reach.y) / step))) * step
		size = (hi - lo) / step + Vector2i.ONE
		var grid := _water_grid(lo, step, size, LAKE, true)
		depths = grid[0]
		fades = grid[1]
	else:
		for j in size.y:
			for i in size.x:
				var x := i * step
				var z := j * step
				var depth := LAKE - _cached(x, z)
				if water_cache[z * (SIZE + 1) + x] != LAKE: depth = -10.0
				depths.append(depth)
				fades.append(_ribbon_fade(x, z))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for j in size.y:
		for i in size.x:
			var k := j * size.x + i
			vertices.append(Vector3(lo.x + i * step, LAKE, lo.y + j * step))
			normals.append(Vector3.UP)
			colors.append(Color(clampf(depths[k] / 8.0, 0.0, 1.0), fades[k], 0))
	var indices := PackedInt32Array()
	for j in size.y - 1:
		for i in size.x - 1:
			var k := j * size.x + i
			if maxf(maxf(depths[k], depths[k + 1]), maxf(depths[k + size.x], depths[k + size.x + 1])) < -1.5: continue
			indices.append_array([k, k + 1, k + size.x, k + 1, k + size.x + 1, k + size.x])
	var water := MeshInstance3D.new()
	water.name = "Lake"
	water.mesh = _array_mesh(vertices, normals, colors, indices, lake_material)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

## 碧の海: a 2 m grid along the coast of the designed square plus a coarse 8 m sheet over
## everything else out to the horizon, both at SEA with baked depth for the shader.
func _build_sea() -> void:
	sea_material = ShaderMaterial.new()
	sea_material.shader = LAKE_SHADER
	sea_material.set_shader_parameter("shallow", Color(0.52, 0.88, 0.80))
	sea_material.set_shader_parameter("mid", Color(0.22, 0.66, 0.76))
	sea_material.set_shader_parameter("deep", Color(0.08, 0.42, 0.70))
	sea_material.set_shader_parameter("abyss", Color(0.04, 0.26, 0.56))
	sea_material.set_shader_parameter("band_depths", Vector3(0.8, 2.6, 7.0))
	sea_material.set_shader_parameter("wave_size", 2.2)
	sea_material.set_shader_parameter("surf", 1.0)
	var inner := mini(extent, SIZE)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for grid: Array in [[0, 2, inner / 2 + 1], [-480, 8, (extent + 960) / 8 + 1]]:
		var lo: int = grid[0]
		var step: int = grid[1]
		var count: int = grid[2]
		var base := vertices.size()
		var data := _water_grid(Vector2i(lo, lo), step, Vector2i(count, count), SEA, false)
		var depths: PackedFloat32Array = data[0]
		var fades: PackedFloat32Array = data[1]
		for j in count:
			for i in count:
				var k := j * count + i
				vertices.append(Vector3(lo + i * step, SEA, lo + j * step))
				normals.append(Vector3.UP)
				colors.append(Color(clampf(depths[k] / 8.0, 0.0, 1.0), fades[k], 0))
		for j in count - 1:
			for i in count - 1:
				# The coarse sheet only covers what lies outside the fine grid.
				if step > 2 and lo + i * step >= 0 and lo + (i + 1) * step <= inner and lo + j * step >= 0 and lo + (j + 1) * step <= inner: continue
				var k := j * count + i
				if maxf(maxf(depths[k], depths[k + 1]), maxf(depths[k + count], depths[k + count + 1])) < -0.6: continue
				indices.append_array([base + k, base + k + 1, base + k + count, base + k + 1, base + k + count + 1, base + k + count])
	var water := MeshInstance3D.new()
	water.name = "Sea"
	water.mesh = _array_mesh(vertices, normals, colors, indices, sea_material)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

## How far a river ribbon has faded in over this point (0 off the ribbon). Where a river
## meets the lake or the sea both surfaces lie at the same level, so the still water fades
## out by as much as the ribbon fades in instead of doubling up.
func _ribbon_fade(x: float, z: float) -> float:
	var hit := _river_hit(roundi(x), roundi(z), _bucket_at(river_buckets, roundi(x), roundi(z)))
	if hit.x < 0.0 or hit.y > river_width[int(hit.x)] + 1.6: return 0.0
	return river_fade[int(hit.x)]

## Each river as a ribbon over its channel. Rows follow the 1 m samples; at a fall two
## extra rows (lip and foot) hang a steep sheet just in front of the cut cliff. UV.x is
## meters across, UV.y the flow distance (stretched down a fall, so its streaks race);
## COLOR = depth / 8, fall, fade, foam.
func _build_river_meshes() -> void:
	river_material = ShaderMaterial.new()
	river_material.shader = RIVER_SHADER
	var root := Node3D.new()
	root.name = "Rivers"
	add_child(root)
	var across := 10
	for river in rivers:
		var points: Array = river.points
		var widths: PackedFloat32Array = river.widths
		var levels: PackedFloat32Array = river.levels
		var foams: PackedFloat32Array = river.foams
		var fades: PackedFloat32Array = river.fades
		# Rows: position along the samples, level, fall, foam, fade.
		var rows: Array = []
		for i in points.size():
			# The carving cuts each fall's cliff halfway between two samples, jagged at the 1 m
			# grid; the water shoots out over it to a lip on the next sample and drops from
			# there, so the sheet always hangs in front of the rock.
			var after_fall := i > 0 and levels[i] < levels[i - 1] - 0.01
			rows.append([i + (0.35 if after_fall else 0.0), levels[i], 1.0 if after_fall else 0.0, foams[i], fades[i]])
			if i + 1 < points.size() and levels[i + 1] < levels[i] - 0.01:
				rows.append([i + 1.0, levels[i], 1.0, 0.3, fades[i]])
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var flow := 0.0
		var previous := Vector3.ZERO
		for r in rows.size():
			var row: Array = rows[r]
			var at: float = row[0]
			var i := mini(floori(at), points.size() - 2)
			var center: Vector2 = (points[i] as Vector2).lerp(points[i + 1], at - i)
			var side := _river_side(points, i).lerp(_river_side(points, i + 1), at - i).normalized()
			var half := lerpf(widths[i], widths[i + 1], at - i) + 1.6
			var level: float = row[1]
			var mid := Vector3(center.x, level, center.y)
			if r > 0:
				# Down a fall the flow coordinate advances slower than the sheet is long, so
				# the same scroll rate reads as water racing down it.
				flow += Vector2(mid.x - previous.x, mid.z - previous.z).length() + absf(level - previous.y) * 0.35
			previous = mid
			for k in across + 1:
				var offset := (float(k) / across * 2.0 - 1.0) * half
				var p := center + side * offset
				vertices.append(Vector3(p.x, level, p.y))
				var depth := level - _expanded_height(p.x, p.y)
				colors.append(Color(clampf(depth / 8.0, 0.0, 1.0), row[2], row[4], row[3]))
				uvs.append(Vector2(offset, flow))
		var width := across + 1
		var normals := PackedVector3Array()
		for r in rows.size():
			for k in width:
				var along := vertices[mini(r + 1, rows.size() - 1) * width + k] - vertices[maxi(r - 1, 0) * width + k]
				var side := vertices[r * width + mini(k + 1, across)] - vertices[r * width + maxi(k - 1, 0)]
				normals.append(side.cross(along).normalized())
		var indices := PackedInt32Array()
		for r in rows.size() - 1:
			if colors[r * width].b <= 0.0 and colors[(r + 1) * width].b <= 0.0: continue
			for k in across:
				var a := r * width + k
				indices.append_array([a, a + width, a + 1, a + 1, a + width, a + width + 1])
		var mesh := MeshInstance3D.new()
		mesh.name = "River_%s" % river.name
		mesh.mesh = _array_mesh(vertices, normals, colors, indices, river_material, uvs)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)

func _array_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, material: Material, uvs := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
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
	var reach := (half + Vector2(0.2, 0.2)).rotated(-yaw_angle).abs()
	_block(at, reach)

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
	for k in range(0, ramp_rows.size(), 6):
		var a := Vector2(ramp_rows[k], ramp_rows[k + 1])
		var ab := Vector2(ramp_rows[k + 2], ramp_rows[k + 3]) - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < ramp_rows[k + 4] + 5.0 + margin: return true
	return false

# --- Streaming tiles ----------------------------------------------------------
# Each CHUNK tile caches APRON extra grid points on every side, so every lookup its own
# generation makes (bilinear heights, ±0.5 m slopes, ±1 m normals, 2 m biome cells) is
# served from its own window. Every value depends only on its position and the world
# seed: neighbors' overlapping windows agree exactly, so tile edges meet without seams,
# and a tile comes back the same whenever and in whatever order it is generated. The
# *_task functions run on worker threads and read only the fixed layout (landforms,
# rivers, roads, landmark obstacles) and the tiles handed to them; the main thread turns
# their results into nodes (_detail_steps, _grass_steps).

const APRON := 2
const SPAN := CHUNK + 2 * APRON + 1
const BIOME_SPAN := CHUNK / 2 + 3
## Far terrain grid (m) and tiles per far block side.
const FAR_STEP := 8
const FAR_BLOCK := 4
## Skirts hang this far below the tile / far block edges, closing any crack between them.
const TILE_SKIRT := 3.0
const FAR_SKIRT := 8.0
## Grass sub-cells per tile (about Meadow.CELL wide).
const GRASS_CELLS := [0, 11, 22, CHUNK]
## Bush spots: eleven per tile side (about the 3 m of the whole-field layout), their chance
## scaled to keep the same density.
const BUSH_SPACING := CHUNK / 11.0
## Floats per river / road segment row.
const RIVER_ROW := 10
const PATH_ROW := 9

## The tile at (x, z) with its dense data (loaded on the spot if the streamer has not).
func _data_tile(x: float, z: float) -> Chunks.Tile:
	return chunks.ensure_data(chunks.key_at(x, z))

func _t_index(t: Chunks.Tile, ix: int, iz: int) -> int:
	return (iz - t.z0 + APRON) * SPAN + ix - t.x0 + APRON

func _t_bilinear(t: Chunks.Tile, grid: PackedFloat32Array, x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var i := _t_index(t, ix, iz)
	var fx := x - ix
	var top := lerpf(grid[i], grid[i + 1], fx)
	return lerpf(top, lerpf(grid[i + SPAN], grid[i + SPAN + 1], fx), z - iz)

func _t_height(t: Chunks.Tile, x: float, z: float) -> float:
	return _t_bilinear(t, t.vh, x, z)

func _t_gameplay(t: Chunks.Tile, x: float, z: float) -> float:
	return _t_bilinear(t, t.gh, x, z)

func _t_slope(t: Chunks.Tile, x: float, z: float) -> float:
	return Vector2(_t_height(t, x + 0.5, z) - _t_height(t, x - 0.5, z), _t_height(t, x, z + 0.5) - _t_height(t, x, z - 0.5)).length()

func _t_gameplay_slope(t: Chunks.Tile, x: float, z: float) -> float:
	return Vector2(_t_gameplay(t, x + 0.5, z) - _t_gameplay(t, x - 0.5, z), _t_gameplay(t, x, z + 0.5) - _t_gameplay(t, x, z - 0.5)).length()

func _t_normal(t: Chunks.Tile, x: float, z: float) -> Vector3:
	return Vector3(_t_height(t, x - 0.5, z) - _t_height(t, x + 0.5, z), 1.0, _t_height(t, x, z - 0.5) - _t_height(t, x, z + 0.5)).normalized()

func _t_water_level(t: Chunks.Tile, x: float, z: float) -> float:
	if x < 0.0 or z < 0.0 or x > extent or z > extent: return SEA
	return t.water[_t_index(t, clampi(roundi(x), 0, extent), clampi(roundi(z), 0, extent))]

func _t_water_depth(t: Chunks.Tile, x: float, z: float) -> float:
	return _t_water_level(t, x, z) - _t_height(t, x, z)

func _t_path(t: Chunks.Tile, x: float, z: float) -> float:
	return t.path[_t_index(t, clampi(roundi(x), 0, extent), clampi(roundi(z), 0, extent))]

## Visual-only micro relief (about ±0.05–0.18 m), scaled by the biome's ground roughness
## and calmed on roads, plazas and fields. It never reaches the gameplay height.
func _t_micro(t: Chunks.Tile, x: int, z: int) -> float:
	if x < 0 or z < 0 or x > extent or z > extent: return 0.0
	var p := Vector2(x, z)
	var calm := (1.0 - _plaza_weight(p)) * smoothstep(-0.5, 2.0, _t_path(t, x, z)) * (1.0 - _field_weight(p) * 0.8)
	if calm <= 0.0: return 0.0
	var amplitude := (t.biome as Biomes.Patch).param_smooth(Biomes.Param.GROUND_ROUGHNESS, x, z) * MICRO_RELIEF * calm
	return (noise.get_noise_2d(x * 7.0 + 1300.0, z * 7.0 - 800.0) * 1.5 + noise.get_noise_2d(x * 19.0, z * 19.0 + 77.0) * 0.5) * amplitude

## Worker task: the tile's windows — gameplay heights (landforms carved by the rivers),
## water levels and road distances, then the biome patch (which reads the gameplay
## heights), then the visual heights — and with `plan` its trees and rocks.
func _tile_data_task(t: Chunks.Tile, plan: bool, result: Dictionary) -> void:
	var gh := PackedFloat32Array()
	var water := PackedFloat32Array()
	var path := PackedFloat32Array()
	gh.resize(SPAN * SPAN)
	water.resize(SPAN * SPAN)
	path.resize(SPAN * SPAN)
	var rivers_here: PackedInt32Array = river_buckets.get(t.key, PackedInt32Array())
	var roads_here: PackedInt32Array = path_buckets.get(t.key, PackedInt32Array())
	for j in SPAN:
		var z := t.z0 - APRON + j
		for i in SPAN:
			var x := t.x0 - APRON + i
			var k := j * SPAN + i
			var hit := _river_hit(x, z, rivers_here)
			gh[k] = _carve_river(_landform_height(x, z), hit)
			water[k] = _water_from(x, z, hit) if x >= 0 and z >= 0 and x <= extent and z <= extent else SEA
			path[k] = _path_query(x, z, roads_here)
	t.gh = gh
	t.water = water
	t.path = path
	t.biome = biome.bake_patch(t.x0 / 2 - 1, t.z0 / 2 - 1, BIOME_SPAN, func(x: float, z: float) -> PackedFloat32Array:
		return _biome_signals(x, z, gh[(roundi(z) - t.z0 + APRON) * SPAN + roundi(x) - t.x0 + APRON]))
	var vh := gh.duplicate()
	for j in SPAN:
		for i in SPAN: vh[j * SPAN + i] += _t_micro(t, t.x0 - APRON + i, t.z0 - APRON + j)
	t.vh = vh
	result.texels = biome.patch_images(t.biome)
	result.data = true
	if plan:
		_plan_trees(t)
		result.planned = true

## Worker task: trees and rocks for a tile whose data came before the landmarks did.
func _tile_plan_task(t: Chunks.Tile, result: Dictionary) -> void:
	_plan_trees(t)
	result.planned = true

## Trees and boulders from the biome table: density, broadleaf/conifer mix and size come
## from the blended BiomeData; density rhythm clumps them into groves and glades, and the
## designed sightlines stay open. Trees are the Blender-built Phase 2 set with
## hierarchical LOD (Vegetation.add_tree_chunk): broadleaf A/B/C in the woods, oaks
## favoured on open land, conifer A/B. Blossom trees and boulders are still procedural.
## Spots lie on a 4 m lattice; every tile draws from its own seeded generator.
func _plan_trees(t: Chunks.Tile) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed + 5, t.key.x, t.key.y])
	var spacing := 4.0
	var b: Biomes.Patch = t.biome
	var grid := b.params
	var trees: Array = []
	var rects: Array[Rect2] = []
	var cover := {}
	var landmarks: Array = obstacle_chunks.get(t.key, [])
	var x_end := float(mini(t.x0 + CHUNK, extent))
	var z := float(t.z0)
	while z < mini(t.z0 + CHUNK, extent):
		var x := float(t.x0)
		while x < x_end:
			# Every random number is drawn up front so a skipped spot never shifts the rest.
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.75, 1.25)
			var angle := rng.randf() * TAU
			var stretch := rng.randf()
			x += spacing
			var h := _t_height(t, p.x, p.y)
			if _t_water_depth(t, p.x, p.y) > -1.0 or _t_path(t, p.x, p.y) < 3.0: continue
			if _clear(p, landmarks) or _near_ramp(p, 0.0): continue
			var c := b.cell(p.x, p.y)
			if h < grid[c + Biomes.Param.MIN_HEIGHT] or h > grid[c + Biomes.Param.MAX_HEIGHT]: continue
			var slope := _t_gameplay_slope(t, p.x, p.y)
			var open := 1.0 - _sightline_mask(p)
			var tree_chance := grid[c + Biomes.Param.TREE_DENSITY] * _density_rhythm(p)
			# Small broadleaf groves dot the plains.
			var grove := smoothstep(0.28, 0.42, noise.get_noise_2d(p.x * 1.5 + 911.0, p.y * 1.5 - 45.0))
			tree_chance += b.weight(Biomes.Biome.PLAINS, p.x, p.y) * grove * 0.4
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
					kind = _tree_asset(kind, fmod(pick * 389.0, 1.0))
					size = variation
				else:
					# Blossom trees are rare accents in the open meadows and on the shore (not among
					# the seed trees, where their spots take a seed broadleaf like their neighbors).
					var meadow := b.weight(Biomes.Biome.PLAINS, p.x, p.y) + b.weight(Biomes.Biome.LAKESHORE, p.x, p.y)
					var open_land := meadow + b.weight(Biomes.Biome.FARMLAND, p.x, p.y) + b.weight(Biomes.Biome.HIGHLAND, p.x, p.y)
					if not seed_trees and fmod(pick * 97.0, 1.0) < 0.06 * meadow:
						kind = _tree_asset("blossom") if toon_trees or card_trees else "broadleaf"
						variant = 2
						trunk = 0.5
						if toon_trees or card_trees: size = variation
					else:
						# Oaks stand on open land; the woods are broadleaf A / B / C.
						var oak := fmod(pick * 53.0, 1.0) < 0.1 + 0.45 * clampf(open_land, 0.0, 1.0)
						kind = ("oak_b" if shape < 0.3 else "oak_a") if oak else ["broadleaf_a", "broadleaf_b", "broadleaf_c"][int(shape * 3.0)]
						trunk = 0.65 if oak else 0.45
						kind = _tree_asset(kind, fmod(pick * 389.0, 1.0))
						size = variation
				# Padded by 0.3 m like every indexed obstacle (_index_obstacles).
				rects.append(Rect2(p - Vector2(trunk, trunk) * size, Vector2(trunk, trunk) * 2.0 * size).grow(0.3))
				cover[world_position_to_cell(Vector3(p.x, 0, p.y))] = "TREE"
			elif roll < tree_chance + rock_chance:
				kind = "rock"
				variant = int(pick * 40.0) % 4
				size *= 1.1 if pick < 0.7 else 2.2
				rects.append(Rect2(p - Vector2(0.7, 0.7) * size, Vector2(1.4, 1.4) * size).grow(0.3))
			else:
				continue
			var mesh_key := kind if Vegetation.has_asset(kind) else "%s_%d" % [kind, variant]
			var tall := lerpf(0.6, 0.9, stretch) if kind == "rock" else lerpf(0.95, 1.05, stretch) if Vegetation.has_asset(kind) else lerpf(0.9, 1.15, stretch)
			var basis := Basis(Vector3.UP, angle).scaled(Vector3(size, size * tall, size))
			trees.append([mesh_key, Transform3D(basis, Vector3(p.x, h - (0.35 * size if kind == "rock" else 0.1), p.y))])
		z += spacing
	t.trees = trees
	t.rects = rects
	t.cover = cover

## The tree asset drawn for a Phase 2 tree kind under the seed / toon / card / solid styles.
## `roll` (0-1) picks one of the seed trees at random.
func _tree_asset(kind: String, roll := 0.0) -> String:
	if seed_trees and kind in Vegetation.SEED_REPLACES:
		return Vegetation.SEED_TREES[mini(int(roll * Vegetation.SEED_TREES.size()), Vegetation.SEED_TREES.size() - 1)]
	if seed_trees and kind in Vegetation.SEED_CONIFER_REPLACES:
		return Vegetation.SEED_CONIFERS[mini(int(roll * Vegetation.SEED_CONIFERS.size()), Vegetation.SEED_CONIFERS.size() - 1)]
	if toon_trees: return Vegetation.TOON_SWAP[kind]
	if card_trees: return Vegetation.CARD_SWAP[kind]
	return kind

## Bushes along forest edges, in the understory and on road verges (Blender-built
## bush A / B / C), clear of the trunks in `rects` (this tile's and its neighbors').
## Walkable light cover: no obstacle, recorded as "LIGHT" cover.
func _tile_bush_task(t: Chunks.Tile, rects: Array[Rect2], result: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed + 7, t.key.x, t.key.y])
	var b: Biomes.Patch = t.biome
	var grid := b.params
	var spacing := BUSH_SPACING
	var density := pow(spacing / 3.0, 2.0)
	var bushes: Array = []
	var cover := {}
	var near: Array = obstacle_chunks.get(t.key, []).duplicate()
	near.append_array(rects)
	var x_end := float(mini(t.x0 + CHUNK, extent))
	var z_end := float(mini(t.z0 + CHUNK, extent))
	for row in 11:
		var z := t.z0 + row * spacing
		if z >= z_end: break
		for column in 11:
			var x := t.x0 + column * spacing
			if x >= x_end: break
			var p := Vector2(x + rng.randf() * spacing, z + rng.randf() * spacing)
			var roll := rng.randf()
			var pick := rng.randf()
			var size := rng.randf_range(0.85, 1.15)
			var angle := rng.randf() * TAU
			var h := _t_height(t, p.x, p.y)
			var road := _t_path(t, p.x, p.y)
			if _t_water_depth(t, p.x, p.y) > -0.8 or road < 2.0 or _clear(p, near) or _near_ramp(p, 0.0): continue
			var c := b.cell(p.x, p.y)
			if h > grid[c + Biomes.Param.MAX_HEIGHT] or _t_slope(t, p.x, p.y) > 0.6: continue
			if _plaza_weight(p) > 0.3 or _field_weight(p) > 0.3: continue
			# Densest where the woods thin out (forest edge), some understory inside, a few
			# on the road verges; sightlines thin them but low shrubs rarely block a view.
			var trees := grid[c + Biomes.Param.TREE_DENSITY] * _density_rhythm(p)
			var edge := smoothstep(0.04, 0.22, trees) * (1.0 - smoothstep(0.7, 1.1, trees))
			var verge := (1.0 - smoothstep(4.0, 7.0, road)) * (1.0 - b.weight(Biomes.Biome.SETTLEMENT, p.x, p.y))
			var chance := (0.4 * edge + 0.12 * smoothstep(0.5, 1.0, trees) + 0.1 * verge) * lerpf(0.5, 1.0, 1.0 - _sightline_mask(p)) * density
			if roll >= chance: continue
			var deep := b.weight(Biomes.Biome.DEEP_FOREST, p.x, p.y) + b.weight(Biomes.Biome.FOREST, p.x, p.y) * 0.5
			var asset := "bush_c" if pick < 0.2 + 0.4 * deep else ("bush_b" if pick < 0.55 + 0.3 * verge else "bush_a")
			bushes.append([asset, Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * size), Vector3(p.x, h - 0.05, p.y))])
			var cell := world_position_to_cell(Vector3(p.x, 0, p.y))
			if not t.cover.has(cell): cover[cell] = "LIGHT"
	result.bushes = bushes
	result.bush_cover = cover

## Worker task: the tile's 1 m terrain mesh arrays, for _terrain_steps.
func _tile_terrain_task(t: Chunks.Tile, result: Dictionary) -> void:
	result.terrain = _terrain_arrays(t)

## Worker task: the tile's bushes (if not placed yet) and its trees and bushes grouped per
## asset, ready for the main thread's _detail_steps.
func _tile_detail_task(t: Chunks.Tile, rects: Array[Rect2], result: Dictionary) -> void:
	var bushes: Array = t.bushes
	if not t.bushes_planned:
		_tile_bush_task(t, rects, result)
		bushes = result.bushes
	var trees := {}
	for entry: Array in t.trees: (trees.get_or_add(entry[0], []) as Array).append(entry[1])
	result.trees = trees
	var groups := {}
	for entry: Array in bushes: (groups.get_or_add(entry[0], []) as Array).append(entry[1])
	result.bush_groups = groups

## The tile's 1 m terrain mesh, vertex for vertex as the whole-field build made it, plus a
## skirt: the edge loop copied TILE_SKIRT lower and closed with two-sided strips.
func _terrain_arrays(t: Chunks.Tile) -> Array:
	var b: Biomes.Patch = t.biome
	var x1 := mini(t.x0 + CHUNK, extent)
	var z1 := mini(t.z0 + CHUNK, extent)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for z in range(t.z0, z1 + 1):
		for x in range(t.x0, x1 + 1):
			var k := _t_index(t, x, z)
			var h := t.vh[k]
			vertices.append(Vector3(x, h, z))
			var normal := Vector3(t.vh[k - 1] - t.vh[k + 1], 2.0, t.vh[k - SPAN] - t.vh[k + SPAN])
			normals.append(normal.normalized())
			# Height above the local water (sea, lake or river): sand and pebbles along
			# every shore and riverbed, but bare rock on falls and sea cliffs.
			var above := h - t.water[k]
			var road := 1.0 - smoothstep(-0.4, 1.0, t.path[k] + noise.get_noise_2d(x * 5.0, z * 5.0) * 0.8)
			var shore := b.weight(Biomes.Biome.LAKESHORE, x, z) * (1.0 - smoothstep(1.2, 3.0, above)) * 0.85
			var steep := smoothstep(1.4, 2.4, Vector2(normal.x, normal.z).length())
			var sand := maxf(1.0 - smoothstep(0.4, 1.6, above), shore) * (1.0 - road) * (1.0 - steep)
			colors.append(Color(road, sand, _plaza_weight(Vector2(x, z)), _field_weight(Vector2(x, z)) * (1.0 - road)))
			uvs.append(Vector2(-above, 0.0))
	var width := x1 - t.x0 + 1
	var depth := z1 - t.z0 + 1
	var indices := PackedInt32Array()
	for z in depth - 1:
		for x in width - 1:
			var i := z * width + x
			indices.append_array([i, i + 1, i + width, i + 1, i + width + 1, i + width])
	var ring: Array[int] = []
	for x in width: ring.append(x)
	for z in range(1, depth): ring.append(z * width + width - 1)
	for x in range(width - 2, -1, -1): ring.append((depth - 1) * width + x)
	for z in range(depth - 2, 0, -1): ring.append(z * width)
	var base := vertices.size()
	for v in ring:
		vertices.append(vertices[v] - Vector3(0, TILE_SKIRT, 0))
		normals.append(normals[v])
		colors.append(colors[v])
		uvs.append(uvs[v])
	for s in ring.size():
		var a := ring[s]
		var c := ring[(s + 1) % ring.size()]
		var la := base + s
		var lc := base + (s + 1) % ring.size()
		indices.append_array([a, c, la, c, lc, la, a, la, c, c, la, lc])
	return [vertices, normals, colors, uvs, indices]

## Main-thread step for a finished terrain task: the mesh goes in and the far block
## leaves the tile out.
func _terrain_steps(t: Chunks.Tile, result: Dictionary) -> Array[Callable]:
	return [_attach_terrain.bind(t, result)]

func _attach_terrain(t: Chunks.Tile, result: Dictionary) -> void:
	var arrays: Array = result.terrain
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain_%d_%d" % [t.key.x, t.key.y]
	terrain.mesh = _array_mesh(arrays[0], arrays[1], arrays[2], arrays[4], terrain_material, arrays[3])
	terrain_root.add_child(terrain)
	t.terrain = terrain
	far_excluded[t.key] = true
	_mark_far(t.key, true, false)

## Main-thread steps for a finished detail task, one per frame budget slot: the trees and
## rocks (then the far forest leaves the tile out), then the bushes.
func _detail_steps(t: Chunks.Tile, result: Dictionary) -> Array[Callable]:
	return [_attach_trees.bind(t, result), _attach_bushes.bind(t, result)]

func _attach_trees(t: Chunks.Tile, result: Dictionary) -> void:
	t.detail = Node3D.new()
	t.detail.name = "Tile_%d_%d" % [t.key.x, t.key.y]
	field_root.add_child(t.detail)
	var forest := Node3D.new()
	forest.name = "Forest"
	t.detail.add_child(forest)
	var groups: Dictionary = result.trees
	for mesh_key: String in groups:
		if Vegetation.has_asset(mesh_key):
			Vegetation.add_tree_chunk(forest, mesh_key, groups[mesh_key])
			continue
		var kind := mesh_key.get_slice("_", 0)
		_multimesh(forest, Props.mesh(kind, int(mesh_key.get_slice("_", 1))), groups[mesh_key], _plant_material(kind), mesh_key)
	forest_excluded[t.key] = true
	_mark_far(t.key, false, true)

func _attach_bushes(t: Chunks.Tile, result: Dictionary) -> void:
	var bushes := Node3D.new()
	bushes.name = "Bushes"
	t.detail.add_child(bushes)
	var groups: Dictionary = result.bush_groups
	for asset: String in groups:
		Vegetation.add_bush_chunk(bushes, asset, groups[asset])

## Worker task: the Ghibli grass carpet and wildflowers of a tile, per GRASS_CELLS
## sub-cell (each with its own seeded generator). Every 1 m cell of open ground takes one
## procedural blade patch (open_field_meadow.gd) sheared onto the slope and lit with the
## terrain normal, so the carpet closes over the ground and shades with the hills. Blade
## height follows the ground: short on verges, slopes, lawns and thin ground, knee-high
## where it is wet or wild. Blender-built flower clusters gather in drifts of one kind
## (star flowers A, cool spikes B where it is wetter), standing a little above the grass.
func _tile_grass_task(t: Chunks.Tile, result: Dictionary) -> void:
	var b: Biomes.Patch = t.biome
	var grid := b.params
	var cells: Array = []
	for sz in GRASS_CELLS.size() - 1:
		for sx in GRASS_CELLS.size() - 1:
			var cx0: int = t.x0 + GRASS_CELLS[sx]
			var cz0: int = t.z0 + GRASS_CELLS[sz]
			var cx1 := mini(t.x0 + GRASS_CELLS[sx + 1], extent)
			var cz1 := mini(t.z0 + GRASS_CELLS[sz + 1], extent)
			if cx0 >= cx1 or cz0 >= cz1: continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([world_seed + 91, cx0, cz0])
			var carpet: Array = []
			var carpet_normals: Array = []
			var groups := {}
			var normals := {}
			for z in range(cz0, cz1):
				for x in range(cx0, cx1):
					var c := b.cell(x + 0.5, z + 0.5)
					var density := grid[c + Biomes.Param.GRASS_DENSITY]
					var wet := grid[c + Biomes.Param.WETNESS]
					var top := grid[c + Biomes.Param.MAX_HEIGHT]
					var px := x + 0.5 + rng.randf_range(-0.3, 0.3)
					var pz := z + 0.5 + rng.randf_range(-0.3, 0.3)
					var yaw_angle := rng.randf() * TAU
					var jitter := rng.randf_range(0.85, 1.15)
					var roll := rng.randf()
					# Thin biomes (forest floor, mountain) break into tufts; open land closes up.
					if roll > density * 1.5: continue
					var h := _t_height(t, px, pz)
					if h > top or _t_water_depth(t, px, pz) > -0.4: continue
					var road := _t_path(t, px, pz)
					if road < -0.1: continue
					var slope := _t_slope(t, px, pz)
					if slope > 0.7 or _plaza_weight(Vector2(px, pz)) > 0.3 or _field_weight(Vector2(px, pz)) > 0.3: continue
					# Height: lawns and verges short, the open meadow mid, wet or wild drifts tall.
					var lawn := smoothstep(0.15, 0.45, noise.get_noise_2d(px * 1.9 + 520.0, pz * 1.9 + 210.0))
					var wild := smoothstep(0.0, 0.35, noise.get_noise_2d(px * 1.7 - 150.0, pz * 1.7 + 60.0) + 0.6 * grid[c + Biomes.Param.ROCKINESS] + 0.5 * wet)
					var tall := lerpf(0.42, 0.72, wild)
					tall = lerpf(tall, 0.24, maxf(lawn, 1.0 - smoothstep(0.2, 0.45, density)))
					tall *= lerpf(0.45, 1.0, smoothstep(0.0, 2.5, road)) * lerpf(1.0, 0.6, smoothstep(0.35, 0.7, slope))
					var n := _t_normal(t, px, pz)
					carpet.append(Meadow.patch_transform(Vector3(px, h - 0.04, pz), n, tall * jitter, yaw_angle))
					carpet_normals.append(n)
					# Wildflower drifts on top of the carpet.
					var drift := lerpf(0.15, 3.0, smoothstep(0.05, 0.4, noise.get_noise_2d(px * 2.2 + 70.0, pz * 2.2 - 31.0)))
					var flower_p := 0.1 * grid[c + Biomes.Param.FLOWER_DENSITY] * drift
					if rng.randf() >= flower_p or road < 1.0: continue
					var flower_b := noise.get_noise_2d(px * 1.3 + 300.0, pz * 1.3 - 80.0) > 0.12 - 0.5 * wet
					var asset := "flower_grass_b" if flower_b else "flower_grass_a"
					var fx := x + rng.randf()
					var fz := z + rng.randf()
					if not groups.has(asset):
						groups[asset] = []
						normals[asset] = []
					groups[asset].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.25, 1.6)), Vector3(fx, _t_height(t, fx, fz) - 0.03, fz)))
					normals[asset].append(_t_normal(t, fx, fz))
			cells.append(["Meadow_%d_%d" % [cx0, cz0], carpet, carpet_normals, groups, normals])
	result.cells = cells
	result.signature = hash(cells)

## Main-thread steps for a finished grass task: one per sub-cell.
func _grass_steps(t: Chunks.Tile, result: Dictionary) -> Array[Callable]:
	var list: Array[Callable] = []
	for cell: Array in result.cells: list.append(_attach_grass_cell.bind(t, cell))
	chunks.record_grass(t, result.signature)
	return list

func _attach_grass_cell(t: Chunks.Tile, cell: Array) -> void:
	if t.grass == null:
		t.grass = Node3D.new()
		t.grass.name = "Meadow_%d_%d" % [t.key.x, t.key.y]
		meadow_root.add_child(t.grass)
	var detail := Node3D.new()
	detail.name = cell[0]
	t.grass.add_child(detail)
	Meadow.add_cell(detail, cell[1], cell[2], "Grass")
	var groups: Dictionary = cell[3]
	var normals: Dictionary = cell[4]
	for asset: String in groups:
		Vegetation.add_grass_chunk(detail, asset, groups[asset], normals[asset])

## A finished data task: the tile's biome patch goes into the shader maps (once) and its
## plan into the far forest.
func _attach_data(t: Chunks.Tile, result: Dictionary) -> void:
	if result.get("data", false) and not patched.has(t.key):
		patched[t.key] = true
		biome.write_patch(t.biome, result.texels)
	if result.get("planned", false): _mark_far(t.key, false, true)

func _release_grass(t: Chunks.Tile) -> void:
	t.grass.queue_free()

## The far forest takes the tiles' trees back first (in this frame), then their detail goes.
func _release_details(list: Array[Chunks.Tile]) -> void:
	var blocks := {}
	for t in list:
		forest_excluded.erase(t.key)
		_mark_far(t.key, false, true)
		blocks[_far_block_of(t.key).get("key")] = true
	for block: Dictionary in far_blocks.values():
		if block.forest_dirty and blocks.has(block.key): _rebuild_far_forest(block)
	for t in list: t.detail.queue_free()

## The far blocks take the tiles' ground back first (in this frame), then their mesh goes.
func _release_terrains(list: Array[Chunks.Tile]) -> void:
	for t in list:
		far_excluded.erase(t.key)
		_mark_far(t.key, true, false)
	for block: Dictionary in far_blocks.values():
		if block.terrain_dirty: _rebuild_far_terrain(block)
	for t in list: t.terrain.queue_free()

## A tile dropped from the streamer: its trees leave the far forest.
func _forget_tile(t: Chunks.Tile) -> void:
	_mark_far(t.key, false, true)

## Hands the biome tint/debug maps to every open-field shader material.
func _apply_biome_maps() -> void:
	var tint: Texture2D = biome.tint_map
	var surface: Texture2D = biome.surface_map
	biome_debug_map = biome.debug_map
	for material in _field_materials():
		material.set_shader_parameter("biome_map", tint)
		material.set_shader_parameter("biome_debug_map", biome_debug_map)
		material.set_shader_parameter("biome_surface_map", surface)
		material.set_shader_parameter("biome_uv_scale", biome.uv_scale())
		material.set_shader_parameter("biome_uv_offset", biome.uv_offset())
		material.set_shader_parameter("biome_extent", float(extent))
		material.set_shader_parameter("biome_enabled", 1.0)

func _field_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = Props.shader_materials()
	materials.append_array(Vegetation.shader_materials())
	materials.append(terrain_material)
	return materials

## Place names over the landmarks: text, position, height above the ground or water.
const LABELS := [["ルミエール城", CRAG, 44.0], ["城下町", TOWN_PLAZA, 16.0], ["鏡の湖", Vector2(150, 160), 6.0], ["風車の丘", VILLAGE, 20.0], ["白霧の遺跡", RUINS, 16.0], ["見晴らしの丘", SPAWN_HILL, 9.0], ["北嶺 アルヴァ", Vector2(300, 30), 22.0], ["白瀬川", Vector2(265, 58), 10.0], ["碧瀬川", Vector2(340, 194), 8.0], ["碧の海", Vector2(430, 290), 8.0]]

func _build_labels(parent: Node3D) -> void:
	for entry: Array in LABELS:
		var label := Label3D.new()
		label.text = entry[0]
		var p: Vector2 = entry[1]
		label.position = Vector3(p.x, maxf(_height(p.x, p.y), _water_level(p.x, p.y)) + entry[2], p.y)
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
	_sync_weapon_buttons()
	_spawn_sparring_partner(spawn)
	_spawn_enemies(spawn)
	player.attack_impact.connect(_on_player_attack_impact)
	encounter_marker = Node3D.new()
	encounter_marker.visible = false
	add_child(encounter_marker)
	encounter_position = Vector3(-1000, 0, -1000)

## Character 001 stands just ahead of the explorer as a target that flinches when struck.
func _spawn_sparring_partner(spawn: Vector2) -> void:
	sparring_partner = SPARRING_SCENE.instantiate() as Node3D
	sparring_partner.name = "SparringPartner"
	add_child(sparring_partner)
	var at := spawn + Vector2(player.world_facing.x, player.world_facing.z) * SPARRING_OFFSET
	sparring_partner.position = Vector3(at.x, _surface(at.x, at.y) + 0.05, at.y)
	_face_toward(sparring_partner, player.position)
	var animation_player: AnimationPlayer = sparring_partner.animation_player
	if animation_player:
		if animation_player.has_animation("idle"):
			animation_player.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		if animation_player.has_animation("hit"):
			animation_player.get_animation("hit").loop_mode = Animation.LOOP_NONE
		animation_player.animation_finished.connect(func(clip: StringName) -> void:
			if clip == &"hit": animation_player.play("idle", 0.2))
	# In npcs it blocks the explorer's path and can be talked to like the roster.
	npcs.append({"actor": sparring_partner, "data": {
		"id": "sparring_" + sparring_partner.character_id, "name": sparring_partner.display_name,
		"lines": Array(sparring_partner.dialogue)
	}})

func _spawn_enemies(spawn: Vector2) -> void:
	var forward := Vector2(player.world_facing.x, player.world_facing.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var demo_kinds: Dictionary = {}
	for index in field_enemies.size():
		var enemy := field_enemies[index].instantiate() as Node3D
		enemy.name = "Enemy%d" % index
		var at := spawn + forward * ENEMY_OFFSET + right * ENEMY_SPACING * (index - (field_enemies.size() - 1) * 0.5)
		enemy.position = Vector3(at.x, _surface(at.x, at.y) + 0.05, at.y)
		enemy.set("ground_height", _surface)
		var kind: String = enemy.get("enemy_id")
		if enemy_demo and not demo_kinds.has(kind):
			demo_kinds[kind] = true
			enemy.set("demo", true)
			enemy.set("show_clip_label", true)
		add_child(enemy)
		_face_toward(enemy, player.position)
		enemies.append(enemy)

## Roster visuals face +Z.
func _face_toward(actor: Node3D, target: Vector3) -> void:
	var to := Vector2(target.x - actor.position.x, target.z - actor.position.z)
	if not to.is_zero_approx(): actor.rotation.y = atan2(to.x, to.y)

func _on_player_attack_impact(clip: String) -> void:
	var stops: bool = player.sword_combat.slows_on_hit(clip)
	var struck: Array[Node3D] = []
	for enemy in enemies:
		if _within_strike(enemy):
			_face_toward(enemy, player.position)
			# Freeze first, so a finishing blow's fall waits out the hit-stop too.
			if stops: enemy.hold(HIT_STOP)
			enemy.take_hit()
			struck.append(enemy)
	if sparring_partner and _within_strike(sparring_partner): struck.append(sparring_partner)
	if not struck.is_empty() and stops: _show_hits(struck, clip)
	if sparring_partner == null or not _within_strike(sparring_partner): return
	var animation_player: AnimationPlayer = sparring_partner.animation_player
	if animation_player == null or not animation_player.has_animation("hit"): return
	_face_toward(sparring_partner, player.position)
	# Restart on every blow so combos read as separate hits.
	animation_player.play("hit", 0.05)
	animation_player.seek(0.0, true)
	if stops: _hold_clip(animation_player)

## Freezes a struck character's clip for the hit-stop, unless another clip has taken over by then.
func _hold_clip(animation_player: AnimationPlayer) -> void:
	var clip := animation_player.current_animation
	animation_player.speed_scale = 0.0
	get_tree().create_timer(HIT_STOP).timeout.connect(func() -> void:
		if is_instance_valid(animation_player) and animation_player.current_animation == clip: animation_player.speed_scale = 1.0)

## A hit effect on each struck target's near side at sword height; it and the attack freeze for the hit-stop.
func _show_hits(targets: Array[Node3D], clip: String) -> void:
	var combat = player.sword_combat
	var tilt := SLASH_HIT_TILT if clip in [combat.slash_clip, combat.alt_slash_clip] else 0.0
	var height: float = player.sword_combat.grip.global_position.y if player.sword_combat.grip else player.position.y + 1.0
	for target in targets:
		var toward := player.position - target.position
		toward.y = 0.0
		var fx := HitFx.new()
		fx.name = "SwordHitFx"
		fx.hold = HIT_STOP
		fx.tilt_degrees = tilt
		add_child(fx)
		var at := target.position + toward.limit_length(HIT_FX_INSET)
		fx.global_position = Vector3(at.x, height, at.z)
	player.hold_attack(HIT_STOP)

func _within_strike(target: Node3D) -> bool:
	var to := target.position - player.position
	to.y = 0.0
	var reach := BOW_REACH if player.sword_combat.is_ranged() else MELEE_REACH
	if to.length() > reach: return false
	# A wide cone up close, a narrow one for arrows at range.
	var cone := 0.9 if reach == BOW_REACH and to.length() > MELEE_REACH else 0.2
	return to.length() <= 0.3 or to.normalized().dot(player.world_facing.normalized()) >= cone

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
	from.y += maxf(_height(from.x, from.z), _water_level(from.x, from.z))
	var direction := ((shot[1] as Vector3) - from).normalized()
	overview = true
	distance = 20.0
	focus = from + direction * distance
	yaw = atan2(-direction.x, -direction.z)
	pitch = asin(-direction.y)
	_update_camera()

## Top-down 1 px = 1 m map: biome debug colors over a hillshade, sightlines in white.
## Generates every tile of the field first (slow on a large field; a debugging aid).
func _dump_maps(directory: String) -> void:
	for kz in chunks.tiles_per_side:
		for kx in chunks.tiles_per_side: chunks.ensure_plan(Vector2i(kx, kz))
	var image := Image.create_empty(extent + 1, extent + 1, false, Image.FORMAT_RGB8)
	var debug := biome.debug_image
	var light := Vector3(-1, 2, -1).normalized()
	for z in extent + 1:
		for x in extent + 1:
			var normal := Vector3(_cached(x - 1, z) - _cached(x + 1, z), 2.0, _cached(x, z - 1) - _cached(x, z + 1)).normalized()
			var color := debug.get_pixel(mini(x >> 1, debug.get_width() - 1), mini(z >> 1, debug.get_height() - 1))
			var depth := _water_level(x, z) - _cached(x, z)
			if depth > 0.0: color = Color("1d3f66").lerp(Color("5fb8c8"), 1.0 - smoothstep(0.0, WADE_DEPTH, depth))
			color = color * lerpf(0.45, 1.15, maxf(normal.dot(light), 0.0))
			if _sightline_mask(Vector2(x, z)) > 0.5: color = color.lerp(Color.WHITE, 0.25)
			image.set_pixel(x, z, color)
	var rects: Array[Rect2] = obstacles.duplicate()
	for t: Chunks.Tile in chunks.tiles.values(): rects.append_array(t.rects)
	for rect in rects:
		var center := rect.get_center()
		if center.x >= 0 and center.y >= 0 and center.x <= extent and center.y <= extent:
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
	terrain_panel.offset_top = 780
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
	if streamed:
		var tiles := chunks.stats()
		terrain_text.text += "\nTiles: grass %d / detail %d / terrain %d\n  data %d / plan %d, queued %d" % [
			tiles.grass, tiles.detail, tiles.terrain, tiles.data, tiles.plan, chunks.pending()]

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
	var hit := _river_at(p.x, p.y)
	if not hit.is_empty() and float(hit[2]) < (hit[0].widths as PackedFloat32Array)[hit[1]] + 6.0: return hit[0].name
	if _coast_distance(p) > -30.0: return "碧の海岸"
	if p.y < 95.0: return "北嶺の麓"
	if p.distance_to(SPAWN_HILL) < 40.0: return "見晴らしの丘"
	if ((p - LAKE_CENTER) / LAKE_RADIUS).length() < 1.3: return "鏡の湖畔"
	return REGION_NAMES.get(get_biome_at(p.x, p.y), "翠風の野")

func _process(delta: float) -> void:
	super._process(delta)
	if streamed and player:
		# Around the explorer and around the camera, which may look from elsewhere (views).
		chunks.update([Vector2(player.position.x, player.position.z), Vector2(camera.position.x, camera.position.z)], delta)
		var started := Time.get_ticks_usec()
		_update_far()
		biome_flush_wait -= delta
		if biome_flush_wait <= 0.0:
			biome.flush_maps()
			biome_flush_wait = 0.25
		chunks.counters.max_far_ms = maxf(chunks.counters.max_far_ms, (Time.get_ticks_usec() - started) / 1000.0)
	for hub in spinning: hub.rotation.z += delta * 0.55
	if crystal:
		crystal.rotation.y += delta * 0.6
		crystal.position.y = 4.2 + sin(Time.get_ticks_msec() * 0.0015) * 0.25
	_sync_conditions()
	if terrain_panel.visible: _update_terrain_hud()
	if mode == "explore" and prompt_text and not prompt_text.text.begins_with("E /"):
		prompt_text.text = "目標 : 丘の上のルミエール城を目指して、開けた野を自由に旅しよう"

## The orbit camera keeps clear of the ground as in world.gd, but only reads heights it
## already has, so a far-flung overview never loads tiles for its clearance.
func _update_camera() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	if camera.position.x >= 0 and camera.position.x < extent and camera.position.z >= 0 and camera.position.z < extent:
		camera.position.y = maxf(camera.position.y, _height_estimate(camera.position.x, camera.position.z) + minf(3.0, 0.5 + distance * 0.25))
	camera.look_at(focus)

## Mirrors FieldWeather's time/weather/season onto the open-field materials.
func _sync_conditions() -> void:
	if field_weather == null: return
	var key: int = (field_weather.season_index * 4 + field_weather.time_index) * 4 + field_weather.weather_index
	if key == conditions_key: return
	conditions_key = key
	var wet := 1.0 if field_weather.weather_index == 1 else 0.0
	var snow := 0.8 if field_weather.weather_index == 3 else 0.0
	var materials: Array[ShaderMaterial] = Props.shader_materials()
	materials.append_array(Vegetation.shader_materials())
	materials.append_array([terrain_material, lake_material, sea_material, river_material])
	for material in materials:
		material.set_shader_parameter("wetness", wet)
		material.set_shader_parameter("snow_cover", snow)
		material.set_shader_parameter("season", field_weather.season_index)
	# Wind for the Phase 2 vegetation: livelier in rain and cloud, calmer in snow.
	var wind := [1.0, 1.7, 1.3, 0.6][field_weather.weather_index] as float
	for material in Vegetation.shader_materials():
		material.set_shader_parameter("wind_strength", wind)
	for material in [Vegetation.GRASS_MATERIAL, Vegetation.FLOWER_MATERIAL, Vegetation.MEADOW_MATERIAL]:
		material.set_shader_parameter("sway", 1.0 if grass_sway else 0.0)
	# Aerial perspective: distant land fades toward a cool, time-of-day haze.
	var haze := [Color(0.74, 0.79, 0.86), Color(0.60, 0.73, 0.88), Color(0.78, 0.68, 0.68), Color(0.10, 0.14, 0.24)][field_weather.time_index] as Color
	if field_weather.weather_index != 0: haze = haze.lerp(Color(0.62, 0.66, 0.70) if field_weather.time_index != 3 else Color(0.12, 0.14, 0.2), 0.6)
	terrain_material.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))
	lamp_material.emission_energy_multiplier = 3.0 if field_weather.time_index == 3 else (1.2 if field_weather.time_index == 2 else 0.3)
