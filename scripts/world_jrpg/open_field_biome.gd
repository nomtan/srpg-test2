extends RefCounted
## Biome system for JRPGWorldSample2's open field.
##
## The world reports a handful of designed landform signals per point (how much it is
## town, ruins, farmland, lakeshore, forest, ...); compose() turns them into blended
## biome weights that always sum to 1. Those weights and every BiomeData parameter are
## precomputed on a 2 m grid, so terrain, vegetation and shaders read one shared source
## instead of hard-coding biome rules of their own. bake() fills the grid over a whole
## map at once; the streaming open field instead bakes one Patch per tile (bake_patch)
## and writes it into the shared shader maps (init_maps / write_patch / flush_maps).
enum Biome { PLAINS, FOREST, DEEP_FOREST, HIGHLAND, MOUNTAIN, LAKESHORE, WETLAND, FARMLAND, SETTLEMENT, RUINS }
## Landform signals in the order the world's signal callable returns them (each 0..1).
enum Landform { SETTLEMENT, RUINS, FARMLAND, SHORE, WETLAND, MOUNTAIN, FOREST, DEEP, HIGHLAND }
const COUNT := 10
const LANDFORM_COUNT := 9
const NAMES := ["PLAINS", "FOREST", "DEEP_FOREST", "HIGHLAND", "MOUNTAIN", "LAKESHORE", "WETLAND", "FARMLAND", "SETTLEMENT", "RUINS"]
const DEBUG_COLORS := [Color("6fd04a"), Color("2f7d32"), Color("123f1c"), Color("e8d43c"), Color("8c8c8c"),
	Color("3fe0e0"), Color("2c5fd6"), Color("8a5a2b"), Color("f08a24"), Color("9b4fd0")]
## Blended parameters precomputed per grid point. ground_roughness scales the visual-only
## micro relief; rockiness exposes stone patches in the ground shader; litter darkens the
## forest floor; min/max_height bound where vegetation grows; max_slope is the steepest
## ground (rise / run) that still carries trees.
const PARAMS := ["grass_density", "flower_density", "tree_density", "rock_density", "broadleaf_weight",
	"conifer_weight", "ground_roughness", "wetness", "min_height", "max_height", "max_slope", "tree_scale",
	"rockiness", "litter"]
## Indices into PARAMS, for hot loops reading param_grid[cell(x, z) + Param.X] directly.
enum Param { GRASS_DENSITY, FLOWER_DENSITY, TREE_DENSITY, ROCK_DENSITY, BROADLEAF_WEIGHT,
	CONIFER_WEIGHT, GROUND_ROUGHNESS, WETNESS, MIN_HEIGHT, MAX_HEIGHT, MAX_SLOPE, TREE_SCALE, ROCKINESS, LITTER }
