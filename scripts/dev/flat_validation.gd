extends Node3D

## Phase17-Step1 (docs/dev/phase/phase17-step1.md T9): the tool used to decide
## between Plan A (solid color) and Plan B (existing pixel texture) for the
## flat/lowpoly-diorama terrain look, and to dial in the shared face-factor /
## variation / strata parameters both plans run through.
##
## F1/F2 swap ONLY the terrain material (geometry, camera, and every other
## parameter stay fixed) so the two plans can be judged on the same frame.
## F3 captures a same-state A/B screenshot pair to docs/dev/assets/.
## Ctrl+S exports the current parameters - that export is what step1's
## completion condition asks to transcribe into docs/dev/flat_shading_spec.md.

const BATTLE_ENVIRONMENT: Environment = preload("res://assets/environment/battle_atmosphere.tres")
const VISUAL_THEME: MapVisualTheme = preload("res://assets/terrain/theme_default.tres")
const CHARACTER_MODEL := "res://assets/characters/py/base_body.glb"
const CHARACTER_FACE_TEXTURE := "res://assets/characters/textures/anime_face_vain.png"

# Painted prop placement is intentionally disabled in this validation scene.
# Generated transparent assets remain available for later production use.
const PAINTED_PROP_TEXTURES := {}

const REFERENCE_TERRAIN_TEXTURES := {
	"grass": preload("res://assets/terrain/reference/terrain_grass_top_ref.png"),
	"dirt": preload("res://assets/terrain/reference/terrain_dirt_top_ref.png"),
	"stone": preload("res://assets/terrain/reference/terrain_stone_top_ref.png"),
	"cliff": preload("res://assets/terrain/reference/terrain_cliff_side_ref.png"),
	"cliff_grass": preload("res://assets/terrain/reference/terrain_cliff_side_top_ref.png"),
}

# The former generated billboard characters are no longer part of this
# validation scene. Keep the unused helper parse-safe without loading deleted
# files; the one displayed unit comes from the real game model above.
const PAINTED_CHARACTER_TEXTURES := {}

const FLAT_TERRAIN_SOLID_SHADER := preload("res://shaders/flat/flat_terrain_solid.gdshader")
const FLAT_TERRAIN_TEX_SHADER := preload("res://shaders/flat/flat_terrain_tex.gdshader")
const FLAT_CHARACTER_SHADER := preload("res://shaders/flat/flat_character.gdshader")
const FLAT_VEGETATION_SHADER := preload("res://shaders/flat/flat_vegetation.gdshader")
const FLAT_GRASS_TRANSITION_SHADER := preload("res://shaders/flat/flat_grass_transition.gdshader")

const PALETTE_RESOLVED_PATH := "res://tools/asset_gen/palette_resolved.json"
const EXPORT_PATH := "res://scenes/dev/flat_preset_export.json"
const SCREENSHOT_SOLID_PATH := "res://docs/dev/assets/flat_ab_solid.png"
const SCREENSHOT_TEX_PATH := "res://docs/dev/assets/flat_ab_tex.png"
const REFERENCE_PREVIEW_PATH := "res://docs/dev/assets/flat_reference_preview.png"

const MAP_WIDTH := 18
const MAP_DEPTH := 14

# Explicit scene-asset -> palette.json "colors" key mapping (fix F1-3, see
# docs/dev/terrain_tile_inventory.md). Deliberately NOT a substring/filename
# heuristic - an unmapped asset must fail loudly (magenta + warning), not
# silently guess a bucket. Multiple assets sharing a palette key means they
# share the same underlying mesh/texture (e.g. stone_road/rock/wall all
# resolve to terrain_stone_top_01.glb), not a judgment call made here.
const TERRAIN_ASSET_TO_PALETTE_KEY := {
	"terrain_grass_top_01.glb": "grass",
	"terrain_dirt_top_01.glb": "dirt",
	"terrain_stone_top_01.glb": "stone",
	"terrain_stair_01.glb": "stone", # build_terrain_glb.py bakes the stone-top texture onto the stair asset
	"terrain_cliff_side_01.glb": "cliff_side",
	"terrain_cliff_side_top_01.glb": "cliff_side_top",
	"terrain_cliff_stone_01.glb": "cliff_stone",
	"water_plane.tscn": "water",
	"water_side.tscn": "water",
	"lava_plane.tscn": "lava",
	"lava_side.tscn": "lava",
	"stone_brick.glb": "stone_brick",
	"stone_brick_stairs.glb": "stone_brick",
	"infested_cracked_stone_bricks.glb": "infested_cracked_stone_bricks",
	"chiseled_stone_brick.glb": "chiseled_stone_brick",
	"bricks.glb": "bricks",
	"brick_stairs.glb": "bricks",
	"cobblestone.glb": "cobblestone",
	"cobblestone_stairs.glb": "cobblestone",
}

# Cross-quad foliage (fix F2): always routed to flat_vegetation.gdshader
# regardless of Plan A/B, never through the terrain bucket/magenta path.
const VEGETATION_ASSET_NAMES := [
	"prop_grass_short_01.tscn", "prop_grass_short_02.tscn", "prop_grass_short_03.tscn",
	"prop_grass_mid_01.tscn", "prop_grass_mid_02.tscn", "prop_grass_mid_03.tscn",
	"prop_grass_tall_01.tscn",
]

const UNDEFINED_TILE_COLOR := Color("#ff00ff")
const TERRAIN_STYLE_TINTS := {
	"grass": Vector3(1.16, 1.08, 0.72),
	"dirt": Vector3(1.14, 1.08, 0.86),
	"stone": Vector3(1.06, 1.04, 0.94),
	"cliff_side": Vector3(1.12, 1.06, 0.82),
	"cliff_side_top": Vector3(1.12, 1.06, 0.82),
	"cliff_stone": Vector3(1.05, 1.03, 0.91),
}

var params := {
	"face_top": 1.01,
	"face_side_x": 0.68,
	"face_side_z": 0.90,
	"face_bottom": 0.58,
	"tile_size": 0.2,
	"hue_jitter": 0.035,
	"grass_hue_jitter": 0.08,
	"dirt_hue_jitter": 0.01,
	"sat_jitter": 0.11,
	"val_jitter": 0.014,
	"strata_enabled": true,
	"strata_height": 0.5,
	"strata_hue_jitter": 0.015,
	"strata_val_jitter": 0.04,
	"character_face_top_boost": 1.04,
	"background_color": Color("#111313"),
	"fog_density": 0.002,
	"fog_color": Color("#52605d"),
}