## Per-biome data. ground_tint is sRGB; tree_density is the chance of a tree per 4 m cell.
const DATA := {
	Biome.PLAINS: {"ground_tint": Color(0.48, 0.64, 0.29), "grass_density": 1.0, "flower_density": 1.0, "tree_density": 0.02, "rock_density": 0.010,
		"broadleaf_weight": 0.85, "conifer_weight": 0.15, "ground_roughness": 0.5, "wetness": 0.0, "min_height": 10.6, "max_height": 70.0, "max_slope": 0.75, "tree_scale": 1.0, "rockiness": 0.05, "litter": 0.00},
	Biome.FOREST: {"ground_tint": Color(0.34, 0.52, 0.25), "grass_density": 0.6, "flower_density": 0.35, "tree_density": 0.7, "rock_density": 0.028,
		"broadleaf_weight": 0.75, "conifer_weight": 0.25, "ground_roughness": 0.8, "wetness": 0.05, "min_height": 10.6, "max_height": 72.0, "max_slope": 0.85, "tree_scale": 1.05, "rockiness": 0.08, "litter": 0.45},
	Biome.DEEP_FOREST: {"ground_tint": Color(0.24, 0.42, 0.21), "grass_density": 0.35, "flower_density": 0.08, "tree_density": 0.95, "rock_density": 0.035,
		"broadleaf_weight": 0.45, "conifer_weight": 0.55, "ground_roughness": 1.0, "wetness": 0.15, "min_height": 10.6, "max_height": 72.0, "max_slope": 0.9, "tree_scale": 1.25, "rockiness": 0.12, "litter": 0.85},
	Biome.HIGHLAND: {"ground_tint": Color(0.62, 0.68, 0.34), "grass_density": 0.8, "flower_density": 0.55, "tree_density": 0.13, "rock_density": 0.05,
		"broadleaf_weight": 0.2, "conifer_weight": 0.8, "ground_roughness": 0.7, "wetness": 0.0, "min_height": 10.6, "max_height": 74.0, "max_slope": 0.85, "tree_scale": 0.95, "rockiness": 0.25, "litter": 0.00},
	Biome.MOUNTAIN: {"ground_tint": Color(0.56, 0.63, 0.48), "grass_density": 0.3, "flower_density": 0.12, "tree_density": 0.05, "rock_density": 0.11,
		"broadleaf_weight": 0.0, "conifer_weight": 1.0, "ground_roughness": 1.0, "wetness": 0.0, "min_height": 10.6, "max_height": 76.0, "max_slope": 0.8, "tree_scale": 0.85, "rockiness": 0.75, "litter": 0.00},
	Biome.LAKESHORE: {"ground_tint": Color(0.45, 0.66, 0.42), "grass_density": 0.6, "flower_density": 0.3, "tree_density": 0.03, "rock_density": 0.03,
		"broadleaf_weight": 0.8, "conifer_weight": 0.2, "ground_roughness": 0.3, "wetness": 0.55, "min_height": 11.0, "max_height": 40.0, "max_slope": 0.6, "tree_scale": 0.9, "rockiness": 0.10, "litter": 0.00},
	Biome.WETLAND: {"ground_tint": Color(0.32, 0.50, 0.38), "grass_density": 1.1, "flower_density": 0.2, "tree_density": 0.04, "rock_density": 0.006,
		"broadleaf_weight": 0.9, "conifer_weight": 0.1, "ground_roughness": 0.25, "wetness": 0.8, "min_height": 10.8, "max_height": 40.0, "max_slope": 0.5, "tree_scale": 0.9, "rockiness": 0.00, "litter": 0.10},
	Biome.FARMLAND: {"ground_tint": Color(0.58, 0.66, 0.33), "grass_density": 0.55, "flower_density": 0.5, "tree_density": 0.012, "rock_density": 0.004,
		"broadleaf_weight": 1.0, "conifer_weight": 0.0, "ground_roughness": 0.15, "wetness": 0.1, "min_height": 10.6, "max_height": 60.0, "max_slope": 0.5, "tree_scale": 1.0, "rockiness": 0.00, "litter": 0.00},
	Biome.SETTLEMENT: {"ground_tint": Color(0.51, 0.65, 0.32), "grass_density": 0.4, "flower_density": 0.6, "tree_density": 0.0, "rock_density": 0.0,
		"broadleaf_weight": 1.0, "conifer_weight": 0.0, "ground_roughness": 0.1, "wetness": 0.0, "min_height": 10.6, "max_height": 60.0, "max_slope": 0.5, "tree_scale": 1.0, "rockiness": 0.00, "litter": 0.00},
	Biome.RUINS: {"ground_tint": Color(0.53, 0.60, 0.45), "grass_density": 0.7, "flower_density": 0.25, "tree_density": 0.04, "rock_density": 0.05,
		"broadleaf_weight": 0.5, "conifer_weight": 0.5, "ground_roughness": 0.6, "wetness": 0.1, "min_height": 10.6, "max_height": 60.0, "max_slope": 0.7, "tree_scale": 1.0, "rockiness": 0.30, "litter": 0.10},
}

class BiomeData:
	var biome: int
	var ground_tint: Color
	var grass_density: float
	var flower_density: float
	var tree_density: float
	var rock_density: float
	var broadleaf_weight: float
	var conifer_weight: float
	var ground_roughness: float
	var wetness: float
	var min_height: float
	var max_height: float
	var max_slope: float
	var tree_scale: float
	var rockiness: float
	var litter: float

	func _init(id: int, values: Dictionary) -> void:
		biome = id
		for key: String in values: set(key, values[key])