var terrain_mode := "A" # Keep the validation scene on the solid-color baseline; B remains available on F2.
var free_orbit := false
var presentation_mode := false

var environment_resource: Environment
var camera_controller: CameraController
var bucket_colors: Dictionary = {}
var validation_map: MapData

# Each entry: {mesh_instance, surface_index, solid_material, tex_material}
var terrain_entries: Array = []
var transition_entries: Array = []
var character_materials: Array[ShaderMaterial] = []
var vegetation_materials: Array[ShaderMaterial] = []
var reference_prop_materials: Array[ShaderMaterial] = []
var _reference_material_cache: Dictionary = {}

# fix F1-4: every unmapped/uncolored tile surface increments this so the
# validation UI can show "未定義タイル: N件". Per phase17-step1-fix.md, A/B
# judgment must not proceed while this is > 0.
var undefined_tile_count := 0
var _warned_asset_names: Dictionary = {}

var sliders: Dictionary = {}
var status_label: Label
var undefined_label: Label
var ui_layer: CanvasLayer


func _ready() -> void:
	bucket_colors = _load_bucket_colors()
	_build_environment_and_camera()
	_build_terrain()
	_build_characters()
	_build_ui()
	_apply_terrain_mode(terrain_mode)
	_push_character_params()
	_push_vegetation_params()
	if "--auto-capture-reference" in OS.get_cmdline_user_args():
		_capture_reference_preview.call_deferred()


# ---------------------------------------------------------------- Palette

func _load_bucket_colors() -> Dictionary:
	var colors := {}
	var file := FileAccess.open(PALETTE_RESOLVED_PATH, FileAccess.READ)
	if not file:
		push_warning("Cannot read %s - run tools/asset_gen/gen_palette_flat.py first" % PALETTE_RESOLVED_PATH)
		return colors
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.has("colors"):
		for key in parsed["colors"]:
			var entry: Dictionary = parsed["colors"][key]
			if entry.has("resolved"):
				colors[key] = Color(entry["resolved"])
	return colors


# ---------------------------------------------------------------- Environment

func _build_environment_and_camera() -> void:
	# Duplicate so slider tweaks never mutate the shared production resource.
	environment_resource = BATTLE_ENVIRONMENT.duplicate()
	environment_resource.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_resource.tonemap_exposure = 1.0
	environment_resource.ssao_enabled = false
	environment_resource.ssil_enabled = false
	environment_resource.sdfgi_enabled = false
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = params.background_color
	environment_resource.fog_enabled = true
	environment_resource.fog_light_color = params.fog_color
	environment_resource.fog_density = params.fog_density
	environment_resource.glow_enabled = true
	environment_resource.glow_intensity = 0.25
	environment_resource.glow_hdr_threshold = 1.5
	environment_resource.adjustment_enabled = true
	environment_resource.adjustment_brightness = 1.03
	environment_resource.adjustment_contrast = 0.96
	environment_resource.adjustment_saturation = 0.88

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment_resource
	add_child(world_environment)

	# Unshaded materials ignore this light entirely; it stays only in case a
	# StandardMaterial3D element remains somewhere (see T8 notes).
	var directional_light := DirectionalLight3D.new()
	directional_light.name = "DirectionalLight3D"
	directional_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	directional_light.shadow_enabled = false
	add_child(directional_light)

	camera_controller = CameraController.new()
	camera_controller.name = "CameraController"
	add_child(camera_controller)
	var camera := camera_controller.setup()
	# About 30 degrees of elevation: four degrees above the previous validation
	# angle while preserving the same horizontal viewing direction.
	camera_controller.focus_offset = Vector3(30.0, 27.8, -38.0)
	# Frame the scene from inside the battlefield: the lower target lifts the
	# ground plane in screen space, while the tighter ortho size lets the outer
	# cliffs leave the frame like the target gameplay composition.
	camera_controller.focus_target = Vector3(7.0, 0.50, 8.5)
	camera.position = camera_controller.focus_target + camera_controller.focus_offset
	camera.size = 14.0
	camera.look_at_from_position(camera.position, camera_controller.focus_target, Vector3.UP)
	camera.current = true


# -------------------------------------------------------------------- Terrain

func _build_terrain() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = VISUAL_THEME
	renderer.grass_prop_chance = 0.0
	renderer.grass_prop_seed = 4171
	renderer.grass_transitions_enabled = true
	renderer.grass_transition_fringe_width = 0.20
	# Water/lava cells have logical height 0 (the upper cube is removed), while
	# the liquid fills the resulting cavity to slightly below the height-1 rim.
	renderer.fluid_surface_fill_offset = 0.88
	renderer.painted_grass_overlays_enabled = true
	renderer.painted_grass_overlay_seed = 8123
	renderer.painted_grass_edge_fringe_width = 0.18
	add_child(renderer)
	validation_map = _create_validation_map()
	renderer.build_from_map_data(validation_map)
	_collect_terrain_materials(renderer)


func _create_validation_map() -> MapData:
	var data := MapData.new()
	data.width = MAP_WIDTH
	data.depth = MAP_DEPTH
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"
			data.cells.append(cell)
	data.rebuild_lookup()

	# Raised grassy shelves frame the play space instead of forming a square
	# material showcase. Their uneven fronts create the diorama silhouette.
	for z in range(0, 4):
		for x in range(0, 13):
			if z < 3 or x in range(2, 11):
				data.get_cell(Vector2i(x, z)).height = 2
	for z in range(0, 6):
		for x in range(15, MAP_WIDTH):
			if z < 5 or x >= 16:
				data.get_cell(Vector2i(x, z)).height = 2

	# A broad, irregular dirt clearing gives units and props a readable stage.
	var clearing_center := Vector2(9.3, 7.5)
	for z in range(4, 12):
		for x in range(3, 16):
			var normalized := Vector2(
				(float(x) - clearing_center.x) / 6.5,
				(float(z) - clearing_center.y) / 3.8
			)
			if normalized.length_squared() < 1.0:
				data.get_cell(Vector2i(x, z)).terrain = "dirt"

	# A winding approach joins the northern terrace and the south edge.
	const PATH_CENTERS := [8, 8, 9, 9, 9, 8, 8, 9, 10, 10, 11, 11, 12, 12]
	for z in MAP_DEPTH:
		var half_width := 1 if z in range(3, 12) else 0
		for x in range(PATH_CENTERS[z] - half_width, PATH_CENTERS[z] + half_width + 1):
			var cell := data.get_cell(Vector2i(x, z))
			if cell:
				cell.terrain = "dirt"

	# In this camera orientation the south-west area projects to the back of
	# the screen. Raise a spacious test terrace there, replacing the water inlet
	# while the micro-height gallery is under evaluation.
	for z in range(4, MAP_DEPTH):
		for x in range(0, 8):
			var gallery_base := data.get_cell(Vector2i(x, z))
			gallery_base.height = 2

	# 3^9 exhaustive combinations would be 19,683 cells. This gallery instead
	# covers all useful canonical forms and their directional rotations.
	var micro_patterns := [
		# Three uniform levels.
		PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]),
		PackedInt32Array([1, 1, 1, 1, 1, 1, 1, 1, 1]),
		PackedInt32Array([2, 2, 2, 2, 2, 2, 2, 2, 2]),
		# Four cardinal stair directions.
		PackedInt32Array([0, 0, 0, 1, 1, 1, 2, 2, 2]),
		PackedInt32Array([2, 2, 2, 1, 1, 1, 0, 0, 0]),
		PackedInt32Array([0, 1, 2, 0, 1, 2, 0, 1, 2]),
		PackedInt32Array([2, 1, 0, 2, 1, 0, 2, 1, 0]),
		# Four diagonal stair directions.
		PackedInt32Array([0, 0, 1, 0, 1, 2, 1, 2, 2]),
		PackedInt32Array([1, 0, 0, 2, 1, 0, 2, 2, 1]),
		PackedInt32Array([2, 2, 1, 2, 1, 0, 1, 0, 0]),
		PackedInt32Array([1, 2, 2, 0, 1, 2, 0, 0, 1]),
		# Peak, pit, two ridges, two saddles, and an L-shaped corner.
		PackedInt32Array([0, 1, 0, 1, 2, 1, 0, 1, 0]),
		PackedInt32Array([2, 1, 2, 1, 0, 1, 2, 1, 2]),
		PackedInt32Array([0, 2, 0, 0, 2, 0, 0, 2, 0]),
		PackedInt32Array([0, 0, 0, 2, 2, 2, 0, 0, 0]),
		PackedInt32Array([2, 0, 2, 1, 1, 1, 0, 2, 0]),
		PackedInt32Array([0, 2, 0, 1, 1, 1, 2, 0, 2]),
		PackedInt32Array([0, 0, 0, 0, 1, 1, 0, 1, 2]),
	]
	var gallery_positions: Array[Vector2i] = []
	for z in [5, 7, 9, 11]:
		for x in [0, 2, 4, 6]:
			gallery_positions.append(Vector2i(x, z))
	gallery_positions.append(Vector2i(0, 13))
	gallery_positions.append(Vector2i(2, 13))
	for index in mini(micro_patterns.size(), gallery_positions.size()):
		var pattern_cell := data.get_cell(gallery_positions[index])
		pattern_cell.terrain = "dirt"
		# The base of each pattern starts flush with the height-2 rear terrace;
		# its three micro stages then rise visibly to height 3.
		pattern_cell.height = 3
		pattern_cell.set_micro_height_profile(micro_patterns[index])

	# Actual terrain stone blocks for palette/material tuning. These use the
	# production terrain_stone_top_01.glb rather than procedural round rocks.
	for stone_data in [
		[Vector2i(12, 7), 2],
		[Vector2i(14, 8), 2],
		[Vector2i(15, 8), 2],
		[Vector2i(13, 10), 2],
		[Vector2i(14, 10), 3],
	]:
		var stone_cell := data.get_cell(stone_data[0])
		stone_cell.terrain = "stone"
		stone_cell.height = stone_data[1]

	# Both pools are 2x3 and one full cube layer below the surrounding ground.
	# Neighboring dirt blocks therefore expose the recessed pool walls.
	for z in range(3, 6):
		for x in range(10, 12):
			var water_cell := data.get_cell(Vector2i(x, z))
			water_cell.terrain = "water"
			water_cell.height = 0
	for z in range(3, 6):
		for x in range(14, 16):
			var lava_cell := data.get_cell(Vector2i(x, z))
			lava_cell.terrain = "lava"
			lava_cell.height = 0

	return data


func _add_map_decoration(data: MapData, position: Vector2i, kind: String, rotation: float, scale: Vector3) -> void:
	var cell := data.get_cell(position)
	if not cell or cell.terrain != "grass":
		return
	var decoration := MapDecorationData.new()
	decoration.grid_position = position
	decoration.kind = kind
	decoration.rotation_degrees = rotation
	decoration.scale = scale
	cell.props.append(decoration)


func _collect_terrain_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh:
			for i in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.get_active_material(i)
				if source is ShaderMaterial and (source as ShaderMaterial).shader == FLAT_GRASS_TRANSITION_SHADER:
					var transition_material := source as ShaderMaterial
					transition_material.set_shader_parameter("style_tint", Vector3.ONE)
					transition_material.set_shader_parameter("grass_tex", REFERENCE_TERRAIN_TEXTURES.grass)
					transition_entries.append({
						"mesh_instance": mesh_instance,
						"material": transition_material,
					})
				elif source is BaseMaterial3D:
					_route_terrain_surface(mesh_instance, i, source as BaseMaterial3D)
	for child in root.get_children():
		_collect_terrain_materials(child)


func _resolve_owner_path(mesh_instance: MeshInstance3D) -> String:
	var owner_path := mesh_instance.owner.scene_file_path if mesh_instance.owner else ""
	if not owner_path.is_empty() and mesh_instance.owner != self:
		return owner_path
	# Walk up to find the instanced scene root, which carries scene_file_path.
	# Stop before `self` (the validation scene's own root) - procedurally
	# built nodes with no instanced-scene ancestor (e.g. VoxelMap's debug
	# background plane) would otherwise resolve to flat_validation.tscn
	# itself, which is not a terrain asset.
	var node: Node = mesh_instance
	while node and node != self and node.scene_file_path.is_empty():
		node = node.get_parent()
	if not node or node == self:
		return ""
	return node.scene_file_path