var table: Array[BiomeData] = []
var spacing := 2.0
var size := 0
## Flat grids: weight_grid[k * COUNT + biome], param_grid[k * PARAMS.size() + param].
var weight_grid := PackedFloat32Array()
var param_grid := PackedFloat32Array()
var tint := PackedColorArray()
## Every biome's PARAMS values in a row (COUNT x PARAMS.size()) and its ground tint with
## the wetness in alpha, for blending.
var table_values := PackedFloat32Array()
var tint_values := PackedColorArray()
## Streaming shader maps (see init_maps): images over the whole field and the textures the
## shaders sample.
var tint_image: Image
var surface_image: Image
var debug_image: Image
var tint_map: ImageTexture
var surface_map: ImageTexture
var debug_map: ImageTexture
var maps_dirty := false

## One streaming tile's window of the biome grid: points (i0 .. i0 + span - 1,
## j0 .. j0 + span - 1), `spacing` m apart. A point's values depend only on its position,
## so patches that overlap agree exactly. Lookups mirror the whole-map ones below.
class Patch:
	var i0 := 0
	var j0 := 0
	var span := 0
	var spacing := 2.0
	var weights := PackedFloat32Array()
	var params := PackedFloat32Array()
	var tint := PackedColorArray()

	func _nearest(x: float, z: float) -> int:
		return clampi(roundi(z / spacing) - j0, 0, span - 1) * span + clampi(roundi(x / spacing) - i0, 0, span - 1)

	## Offset of the nearest grid point in params; add a Param index to read a value.
	func cell(x: float, z: float) -> int:
		return _nearest(x, z) * PARAMS.size()

	func weight(id: int, x: float, z: float) -> float:
		return weights[_nearest(x, z) * COUNT + id]

	func param_smooth(index: int, x: float, z: float) -> float:
		return _smooth(params, PARAMS.size(), index, x, z)

	func _smooth(grid: PackedFloat32Array, stride: int, offset: int, x: float, z: float) -> float:
		var fx := clampf(x / spacing - i0, 0.0, span - 1.001)
		var fz := clampf(z / spacing - j0, 0.0, span - 1.001)
		var i := int(fx)
		var j := int(fz)
		var k := j * span + i
		var top := lerpf(grid[k * stride + offset], grid[(k + 1) * stride + offset], fx - i)
		var bottom := lerpf(grid[(k + span) * stride + offset], grid[(k + span + 1) * stride + offset], fx - i)
		return lerpf(top, bottom, fz - j)

	func weights_at(x: float, z: float) -> Dictionary:
		var result := {}
		for id in COUNT:
			var w := _smooth(weights, COUNT, id, x, z)
			if w > 0.01: result[id] = w
		return result

	func biome_at(x: float, z: float) -> int:
		var best := Biome.PLAINS
		var best_weight := -1.0
		for id in COUNT:
			var w := _smooth(weights, COUNT, id, x, z)
			if w > best_weight:
				best = id
				best_weight = w
		return best

func _init() -> void:
	for id in COUNT: table.append(BiomeData.new(id, DATA[id]))
	for id in COUNT:
		for name: String in PARAMS: table_values.append(table[id].get(name))
		var d := table[id]
		tint_values.append(Color(d.ground_tint.r, d.ground_tint.g, d.ground_tint.b, d.wetness))

func data(biome: int) -> BiomeData:
	return table[biome]

## Overlay biomes and the landform signal each takes, in claiming order (flat pairs: worker
## threads baking patches would contend for the reference counts of nested arrays).
const OVERLAYS := [Biome.SETTLEMENT, Landform.SETTLEMENT, Biome.RUINS, Landform.RUINS, Biome.FARMLAND, Landform.FARMLAND,
	Biome.LAKESHORE, Landform.SHORE, Biome.WETLAND, Landform.WETLAND, Biome.MOUNTAIN, Landform.MOUNTAIN]

## Turns landform signals into weights that sum to 1. Overlays claim their share first
## (settlement, ruins, farmland, shore, wetland, mountain); forest, highland and plains
## split what is left, so every boundary is a soft blend rather than a hard switch.
static func compose(s: PackedFloat32Array) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(COUNT)
	var rest := 1.0
	for o in range(0, OVERLAYS.size(), 2):
		var share := clampf(s[OVERLAYS[o + 1]], 0.0, 1.0) * rest
		w[OVERLAYS[o]] = share
		rest -= share
	var forest := clampf(s[Landform.FOREST], 0.0, 1.0)
	var deep := forest * clampf(s[Landform.DEEP], 0.0, 1.0)
	w[Biome.DEEP_FOREST] = deep * rest
	w[Biome.FOREST] = (forest - deep) * rest
	rest *= 1.0 - forest
	var highland := clampf(s[Landform.HIGHLAND], 0.0, 1.0)
	w[Biome.HIGHLAND] = highland * rest
	w[Biome.PLAINS] = (1.0 - highland) * rest
	return w