func _route_terrain_surface(mesh_instance: MeshInstance3D, surface_index: int, source: BaseMaterial3D) -> void:
	var asset_name := str(mesh_instance.get_meta("terrain_asset_name", ""))
	if asset_name.is_empty():
		var owner_path := _resolve_owner_path(mesh_instance)
		asset_name = owner_path.get_file()

	if asset_name in VEGETATION_ASSET_NAMES:
		_register_vegetation_surface(mesh_instance, surface_index, source)
		return

	# Anything else still using alpha (cutout/blend) isn't a recognized
	# terrain/vegetation asset - leave it on its original material rather
	# than guessing, since flat_terrain_*.gdshader doesn't handle ALPHA.
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return

	# No instanced-scene identity at all (e.g. procedural debug scaffolding
	# like the background plane) isn't a terrain tile in the F1 sense -
	# leave it alone rather than flagging it as an undefined tile.
	if asset_name.is_empty():
		return

	_register_terrain_surface(mesh_instance, surface_index, source, asset_name)


const FLATTENED_TEX_DIR := "res://assets/terrain/flattened/"
var _flattened_texture_cache: Dictionary = {}


func _load_flattened_texture(original_path: String) -> Texture2D:
	if original_path.is_empty():
		return null
	if _flattened_texture_cache.has(original_path):
		return _flattened_texture_cache[original_path]
	var flattened_path := FLATTENED_TEX_DIR + original_path.get_file()
	var texture: Texture2D = null
	if ResourceLoader.exists(flattened_path):
		texture = load(flattened_path) as Texture2D
	elif FileAccess.file_exists(flattened_path):
		# Editor imports normally take the ResourceLoader path above. Keep a
		# raw-image fallback for freshly generated files before the first scan.
		var image := Image.new()
		if image.load(flattened_path) == OK:
			texture = ImageTexture.create_from_image(image)
	_flattened_texture_cache[original_path] = texture
	return texture


func _register_terrain_surface(mesh_instance: MeshInstance3D, surface_index: int, source: BaseMaterial3D, asset_name: String) -> void:
	var palette_key: String = TERRAIN_ASSET_TO_PALETTE_KEY.get(asset_name, "")
	# Grass is now painted as a separate top overlay. The supporting box itself
	# is exposed soil on every face, matching the dirt bucket exactly.
	if asset_name == "terrain_grass_top_01.glb":
		palette_key = "dirt"
	var bucket_color: Color = bucket_colors.get(palette_key, UNDEFINED_TILE_COLOR) if not palette_key.is_empty() else UNDEFINED_TILE_COLOR

	if palette_key.is_empty() or not bucket_colors.has(palette_key):
		undefined_tile_count += 1
		if not _warned_asset_names.has(asset_name):
			_warned_asset_names[asset_name] = true
			push_warning(
				"[FlatValidation] undefined tile asset '%s' - add it to TERRAIN_ASSET_TO_PALETTE_KEY in flat_validation.gd and/or palette.json colors" % asset_name
			)

	var solid_material := ShaderMaterial.new()
	solid_material.shader = FLAT_TERRAIN_SOLID_SHADER
	solid_material.set_shader_parameter("base_color", bucket_color)

	var tex_material := ShaderMaterial.new()
	tex_material.shader = FLAT_TERRAIN_TEX_SHADER
	if source.albedo_texture:
		var reference_texture := _reference_terrain_texture_for(source.albedo_texture.resource_path.get_file())
		if reference_texture:
			tex_material.set_shader_parameter("albedo_tex", reference_texture)
			tex_material.set_shader_parameter("style_tint", Vector3.ONE)
		else:
			# Surfaces outside the reference set keep the brightness-flattened
			# comparison texture and the palette-specific style tint.
			var flattened := _load_flattened_texture(source.albedo_texture.resource_path)
			tex_material.set_shader_parameter("albedo_tex", flattened if flattened else source.albedo_texture)
			tex_material.set_shader_parameter("style_tint", TERRAIN_STYLE_TINTS.get(palette_key, Vector3.ONE))

	terrain_entries.append({
		"mesh_instance": mesh_instance,
		"surface_index": surface_index,
		"palette_key": palette_key,
		"solid_material": solid_material,
		"tex_material": tex_material,
	})


func _reference_terrain_texture_for(source_name: String) -> Texture2D:
	# Imported GLBs prefix extracted image names with their scene name, so
	# match the explicit surface-role token rather than requiring an exact
	# basename. Order matters: side roles must win before their parent asset.
	if "grass_side" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.dirt
	if "cliff_side_top" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.cliff_grass
	if "cliff_side" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.cliff
	if "cliff_stone" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.stone
	if "grass_top" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.dirt
	if "dirt_top" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.dirt
	if "stone_top" in source_name:
		return REFERENCE_TERRAIN_TEXTURES.stone
	return null


func _register_vegetation_surface(mesh_instance: MeshInstance3D, surface_index: int, source: BaseMaterial3D) -> void:
	var vegetation_material := ShaderMaterial.new()
	vegetation_material.shader = FLAT_VEGETATION_SHADER
	vegetation_material.set_shader_parameter("style_tint", Vector3(1.12, 1.08, 0.72))
	if source.albedo_texture:
		vegetation_material.set_shader_parameter("albedo_tex", source.albedo_texture)
	mesh_instance.set_surface_override_material(surface_index, vegetation_material)
	vegetation_materials.append(vegetation_material)


# -------------------------------------------------------- Reference dressing

func _build_reference_dressing() -> void:
	var root := Node3D.new()
	root.name = "ReferenceDressing"
	add_child(root)

	# Painted billboard props replace the earlier primitive placeholders. They
	# carry the pixel density and authored material detail seen in the target.
	_add_painted_prop(root, "cart", Vector2(4.2, 4.2), 0.92)
	_add_painted_prop(root, "crate", Vector2(5.25, 7.0), 0.78)
	_add_painted_prop(root, "crate", Vector2(6.05, 7.45), 0.66)
	_add_painted_prop(root, "barrel", Vector2(6.7, 8.25), 0.66)
	_add_painted_prop(root, "barrel", Vector2(7.18, 8.52), 0.58)
	_add_painted_prop(root, "campfire", Vector2(13.9, 4.8), 0.76)
	_add_painted_prop(root, "rocks", Vector2(3.35, 5.1), 0.76)
	_add_painted_prop(root, "rocks", Vector2(14.9, 10.4), 0.66)
	_add_painted_prop(root, "rocks", Vector2(2.8, 12.0), 0.52)
	_add_painted_prop(root, "fence", Vector2(12.7, 1.65), 0.82)

	# Tall grass is concentrated along the perimeter and cliff lips, leaving
	# the combat clearing readable. Short clumps bridge the dense and open
	# areas instead of distributing every tuft uniformly.
	for grass_data in [
		["grass_tall", Vector2(1.2, 4.4), 0.70],
		["grass_tall", Vector2(2.0, 4.2), 0.78],
		["grass_tall", Vector2(3.1, 3.2), 0.66],
		["grass_tall", Vector2(13.8, 2.5), 0.74],
		["grass_tall", Vector2(16.0, 6.1), 0.76],
		["grass_tall", Vector2(16.8, 8.7), 0.68],
		["grass_tall", Vector2(4.0, 11.8), 0.72],
		["grass_tall", Vector2(14.9, 11.7), 0.72],
		["grass_tall", Vector2(0.7, 5.0), 0.68],
		["grass_tall", Vector2(1.5, 5.2), 0.74],
		["grass_tall", Vector2(2.4, 5.0), 0.66],
		["grass_tall", Vector2(15.7, 7.0), 0.72],
		["grass_tall", Vector2(16.4, 7.4), 0.78],
		["grass_tall", Vector2(15.9, 10.5), 0.66],
		["grass_tall", Vector2(4.6, 12.4), 0.70],
		["grass_short", Vector2(0.6, 6.2), 0.62],
		["grass_short", Vector2(3.9, 5.1), 0.58],
		["grass_short", Vector2(5.0, 3.4), 0.62],
		["grass_short", Vector2(12.8, 3.3), 0.62],
		["grass_short", Vector2(15.4, 5.5), 0.58],
		["grass_short", Vector2(3.5, 10.7), 0.62],
		["grass_short", Vector2(5.5, 12.2), 0.60],
		["grass_short", Vector2(14.1, 12.2), 0.64],
	]:
		_add_painted_prop(root, grass_data[0], grass_data[1], grass_data[2], false)

	# Flat stepping stones visually stitch the water inlet back into the path.
	for stone in [
		[Vector2(3.55, 10.7), Vector2(0.34, 0.22), -12.0],
		[Vector2(4.15, 10.25), Vector2(0.29, 0.20), 18.0],
		[Vector2(4.75, 9.85), Vector2(0.25, 0.18), -4.0],
	]:
		_add_ground_patch(root, stone[0], stone[1], Color("#87908a"), stone[2])


func _surface_height_at(point: Vector2) -> float:
	if not validation_map:
		return 1.0
	var grid_position := Vector2i(floori(point.x), floori(point.y))
	var cell := validation_map.get_cell(grid_position)
	return float(cell.height) if cell else 1.0


func _flat_prop_material(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _reference_material_cache.has(key):
		return _reference_material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = FLAT_CHARACTER_SHADER
	material.set_shader_parameter("albedo_color", color)
	material.set_shader_parameter("face_top", params.face_top)
	material.set_shader_parameter("face_side_x", params.face_side_x)
	material.set_shader_parameter("face_side_z", params.face_side_z)
	material.set_shader_parameter("face_bottom", params.face_bottom)
	_reference_material_cache[key] = material
	reference_prop_materials.append(material)
	return material


func _add_painted_prop(
	parent: Node3D,
	kind: String,
	point: Vector2,
	scale_value: float,
	with_shadow := true
) -> void:
	var texture: Texture2D = PAINTED_PROP_TEXTURES.get(kind)
	if not texture:
		push_warning("Unknown painted prop kind: %s" % kind)
		return
	var sprite := Sprite3D.new()
	sprite.name = "Painted_%s" % kind
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sprite.pixel_size = 0.0100 * scale_value
	var sprite_height := float(texture.get_height()) * sprite.pixel_size
	sprite.position = Vector3(point.x, _surface_height_at(point) + sprite_height * 0.5, point.y)
	parent.add_child(sprite)
	if with_shadow:
		_add_shadow(parent, point, Vector2(0.48, 0.27) * scale_value)


func _shadow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.055, 0.065, 0.055, 0.34)
	material.roughness = 1.0
	return material