## Samples signal_at(x, z) -> PackedFloat32Array over [0, world_size]² every `spacing` m.
func bake(world_size: int, signal_at: Callable) -> void:
	size = int(world_size / spacing) + 1
	var count := size * size
	var param_count := PARAMS.size()
	weight_grid.resize(count * COUNT)
	param_grid.resize(count * param_count)
	param_grid.fill(0.0)
	tint.resize(count)
	for j in size:
		for i in size:
			var w := compose(signal_at.call(i * spacing, j * spacing))
			var k := j * size + i
			var color := Color(0, 0, 0, 0)
			for id in COUNT:
				weight_grid[k * COUNT + id] = w[id]
				if w[id] <= 0.0: continue
				var d := table[id]
				color += Color(d.ground_tint.r, d.ground_tint.g, d.ground_tint.b, d.wetness) * w[id]
				for p in param_count:
					param_grid[k * param_count + p] += table_values[id * param_count + p] * w[id]
			tint[k] = color

## Bakes the grid points (i0 .. i0 + span - 1, j0 .. j0 + span - 1) from
## signal_at(x, z) -> PackedFloat32Array, exactly as bake() would. Reads only the biome
## table, so tiles bake their patches on worker threads.
func bake_patch(i0: int, j0: int, span: int, signal_at: Callable) -> Patch:
	var patch := Patch.new()
	patch.i0 = i0
	patch.j0 = j0
	patch.span = span
	patch.spacing = spacing
	var param_count := PARAMS.size()
	patch.weights.resize(span * span * COUNT)
	patch.params.resize(span * span * param_count)
	patch.tint.resize(span * span)
	for j in span:
		for i in span:
			var w := compose(signal_at.call((i0 + i) * spacing, (j0 + j) * spacing))
			var k := j * span + i
			var color := Color(0, 0, 0, 0)
			for id in COUNT:
				patch.weights[k * COUNT + id] = w[id]
				if w[id] <= 0.0: continue
				color += tint_values[id] * w[id]
				for p in param_count:
					patch.params[k * param_count + p] += table_values[id * param_count + p] * w[id]
			patch.tint[k] = color
	return patch

## Streaming maps over [0, world_size]²: plains until the tiles' patches arrive.
func init_maps(world_size: int) -> void:
	size = int(world_size / spacing) + 1
	var plains := table[Biome.PLAINS]
	tint_image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	tint_image.fill(Color(plains.ground_tint.r, plains.ground_tint.g, plains.ground_tint.b, plains.wetness))
	surface_image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	surface_image.fill(Color(plains.rockiness, plains.litter, 0.0, 1.0))
	debug_image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	debug_image.fill(DEBUG_COLORS[Biome.PLAINS])
	tint_map = ImageTexture.create_from_image(tint_image)
	surface_map = ImageTexture.create_from_image(surface_image)
	debug_map = ImageTexture.create_from_image(debug_image)

## A patch's texels for the streaming maps — tint, surface (rockiness, litter) and debug
## colors — for its inner points (the outermost ring belongs to the neighbors). Built on
## the tile's worker thread; write_patch only copies them in.
func patch_images(patch: Patch) -> Array[Image]:
	var count := PARAMS.size()
	var inner := patch.span - 2
	var tint_texels := Image.create_empty(inner, inner, false, Image.FORMAT_RGBA8)
	var surface_texels := Image.create_empty(inner, inner, false, Image.FORMAT_RGBA8)
	var debug_texels := Image.create_empty(inner, inner, false, Image.FORMAT_RGBA8)
	for j in inner:
		for i in inner:
			var k := (j + 1) * patch.span + i + 1
			tint_texels.set_pixel(i, j, patch.tint[k])
			surface_texels.set_pixel(i, j, Color(patch.params[k * count + Param.ROCKINESS], patch.params[k * count + Param.LITTER], 0.0, 1.0))
			var color := Color(0, 0, 0, 1)
			for id in COUNT:
				var w := patch.weights[k * COUNT + id]
				if w > 0.0:
					color.r += DEBUG_COLORS[id].r * w
					color.g += DEBUG_COLORS[id].g * w
					color.b += DEBUG_COLORS[id].b * w
			debug_texels.set_pixel(i, j, color)
	return [tint_texels, surface_texels, debug_texels]