func _add_mesh_part(
	parent: Node3D,
	mesh: PrimitiveMesh,
	position: Vector3,
	color: Color,
	rotation: Vector3 = Vector3.ZERO,
	scale_value: Vector3 = Vector3.ONE
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = position
	part.rotation_degrees = rotation
	part.scale = scale_value
	part.material_override = _flat_prop_material(color)
	parent.add_child(part)
	return part


func _add_ground_patch(parent: Node3D, point: Vector2, radius: Vector2, color: Color, rotation_y: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.014
	mesh.radial_segments = 8
	_add_mesh_part(
		parent,
		mesh,
		Vector3(point.x, _surface_height_at(point) + 0.012, point.y),
		color,
		Vector3(0.0, rotation_y, 0.0),
		Vector3(radius.x * 2.0, 1.0, radius.y * 2.0)
	)


func _add_shadow(parent: Node3D, point: Vector2, radius: Vector2, rotation_y := 0.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 0.008
	mesh.radial_segments = 12
	var shadow := MeshInstance3D.new()
	shadow.mesh = mesh
	shadow.position = Vector3(point.x + 0.10, _surface_height_at(point) + 0.018, point.y + 0.08)
	shadow.rotation_degrees.y = rotation_y
	shadow.scale = Vector3(radius.x * 2.0, 1.0, radius.y * 2.0)
	shadow.material_override = _shadow_material()
	parent.add_child(shadow)


func _add_crate(parent: Node3D, point: Vector2, rotation_y: float, size: float) -> void:
	var prop := Node3D.new()
	prop.position = Vector3(point.x, _surface_height_at(point), point.y)
	prop.rotation_degrees.y = rotation_y
	parent.add_child(prop)
	_add_shadow(parent, point, Vector2(size * 0.58, size * 0.42), rotation_y)

	var body := BoxMesh.new()
	body.size = Vector3(size, size, size)
	_add_mesh_part(prop, body, Vector3(0.0, size * 0.5, 0.0), Color("#765536"))
	var slat_color := Color("#4f3928")
	var slat_thickness := size * 0.09
	for y in [size * 0.16, size * 0.84]:
		var horizontal := BoxMesh.new()
		horizontal.size = Vector3(size * 1.04, slat_thickness, slat_thickness)
		_add_mesh_part(prop, horizontal, Vector3(0.0, y, -size * 0.52), slat_color)
	for x in [-size * 0.42, size * 0.42]:
		var vertical := BoxMesh.new()
		vertical.size = Vector3(slat_thickness, size * 0.92, slat_thickness)
		_add_mesh_part(prop, vertical, Vector3(x, size * 0.5, -size * 0.52), slat_color)


func _add_barrel(parent: Node3D, point: Vector2, scale_value: float) -> void:
	var prop := Node3D.new()
	prop.position = Vector3(point.x, _surface_height_at(point), point.y)
	parent.add_child(prop)
	_add_shadow(parent, point, Vector2(0.36, 0.25) * scale_value)

	var body := CylinderMesh.new()
	body.top_radius = 0.27 * scale_value
	body.bottom_radius = 0.27 * scale_value
	body.height = 0.64 * scale_value
	body.radial_segments = 10
	_add_mesh_part(prop, body, Vector3(0.0, 0.32 * scale_value, 0.0), Color("#6c4a31"))
	for y in [0.10, 0.32, 0.54]:
		var band := CylinderMesh.new()
		band.top_radius = 0.286 * scale_value
		band.bottom_radius = 0.286 * scale_value
		band.height = 0.055 * scale_value
		band.radial_segments = 10
		_add_mesh_part(prop, band, Vector3(0.0, y * scale_value, 0.0), Color("#3f4442"))


func _add_rock_cluster(parent: Node3D, point: Vector2, scale_value: float) -> void:
	_add_shadow(parent, point, Vector2(0.62, 0.34) * scale_value, -12.0)
	var base_y := _surface_height_at(point)
	var rocks := [
		[Vector3(-0.28, 0.20, 0.02), Vector3(0.72, 0.52, 0.62), Color("#788483")],
		[Vector3(0.18, 0.26, -0.08), Vector3(0.62, 0.70, 0.55), Color("#8d9690")],
		[Vector3(0.38, 0.14, 0.16), Vector3(0.48, 0.38, 0.45), Color("#687574")],
	]
	for rock_data in rocks:
		var rock := SphereMesh.new()
		rock.radius = 0.38
		rock.height = 0.60
		rock.radial_segments = 8
		rock.rings = 4
		var offset: Vector3 = rock_data[0] * scale_value
		offset.y += base_y
		_add_mesh_part(parent, rock, Vector3(point.x, 0.0, point.y) + offset, rock_data[2], Vector3(0.0, 17.0, 8.0), rock_data[1] * scale_value)


func _add_campfire(parent: Node3D, point: Vector2) -> void:
	var base_y := _surface_height_at(point)
	_add_shadow(parent, point, Vector2(0.55, 0.34), 10.0)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var stone := SphereMesh.new()
		stone.radius = 0.13
		stone.height = 0.18
		stone.radial_segments = 6
		stone.rings = 3
		_add_mesh_part(
			parent,
			stone,
			Vector3(point.x + cos(angle) * 0.34, base_y + 0.09, point.y + sin(angle) * 0.34),
			Color("#69716d")
		)
	for angle_y in [-32.0, 32.0]:
		var log_mesh := BoxMesh.new()
		log_mesh.size = Vector3(0.72, 0.12, 0.14)
		_add_mesh_part(parent, log_mesh, Vector3(point.x, base_y + 0.13, point.y), Color("#4b3024"), Vector3(0.0, angle_y, 0.0))
	var flame_outer := SphereMesh.new()
	flame_outer.radius = 0.23
	flame_outer.height = 0.58
	flame_outer.radial_segments = 8
	flame_outer.rings = 4
	_add_mesh_part(parent, flame_outer, Vector3(point.x, base_y + 0.42, point.y), Color("#e66b2d"), Vector3.ZERO, Vector3(0.72, 1.0, 0.72))
	var flame_inner := SphereMesh.new()
	flame_inner.radius = 0.13
	flame_inner.height = 0.36
	flame_inner.radial_segments = 8
	flame_inner.rings = 4
	_add_mesh_part(parent, flame_inner, Vector3(point.x - 0.03, base_y + 0.40, point.y - 0.02), Color("#f3c15b"), Vector3.ZERO, Vector3(0.75, 1.0, 0.75))


func _add_fence_segment(parent: Node3D, point: Vector2, rotation_y: float) -> void:
	var prop := Node3D.new()
	prop.position = Vector3(point.x, _surface_height_at(point), point.y)
	prop.rotation_degrees.y = rotation_y
	parent.add_child(prop)
	_add_shadow(parent, point, Vector2(1.35, 0.22), rotation_y)
	for x in [-0.9, 0.0, 0.9]:
		var post := BoxMesh.new()
		post.size = Vector3(0.14, 0.92, 0.14)
		_add_mesh_part(prop, post, Vector3(x, 0.46, 0.0), Color("#59412d"))
	for y in [0.32, 0.68]:
		var rail := BoxMesh.new()
		rail.size = Vector3(2.0, 0.13, 0.12)
		_add_mesh_part(prop, rail, Vector3(0.0, y, -0.02), Color("#765536"), Vector3(0.0, 0.0, -3.0))


# ---------------------------------------------------------------- Characters

func _build_characters() -> void:
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	_spawn_character(units, "vain_validation", Vector2i(9, 7), 1)


func _add_painted_character(parent: Node3D, kind: String, point: Vector2, scale_value: float) -> void:
	var texture: Texture2D = PAINTED_CHARACTER_TEXTURES.get(kind)
	if not texture:
		push_warning("Unknown painted character kind: %s" % kind)
		return
	var sprite := Sprite3D.new()
	sprite.name = "PaintedCharacter_%s" % kind
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sprite.pixel_size = 0.0095 * scale_value
	var sprite_height := float(texture.get_height()) * sprite.pixel_size
	sprite.position = Vector3(point.x, _surface_height_at(point) + sprite_height * 0.5, point.y)
	parent.add_child(sprite)
	_add_shadow(parent, point, Vector2(0.34, 0.20) * scale_value)


func _spawn_character(parent: Node3D, id: String, grid_pos: Vector2i, height: int) -> void:
	var unit := BattleUnit.new()
	unit.configure(id, id, grid_pos, "player")
	# Match UnitManager's actual Vain setup so the validation result reflects
	# the same model scale, ground offset, facing correction and flat shader.
	unit.setup_visual(CHARACTER_MODEL, 1.02, -0.045, -90.0, true)
	unit.attach_face_texture(CHARACTER_FACE_TEXTURE)
	parent.add_child(unit)
	unit.position = Vector3(grid_pos.x + 0.5, float(height), grid_pos.y + 0.5)
	# Face north, toward the validation camera, so the face and torso materials
	# can be judged instead of presenting the model's back.
	unit.face_toward(grid_pos + Vector2i(0, -1))
	# The validation vignette evaluates the map art, so battle-only overlays
	# must not cover character silhouettes in presentation captures.
	if unit.status_bars:
		unit.status_bars.visible = false
	if unit.direction_marker:
		unit.direction_marker.visible = false
	_collect_character_materials(unit)


func _collect_character_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for i in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_surface_override_material(i)
				if material is ShaderMaterial and (material as ShaderMaterial).shader == FLAT_CHARACTER_SHADER:
					character_materials.append(material)
	for child in node.get_children():
		_collect_character_materials(child)


# ----------------------------------------------------------------- Params

func _apply_terrain_mode(mode: String) -> void:
	terrain_mode = mode
	for entry in terrain_entries:
		var material: ShaderMaterial = entry.solid_material if mode == "A" else entry.tex_material
		(entry.mesh_instance as MeshInstance3D).set_surface_override_material(entry.surface_index, material)
	for entry in transition_entries:
		(entry.mesh_instance as MeshInstance3D).visible = mode == "B"
	_push_terrain_params()
	_update_status()


func _push_terrain_params() -> void:
	for entry in terrain_entries:
		var surface_hue_jitter := _hue_jitter_for_palette(entry.get("palette_key", ""))
		for material in [entry.solid_material, entry.tex_material]:
			material.set_shader_parameter("face_top", params.face_top)
			material.set_shader_parameter("face_side_x", params.face_side_x)
			material.set_shader_parameter("face_side_z", params.face_side_z)
			material.set_shader_parameter("face_bottom", params.face_bottom)
			material.set_shader_parameter("tile_size", params.tile_size)
			material.set_shader_parameter("hue_jitter", surface_hue_jitter)
			material.set_shader_parameter("sat_jitter", params.sat_jitter)
			material.set_shader_parameter("val_jitter", params.val_jitter)
			material.set_shader_parameter("strata_enabled", params.strata_enabled)
			material.set_shader_parameter("strata_height", params.strata_height)
			material.set_shader_parameter("strata_hue_jitter", params.strata_hue_jitter)
			material.set_shader_parameter("strata_val_jitter", params.strata_val_jitter)
	for entry in transition_entries:
		var material: ShaderMaterial = entry.material
		material.set_shader_parameter("face_top", params.face_top)
		material.set_shader_parameter("tile_size", params.tile_size)
		material.set_shader_parameter("hue_jitter", params.grass_hue_jitter)
		material.set_shader_parameter("sat_jitter", params.sat_jitter)
		material.set_shader_parameter("val_jitter", params.val_jitter)


func _hue_jitter_for_palette(palette_key: String) -> float:
	match palette_key:
		"grass":
			return params.grass_hue_jitter
		"dirt":
			return params.dirt_hue_jitter
		_:
			return params.hue_jitter


func _push_character_params() -> void:
	for material in character_materials:
		material.set_shader_parameter("face_top", params.face_top * params.character_face_top_boost)
		material.set_shader_parameter("face_side_x", params.face_side_x)
		material.set_shader_parameter("face_side_z", params.face_side_z)
		material.set_shader_parameter("face_bottom", params.face_bottom)
	for material in reference_prop_materials:
		material.set_shader_parameter("face_top", params.face_top)
		material.set_shader_parameter("face_side_x", params.face_side_x)
		material.set_shader_parameter("face_side_z", params.face_side_z)
		material.set_shader_parameter("face_bottom", params.face_bottom)


func _push_vegetation_params() -> void:
	# flat_vegetation.gdshader never calls face_factor()/apply_strata(), so
	# only face_top/tile_size/hue_jitter/sat_jitter/val_jitter are read.
	for material in vegetation_materials:
		material.set_shader_parameter("face_top", params.face_top)
		material.set_shader_parameter("tile_size", params.tile_size)
		material.set_shader_parameter("hue_jitter", params.grass_hue_jitter)
		material.set_shader_parameter("sat_jitter", params.sat_jitter)
		material.set_shader_parameter("val_jitter", params.val_jitter)


func _push_environment_params() -> void:
	environment_resource.background_color = params.background_color
	environment_resource.fog_density = params.fog_density
	environment_resource.fog_light_color = params.fog_color


# ---------------------------------------------------------------------- UI

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	var info := Label.new()
	info.text = "F1: Plan A  F2: Plan B  F3: capture  F4: presentation  Tab: free orbit  Ctrl+S: export"
	info.add_theme_color_override("font_color", Color.WHITE)
	info.position = Vector2(12, 8)
	ui_layer.add_child(info)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color.WHITE)
	status_label.position = Vector2(12, 28)
	ui_layer.add_child(status_label)

	# fix F1-4: always-visible counter. Per phase17-step1-fix.md, A/B judgment
	# must not proceed while this is > 0 - see flat_shading_spec.md.
	undefined_label = Label.new()
	undefined_label.position = Vector2(12, 48)
	ui_layer.add_child(undefined_label)
	_update_undefined_label()

	var panel := PanelContainer.new()
	panel.name = "SidePanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-320, 8)
	panel.custom_minimum_size = Vector2(300, 0)
	ui_layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 640)
	panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(280, 0)
	scroll.add_child(list)

	_add_float_slider(list, "face_top", 0.0, 1.5, 0.01, _on_terrain_param_changed)
	_add_float_slider(list, "face_side_x", 0.0, 1.5, 0.01, _on_terrain_param_changed)
	_add_float_slider(list, "face_side_z", 0.0, 1.5, 0.01, _on_terrain_param_changed)
	_add_float_slider(list, "face_bottom", 0.0, 1.5, 0.01, _on_terrain_param_changed)
	_add_float_slider(list, "grass_hue_jitter", 0.0, 0.15, 0.005, _on_terrain_param_changed)
	_add_float_slider(list, "dirt_hue_jitter", 0.0, 0.15, 0.005, _on_terrain_param_changed)
	_add_float_slider(list, "sat_jitter", 0.0, 0.3, 0.005, _on_terrain_param_changed)
	_add_float_slider(list, "val_jitter", 0.0, 0.1, 0.002, _on_terrain_param_changed)
	_add_float_slider(list, "tile_size", 0.1, 4.0, 0.05, _on_terrain_param_changed)
	_add_bool_toggle(list, "strata_enabled")
	_add_float_slider(list, "strata_height", 0.1, 4.0, 0.05, _on_terrain_param_changed)
	_add_float_slider(list, "strata_hue_jitter", 0.0, 0.15, 0.005, _on_terrain_param_changed)
	_add_float_slider(list, "strata_val_jitter", 0.0, 0.1, 0.002, _on_terrain_param_changed)
	_add_float_slider(list, "character_face_top_boost", 0.8, 1.5, 0.01, _on_character_param_changed)
	_add_color_picker(list, "background_color")
	_add_float_slider(list, "fog_density", 0.0, 0.03, 0.001, _on_environment_param_changed)
	_add_color_picker(list, "fog_color")


func _add_float_slider(parent: VBoxContainer, param_name: String, min_value: float, max_value: float, step: float, callback: Callable) -> void:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.name = "Label"
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = params[param_name]
	slider.value_changed.connect(func(value: float) -> void:
		params[param_name] = value
		label.text = "%s: %s" % [param_name, snappedf(value, 0.001)]
		callback.call()
	)
	row.add_child(slider)
	parent.add_child(row)
	sliders[param_name] = slider
	label.text = "%s: %s" % [param_name, params[param_name]]


func _add_bool_toggle(parent: VBoxContainer, param_name: String) -> void:
	var check := CheckBox.new()
	check.text = param_name
	check.add_theme_color_override("font_color", Color.WHITE)
	check.button_pressed = params[param_name]
	check.toggled.connect(func(pressed: bool) -> void:
		params[param_name] = pressed
		_on_terrain_param_changed()
	)
	parent.add_child(check)
	sliders[param_name] = check


func _add_color_picker(parent: VBoxContainer, param_name: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = param_name
	label.add_theme_color_override("font_color", Color.WHITE)
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = params[param_name]
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(120, 24)
	picker.color_changed.connect(func(color: Color) -> void:
		params[param_name] = color
		_on_environment_param_changed()
	)
	row.add_child(picker)
	parent.add_child(row)
	sliders[param_name] = picker


func _on_terrain_param_changed() -> void:
	_push_terrain_params()
	_push_vegetation_params()


func _on_character_param_changed() -> void:
	_push_character_params()


func _on_environment_param_changed() -> void:
	_push_environment_params()


func _update_status() -> void:
	if status_label:
		status_label.text = "terrain plan: %s   free orbit: %s   presentation: %s" % [terrain_mode, free_orbit, presentation_mode]


func _toggle_presentation_mode() -> void:
	presentation_mode = not presentation_mode
	if ui_layer:
		ui_layer.visible = not presentation_mode
	_update_status()


func _update_undefined_label() -> void:
	if not undefined_label:
		return
	undefined_label.text = "未定義タイル: %d件" % undefined_tile_count
	undefined_label.add_theme_color_override(
		"font_color", Color.RED if undefined_tile_count > 0 else Color.WHITE
	)


# ------------------------------------------------------------------- Export

func _export_preset() -> void:
	var exported := {
		"terrain_plan": terrain_mode,
		"face_top": params.face_top,
		"face_side_x": params.face_side_x,
		"face_side_z": params.face_side_z,
		"face_bottom": params.face_bottom,
		"tile_size": params.tile_size,
		"hue_jitter": params.hue_jitter,
		"grass_hue_jitter": params.grass_hue_jitter,
		"dirt_hue_jitter": params.dirt_hue_jitter,
		"sat_jitter": params.sat_jitter,
		"val_jitter": params.val_jitter,
		"strata_enabled": params.strata_enabled,
		"strata_height": params.strata_height,
		"strata_hue_jitter": params.strata_hue_jitter,
		"strata_val_jitter": params.strata_val_jitter,
		"character_face_top_boost": params.character_face_top_boost,
		"background_color": "#" + params.background_color.to_html(false),
		"fog_density": params.fog_density,
		"fog_color": "#" + params.fog_color.to_html(false),
	}
	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if not file:
		push_warning("Cannot write %s (error %d)" % [EXPORT_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(exported, "  "))
	file.close()
	print("[FlatValidation] exported ", ProjectSettings.globalize_path(EXPORT_PATH))
	if status_label:
		status_label.text = "exported %s" % EXPORT_PATH


func _capture_ab_pair() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/dev/assets"))
	var previous_mode := terrain_mode
	_apply_terrain_mode("A")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_screenshot(SCREENSHOT_SOLID_PATH)
	_apply_terrain_mode("B")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_screenshot(SCREENSHOT_TEX_PATH)
	_apply_terrain_mode(previous_mode)
	print("[FlatValidation] captured A/B pair")


func _save_screenshot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)


func _capture_reference_preview() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/dev/assets"))
	if ui_layer:
		ui_layer.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_screenshot(REFERENCE_PREVIEW_PATH)
	print("[FlatValidation] captured ", ProjectSettings.globalize_path(REFERENCE_PREVIEW_PATH))
	get_tree().quit()


# ------------------------------------------------------------------- Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_S and event.ctrl_pressed:
			_export_preset()
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_F1: _apply_terrain_mode("A")
			KEY_F2: _apply_terrain_mode("B")
			KEY_F3: _capture_ab_pair()
			KEY_F4: _toggle_presentation_mode()
			KEY_TAB:
				free_orbit = not free_orbit
				_update_status()
			_: return
		get_viewport().set_input_as_handled()
		return

	if not free_orbit:
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		camera_controller.orbit_from_mouse(event.relative)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: camera_controller.zoom_camera(1.5)
			MOUSE_BUTTON_WHEEL_DOWN: camera_controller.zoom_camera(-1.5)
			_: return
		get_viewport().set_input_as_handled()