## Copies a patch's texels (patch_images) into the streaming maps; the next flush_maps
## uploads them.
func write_patch(patch: Patch, texels: Array[Image]) -> void:
	var at := Vector2i(patch.i0 + 1, patch.j0 + 1)
	var rect := Rect2i(Vector2i.ZERO, texels[0].get_size())
	tint_image.blit_rect(texels[0], rect, at)
	surface_image.blit_rect(texels[1], rect, at)
	debug_image.blit_rect(texels[2], rect, at)
	maps_dirty = true

## Uploads the streaming maps if a patch arrived since the last flush.
func flush_maps() -> void:
	if not maps_dirty: return
	maps_dirty = false
	tint_map.update(tint_image)
	surface_map.update(surface_image)
	debug_map.update(debug_image)

func _index(x: float, z: float) -> int:
	return clampi(roundi(z / spacing), 0, size - 1) * size + clampi(roundi(x / spacing), 0, size - 1)

## Offset of the nearest grid point in param_grid; add a Param index to read a value.
## Cheap enough for per-blade vegetation loops.
func cell(x: float, z: float) -> int:
	return _index(x, z) * PARAMS.size()

## Nearest-grid weight of one biome.
func weight(id: int, x: float, z: float) -> float:
	return weight_grid[_index(x, z) * COUNT + id]

func param(name: String, x: float, z: float) -> float:
	return param_grid[cell(x, z) + PARAMS.find(name)]

## Bilinear lookup of one Param for smooth values (micro relief, HUD).
func param_smooth(index: int, x: float, z: float) -> float:
	return _bilinear(param_grid, PARAMS.size(), index, x, z)

func _bilinear(grid: PackedFloat32Array, stride: int, offset: int, x: float, z: float) -> float:
	var fx := clampf(x / spacing, 0.0, size - 1.001)
	var fz := clampf(z / spacing, 0.0, size - 1.001)
	var i := int(fx)
	var j := int(fz)
	var k := j * size + i
	var top := lerpf(grid[k * stride + offset], grid[(k + 1) * stride + offset], fx - i)
	var bottom := lerpf(grid[(k + size) * stride + offset], grid[(k + size + 1) * stride + offset], fx - i)
	return lerpf(top, bottom, fz - j)

## {Biome: weight} for every biome with a meaningful share at this point.
func weights_at(x: float, z: float) -> Dictionary:
	var result := {}
	for id in COUNT:
		var w := _bilinear(weight_grid, COUNT, id, x, z)
		if w > 0.01: result[id] = w
	return result

func biome_at(x: float, z: float) -> int:
	var best := Biome.PLAINS
	var best_weight := -1.0
	for id in COUNT:
		var w := _bilinear(weight_grid, COUNT, id, x, z)
		if w > best_weight:
			best = id
			best_weight = w
	return best

## RGB = blended ground tint (sRGB), A = blended wetness; texel centers sit on the grid.
func tint_texture() -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for j in size:
		for i in size:
			image.set_pixel(i, j, tint[j * size + i])
	return ImageTexture.create_from_image(image)

## R = rockiness, G = forest-floor litter, both blended; sampled like tint_texture().
func surface_texture() -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var count := PARAMS.size()
	for j in size:
		for i in size:
			var k := (j * size + i) * count
			image.set_pixel(i, j, Color(param_grid[k + Param.ROCKINESS], param_grid[k + Param.LITTER], 0.0, 1.0))
	return ImageTexture.create_from_image(image)

## Blended debug colors, so transitions show as gradients between the flat biome colors.
func debug_texture() -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for j in size:
		for i in size:
			var k := j * size + i
			var color := Color(0, 0, 0, 1)
			for id in COUNT:
				var w := weight_grid[k * COUNT + id]
				if w > 0.0:
					color.r += DEBUG_COLORS[id].r * w
					color.g += DEBUG_COLORS[id].g * w
					color.b += DEBUG_COLORS[id].b * w
			image.set_pixel(i, j, color)
	return ImageTexture.create_from_image(image)

## Shader parameters mapping world XZ onto the baked textures.
func uv_scale() -> float:
	return 1.0 / (spacing * size)

func uv_offset() -> float:
	return 0.5 / size
