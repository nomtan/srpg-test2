extends RefCounted
## Phase 2 vegetation assets for JRPGWorldSample2: Blender-built GLBs
## (tools/vegetation/build_vegetation_assets.py) placed through MultiMesh with
## hierarchical LOD. Blender owns the shapes, LOD meshes and material slots; this side
## owns the shared runtime materials, LOD distances and instancing.
const TRUNK_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_trunk.tres")
const FOLIAGE_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_foliage.tres")
const LEAF_CARD_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_leaf_cards.tres")
const NEEDLE_CARD_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_needle_cards.tres")
const BLOSSOM_CARD_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_blossom_cards.tres")
const GRASS_MATERIAL = preload("res://assets/environment/vegetation/materials/grass.tres")
const FLOWER_MATERIAL = preload("res://assets/environment/vegetation/materials/flower.tres")
## The procedural grass carpet's material (open_field_meadow.gd).
const MEADOW_MATERIAL = preload("res://assets/environment/vegetation/materials/meadow_grass.tres")
const TOON_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_toon.tres")
const SEED_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_seed.tres")
const SEED_BARK_MATERIAL = preload("res://assets/environment/vegetation/materials/tree_seed_bark.tres")
## Seed conifers share the seed-tree look but keep their needles through the seasons.
static var seed_conifer_material: ShaderMaterial = _evergreen(SEED_MATERIAL)
const ToonTrees = preload("res://scripts/world_jrpg/open_field_toon_trees.gd")
const ROOT := "res://assets/environment/vegetation/"
const SCENES := {
	"broadleaf_a": ROOT + "trees/broadleaf/broadleaf_a.glb",
	"broadleaf_b": ROOT + "trees/broadleaf/broadleaf_b.glb",
	"broadleaf_c": ROOT + "trees/broadleaf/broadleaf_c.glb",
	"oak_a": ROOT + "trees/oak/oak_a.glb",
	"oak_b": ROOT + "trees/oak/oak_b.glb",
	"conifer_a": ROOT + "trees/conifer/conifer_a.glb",
	"conifer_b": ROOT + "trees/conifer/conifer_b.glb",
	"card_round": ROOT + "trees/card/card_round.glb",
	"card_tall": ROOT + "trees/card/card_tall.glb",
	"card_umbrella": ROOT + "trees/card/card_umbrella.glb",
	"card_oak": ROOT + "trees/card/card_oak.glb",
	"card_lean": ROOT + "trees/card/card_lean.glb",
	"card_spruce": ROOT + "trees/card/card_spruce.glb",
	"card_fir": ROOT + "trees/card/card_fir.glb",
	"card_blossom": ROOT + "trees/card/card_blossom.glb",
	"seed_tree_a": ROOT + "trees/seed/seed_tree_a.glb",
	"seed_tree_b": ROOT + "trees/seed/seed_tree_b.glb",
	"seed_tree_c": ROOT + "trees/seed/seed_tree_c.glb",
	"seed_tree_d": ROOT + "trees/seed/seed_tree_d.glb",
	"seed_tree_e": ROOT + "trees/seed/seed_tree_e.glb",
	"seed_tree_f": ROOT + "trees/seed/seed_tree_f.glb",
	"seed_tree_g": ROOT + "trees/seed/seed_tree_g.glb",
	"seed_tree_h": ROOT + "trees/seed/seed_tree_h.glb",
	"seed_tree_i": ROOT + "trees/seed/seed_tree_i.glb",
	"seed_tree_j": ROOT + "trees/seed/seed_tree_j.glb",
	"seed_tree_k": ROOT + "trees/seed/seed_tree_k.glb",
	"seed_tree_l": ROOT + "trees/seed/seed_tree_l.glb",
	"seed_conifer_a": ROOT + "trees/seed/seed_conifer_a.glb",
	"seed_conifer_b": ROOT + "trees/seed/seed_conifer_b.glb",
	"seed_conifer_c": ROOT + "trees/seed/seed_conifer_c.glb",
	"seed_conifer_d": ROOT + "trees/seed/seed_conifer_d.glb",
	"bush_a": ROOT + "bushes/bush_a.glb",
	"bush_b": ROOT + "bushes/bush_b.glb",
	"bush_c": ROOT + "bushes/bush_c.glb",
	"grass_short": ROOT + "grass/grass_short.glb",
	"grass_normal": ROOT + "grass/grass_normal.glb",
	"grass_tall": ROOT + "grass/grass_tall.glb",
	"grass_wild": ROOT + "grass/grass_wild.glb",
	"flower_grass_a": ROOT + "flowers/flower_grass_a.glb",
	"flower_grass_b": ROOT + "flowers/flower_grass_b.glb",
}
const TREES := ["broadleaf_a", "broadleaf_b", "broadleaf_c", "oak_a", "oak_b", "conifer_a", "conifer_b"]
## Illustration-style trees: leaf cards shaded with the crown's proxy normals.
const CARD_TREES := ["card_round", "card_tall", "card_umbrella", "card_oak", "card_lean", "card_spruce", "card_fir", "card_blossom"]
## Which leaf-card tree stands in for each solid tree on the map ("blossom" is the
## procedural pink accent tree).
const CARD_SWAP := {"broadleaf_a": "card_round", "broadleaf_b": "card_tall", "broadleaf_c": "card_lean",
	"oak_a": "card_oak", "oak_b": "card_umbrella", "conifer_a": "card_spruce", "conifer_b": "card_fir",
	"blossom": "card_blossom"}
## Low-poly anime trees built in code (open_field_toon_trees.gd): opaque, no wind, three LODs.
const TOON_TREES := ["toon_round", "toon_tall", "toon_umbrella", "toon_oak", "toon_lean", "toon_spruce", "toon_fir", "toon_blossom"]
const TOON_SWAP := {"broadleaf_a": "toon_round", "broadleaf_b": "toon_tall", "broadleaf_c": "toon_lean",
	"oak_a": "toon_oak", "oak_b": "toon_umbrella", "conifer_a": "toon_spruce", "conifer_b": "toon_fir",
	"blossom": "toon_blossom"}
## Seed-driven illustration broadleaves (tools/vegetation/build_seed_trees.py): billboard leaf
## cards over a lump core, softly lit with the crown's proxy normals
## (open_field_seed_tree.gdshader); the trunk uses the toon shader. Conifers and blossom keep
## their toon / card stand-ins. Twelve variants, each with its own crown and branch structure
## (k and l on conical trunks that widen down to the ground), picked at random per tree.
const SEED_TREES := ["seed_tree_a", "seed_tree_b", "seed_tree_c", "seed_tree_d", "seed_tree_e",
	"seed_tree_f", "seed_tree_g", "seed_tree_h", "seed_tree_i", "seed_tree_j", "seed_tree_k", "seed_tree_l"]
## The Phase 2 tree kinds the seed trees stand in for.
const SEED_REPLACES := ["broadleaf_a", "broadleaf_b", "broadleaf_c", "oak_a", "oak_b"]
## Seed-driven illustration conifers (narrow, pointed leaf-card crowns on a straight leader),
## standing in for the conifer kinds.
const SEED_CONIFERS := ["seed_conifer_a", "seed_conifer_b", "seed_conifer_c", "seed_conifer_d"]
const SEED_CONIFER_REPLACES := ["conifer_a", "conifer_b"]
const BUSHES := ["bush_a", "bush_b", "bush_c"]
const GRASSES := ["grass_short", "grass_normal", "grass_tall", "grass_wild"]
const FLOWERS := ["flower_grass_a", "flower_grass_b"]
## Blender material slot name -> shared runtime material.
const SLOT_MATERIALS := {"Trunk": TRUNK_MATERIAL, "Leaves": FOLIAGE_MATERIAL, "LeafCards": LEAF_CARD_MATERIAL,
	"LeafCore": LEAF_CARD_MATERIAL, "NeedleCards": NEEDLE_CARD_MATERIAL, "NeedleCore": NEEDLE_CARD_MATERIAL,
	"BlossomCards": BLOSSOM_CARD_MATERIAL, "BlossomCore": BLOSSOM_CARD_MATERIAL, "Grass": GRASS_MATERIAL, "Flower": FLOWER_MATERIAL, "Toon": TOON_MATERIAL,
	"SeedCards": SEED_MATERIAL, "SeedCore": SEED_MATERIAL, "SeedBark": SEED_BARK_MATERIAL}
## Tree LOD bands, measured by Godot from the camera to each MultiMesh's AABB center.
## LOD0/LOD1 live in FINE_CHUNK cells under a COARSE_CHUNK LOD2/LOD3 cell (see
## add_tree_chunk), so a tree's own distance stays within ~11 m / ~23 m of its cell's.
const LOD1_FROM := 34.0
const LOD2_FROM := 80.0
const LOD3_FROM := 160.0
const LOD_MARGIN := 4.0
## The seed trees are the hero broadleaves: they keep full detail further out before the
## (thinned, same-silhouette) LOD1 / LOD2 take over.
const SEED_LOD1_FROM := 70.0
const SEED_LOD2_FROM := 150.0
## The seed GLBs ship one mesh at every LOD (the look is tuned on LOD0), so split_cards thins
## the distance LODs here: per LOD, the share of bark triangles, core triangles and leaf cards
## kept. Bark is mostly twigs hidden in the crown and goes thinnest tube first; kept cards
## grow to hold the leaf cover.
const SEED_LOD_KEEP := [[1.0, 1.0, 1.0], [0.6, 1.0, 1.0], [0.35, 0.5, 0.5]]
## The sun's shadow distance (world.gd); LODs that begin past it never cast.
const SHADOW_REACH := 120.0
const FINE_CHUNK := 16.0
const COARSE_CHUNK := 32.0
## Seed trees switch to LOD1 far out (SEED_LOD1_FROM), so their near cells can be a whole
## coarse cell: a cell holds only a few trees of each of the sixteen kinds, and every cell
## and kind costs a draw per surface (and per shadow split).
const SEED_FINE_CHUNK := 32.0
## ...and their LOD2 cells span 64 m: from SEED_LOD2_FROM out, a tree's own distance stays
## within ~45 m of its cell's.
const SEED_COARSE_CHUNK := 64.0
## Trees keep shadows through LOD2 because the sun's shadow reaches 120 m; LOD3 is past it.
const LOD_SHADOWS := [true, true, true, false]
## Bushes: single-level cells; past BUSH_LOD2_END the ground and trees carry the view.
const BUSH_LOD1_FROM := 26.0
const BUSH_LOD2_FROM := 60.0
const BUSH_LOD2_END := 120.0
const BUSH_SHADOWS := [true, false, false]
## Grass: every clump near the camera, half of them (slightly larger) in the mid band.
const GRASS_NEAR := 36.0
const GRASS_FAR := 70.0
## Billboard leaf cards reach this far (m, at scale 1) outside their mesh's AABB.
const CARD_CULL_MARGIN := 2.5
static var meshes: Dictionary = {}
## Leaf-card trees: per LOD, the "<Kind>Cards" surface index (-1 when that LOD has none).
static var card_surfaces: Dictionary = {}
## Leaf-card trees: per LOD, [body mesh (trunk + cores), cards mesh or null].
static var card_parts: Dictionary = {}

## True for every asset lod_meshes can build (Blender GLBs and the procedural toon trees).
static func has_asset(asset: String) -> bool:
	return SCENES.has(asset) or asset in TOON_TREES

## Trees whose leaf cards are split off into a non-casting MultiMesh (split_cards).
static func _has_cards(asset: String) -> bool:
	return asset in CARD_TREES or _is_seed(asset)

## Seed-driven illustration trees (broadleaves and conifers).
static func _is_seed(asset: String) -> bool:
	return asset in SEED_TREES or asset in SEED_CONIFERS

static func _evergreen(source: ShaderMaterial) -> ShaderMaterial:
	var material: ShaderMaterial = source.duplicate()
	material.set_shader_parameter("evergreen", 1.0)
	return material

## LOD meshes of one asset, finest first, with the shared materials assigned.
static func lod_meshes(asset: String) -> Array[Mesh]:
	if not meshes.has(asset) and asset in TOON_TREES:
		meshes[asset] = ToonTrees.build(asset, TOON_MATERIAL)
	if not meshes.has(asset):
		var list: Array[Mesh] = []
		var scene := (load(SCENES[asset]) as PackedScene).instantiate()
		var by_name := {}
		for node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			by_name[str(node.name)] = node.mesh
		if by_name.has(asset):
			list.append(by_name[asset])
		var level := 0
		while by_name.has("%s_LOD%d" % [asset, level]):
			list.append(by_name["%s_LOD%d" % [asset, level]])
			level += 1
		scene.free()
		var cards: Array[int] = []
		for mesh in list:
			cards.append(-1)
			for surface in mesh.get_surface_count():
				var slot := mesh.surface_get_material(surface)
				var key := slot.resource_name if slot else ""
				if key.ends_with("Cards"): cards[-1] = surface
				assert(SLOT_MATERIALS.has(key), "Unknown vegetation material slot '%s' in %s" % [key, asset])
				var material: Material = SLOT_MATERIALS[key]
				if material == SEED_MATERIAL and asset in SEED_CONIFERS: material = seed_conifer_material
				mesh.surface_set_material(surface, material)
		meshes[asset] = list
		if _has_cards(asset): card_surfaces[asset] = cards
	return meshes[asset]

## A leaf-card tree LOD split into the shadow-casting body (trunk, limbs, crown cores)
## and the cards, which are drawn without casting: alpha-cut cards in the shadow map
## shimmer on the crown and the ground whenever the camera or the wind moves.
static func split_cards(asset: String, level: int) -> Array:
	if not card_parts.has(asset):
		var parts: Array = []
		var lods := lod_meshes(asset)
		for l in lods.size():
			var index: int = card_surfaces[asset][l]
			var keep: Array = SEED_LOD_KEEP[mini(l, SEED_LOD_KEEP.size() - 1)] if _is_seed(asset) else [1.0, 1.0, 1.0]
			# Seed LOD2 starts around the shadow reach and never casts (add_tree_chunk), so
			# the crown core joins its cards (same material): one draw fewer per cell and kind.
			var merge_core := _is_seed(asset) and l == 2 and SEED_LOD2_FROM >= SHADOW_REACH
			var body := ArrayMesh.new()
			var cards: ArrayMesh = null
			var crown: Array = []
			var crown_material: Material = null
			for surface in lods[l].get_surface_count():
				var arrays := lods[l].surface_get_arrays(surface)
				var material := lods[l].surface_get_material(surface)
				if surface == index or (merge_core and material != SEED_BARK_MATERIAL):
					arrays = _thin_cards(arrays, keep[2]) if surface == index else _decimate(arrays, keep[1])
					crown = arrays if crown.is_empty() else _merge(crown, arrays)
					crown_material = material
					continue
				arrays = _thin_bark(arrays, keep[0]) if material == SEED_BARK_MATERIAL else _decimate(arrays, keep[1])
				body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				body.surface_set_material(body.get_surface_count() - 1, material)
			if not crown.is_empty():
				cards = ArrayMesh.new()
				cards.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, crown)
				cards.surface_set_material(0, crown_material)
			parts.append([body, cards])
		card_parts[asset] = parts
	return card_parts[asset][level]

## Two surfaces' arrays (same vertex format) as one.
static func _merge(a: Array, b: Array) -> Array:
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	var offset := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for k in Mesh.ARRAY_MAX:
		assert((a[k] == null) == (b[k] == null), "Seed crown surfaces differ in vertex format")
		if a[k] == null: continue
		if k == Mesh.ARRAY_INDEX:
			var indices: PackedInt32Array = (a[k] as PackedInt32Array).duplicate()
			for i: int in b[k]: indices.append(i + offset)
			result[k] = indices
		else:
			result[k] = a[k] + b[k]
	return result

## `arrays` simplified to about `keep` of its triangles (Godot's mesh LOD generator; the
## vertices stay, only the index list shrinks). Stops at the coarsest level it can reach.
static func _decimate(arrays: Array, keep: float) -> Array:
	if keep >= 1.0: return arrays
	var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var count := importer.get_surface_lod_count(0)
	if count == 0: return arrays
	var indices := importer.get_surface_lod_indices(0, count - 1)
	for i in count:
		indices = importer.get_surface_lod_indices(0, i)
		if indices.size() <= source.size() * keep: break
	var result := arrays.duplicate()
	result[Mesh.ARRAY_INDEX] = indices
	return result

## Keeps the thickest bark tubes (trunk, then limbs, then twigs) up to about `keep` of the
## triangles. A tube is one connected piece of the mesh and goes whole, so a trunk or limb
## never breaks up the way a mesh simplifier thins it. Its girth is its widest ring: the
## vertices sharing one UV.y (the bark texture runs along the tube).
static func _thin_bark(arrays: Array, keep: float) -> Array:
	if keep >= 1.0: return arrays
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var root := PackedInt32Array()
	root.resize(vertices.size())
	for i in root.size(): root[i] = i
	for t in range(0, indices.size(), 3):
		for k in [1, 2]:
			var a := _find(root, indices[t])
			var b := _find(root, indices[t + k])
			if a != b: root[b] = a
	var rings := {}
	for i in vertices.size():
		var key := Vector2i(_find(root, i), roundi(uvs[i].y * 4096.0))
		if not rings.has(key): rings[key] = []
		rings[key].append(vertices[i])
	var girth := {}
	for key: Vector2i in rings:
		var ring: Array = rings[key]
		var center := Vector3.ZERO
		for v: Vector3 in ring: center += v
		center /= ring.size()
		var radius := 0.0
		for v: Vector3 in ring: radius = maxf(radius, v.distance_to(center))
		girth[key.x] = maxf(girth.get(key.x, 0.0), radius)
	var triangles := {}
	for t in range(0, indices.size(), 3):
		var tube := _find(root, indices[t])
		triangles[tube] = triangles.get(tube, 0) + 1
	var tubes := girth.keys()
	tubes.sort_custom(func(a: int, b: int) -> bool: return girth[a] > girth[b])
	var kept := {}
	var budget := indices.size() / 3.0 * keep
	for tube: int in tubes:
		if budget <= 0.0: break
		kept[tube] = true
		budget -= triangles.get(tube, 0)
	var result_indices := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		if kept.has(_find(root, indices[t])): result_indices.append_array(indices.slice(t, t + 3))
	var result := arrays.duplicate()
	result[Mesh.ARRAY_INDEX] = result_indices
	return result

static func _find(root: PackedInt32Array, i: int) -> int:
	while root[i] != i:
		root[i] = root[root[i]]
		i = root[i]
	return i

## Keeps about `keep` of the leaf cards, each grown by 1 / sqrt(keep) so the crown keeps its
## cover. All four corners of a card sit at its center, so hashing a triangle's first corner
## keeps or drops both triangles of a card together.
static func _thin_cards(arrays: Array, keep: float) -> Array:
	if keep >= 1.0: return arrays
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var kept := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		if posmod(hash(vertices[indices[t]]), 1024) < keep * 1024.0:
			kept.append_array(indices.slice(t, t + 3))
	var offsets: PackedVector2Array = (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate()
	var grow := 1.0 / sqrt(keep)
	for i in offsets.size(): offsets[i] *= grow
	var result := arrays.duplicate()
	result[Mesh.ARRAY_INDEX] = kept
	result[Mesh.ARRAY_TEX_UV2] = offsets
	return result

static func shader_materials() -> Array[ShaderMaterial]:
	return [TOON_MATERIAL, SEED_MATERIAL, seed_conifer_material, SEED_BARK_MATERIAL, TRUNK_MATERIAL, FOLIAGE_MATERIAL, LEAF_CARD_MATERIAL, NEEDLE_CARD_MATERIAL, BLOSSOM_CARD_MATERIAL, GRASS_MATERIAL, FLOWER_MATERIAL, MEADOW_MATERIAL]

## The card (and core) material of a leaf-card tree: leaf, needle or blossom palette.
static func card_material(asset: String) -> Material:
	var lods := lod_meshes(asset)
	return lods[0].surface_get_material(card_surfaces[asset][0])

static func triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total

## `custom` (optional, one Color per transform) is the shader's INSTANCE_CUSTOM.
static func _instances(parent: Node3D, mesh: Mesh, transforms: Array, node_name: String, shadows: bool, custom: Array = []) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = not custom.is_empty()
	# The Compatibility renderer feeds custom data into COLOR unless the per-instance
	# color slot is in use too; a white instance color leaves the vertex data intact.
	multi.use_colors = multi.use_custom_data
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
	for i in custom.size():
		multi.set_instance_custom_data(i, custom[i])
		multi.set_instance_color(i, Color.WHITE)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	if not shadows: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

## One tree LOD over `transforms`; leaf-card trees add their cards as a second,
## non-casting MultiMesh. The first entry is the body.
static func _tree_instances(parent: Node3D, asset: String, level: int, transforms: Array, node_name: String, shadows: bool) -> Array[GeometryInstance3D]:
	var list: Array[GeometryInstance3D] = []
	if not _has_cards(asset):
		list.append(_instances(parent, lod_meshes(asset)[level], transforms, node_name, shadows))
		return list
	var parts := split_cards(asset, level)
	list.append(_instances(parent, parts[0], transforms, node_name, shadows))
	if parts[1] != null:
		var cards := _instances(parent, parts[1], transforms, node_name + "_cards", false)
		# The shader spreads each billboard card around its center, past the mesh AABB.
		cards.extra_cull_margin = CARD_CULL_MARGIN
		list.append(cards)
	return list

static func _range(instance: GeometryInstance3D, begin: float, end: float) -> void:
	instance.visibility_range_begin = begin
	instance.visibility_range_end = end
	instance.visibility_range_begin_margin = LOD_MARGIN if begin > 0.0 else 0.0
	instance.visibility_range_end_margin = LOD_MARGIN if end > 0.0 else 0.0

## The COARSE_CHUNK grid cell whose chunk holds `asset` at `p`: seed trees snap to their
## SEED_COARSE_CHUNK cells.
static func chunk_key(asset: String, p: Vector2) -> Vector2i:
	var span := int(SEED_COARSE_CHUNK / COARSE_CHUNK) if _is_seed(asset) else 1
	return Vector2i(floori(p.x / (COARSE_CHUNK * span)) * span, floori(p.y / (COARSE_CHUNK * span)) * span)

## Instances one tree asset over a COARSE_CHUNK cell with hierarchical LOD: the cell's
## LOD2 MultiMesh is the visibility parent of FINE_CHUNK LOD0/LOD1 MultiMeshes, which
## only draw once the camera is inside LOD2's begin distance. No tree is ever drawn
## twice or skipped across a band, and far cells cost one draw per band.
static func add_tree_chunk(parent: Node3D, asset: String, transforms: Array) -> void:
	if transforms.is_empty(): return
	var lods := lod_meshes(asset)
	var lod1_from := SEED_LOD1_FROM if _is_seed(asset) else LOD1_FROM
	var lod2_from := SEED_LOD2_FROM if _is_seed(asset) else LOD2_FROM
	var far_parts := _tree_instances(parent, asset, 2, transforms, "%s_LOD2" % asset, LOD_SHADOWS[2] and lod2_from < SHADOW_REACH)
	for part in far_parts: _range(part, lod2_from, LOD3_FROM if lods.size() > 3 else 0.0)
	var far := far_parts[0]
	if lods.size() > 3:
		for part in _tree_instances(parent, asset, 3, transforms, "%s_LOD3" % asset, LOD_SHADOWS[3]): _range(part, LOD3_FROM, 0.0)
	var cells := {}
	var fine := SEED_FINE_CHUNK if _is_seed(asset) else FINE_CHUNK
	for t: Transform3D in transforms:
		var key := Vector2i(floori(t.origin.x / fine), floori(t.origin.z / fine))
		if not cells.has(key): cells[key] = []
		cells[key].append(t)
	for key: Vector2i in cells:
		for level in 2:
			for near in _tree_instances(parent, asset, level, cells[key], "%s_LOD%d_%d_%d" % [asset, level, key.x, key.y], LOD_SHADOWS[level]):
				_range(near, 0.0 if level == 0 else lod1_from, lod1_from if level == 0 else 0.0)
				near.visibility_parent = near.get_path_to(far)

## Instances one bush asset over a cell: LOD0 (with shadow) near, LOD1 / LOD2 beyond, and
## nothing past BUSH_LOD2_END.
static func add_bush_chunk(parent: Node3D, asset: String, transforms: Array) -> void:
	if transforms.is_empty(): return
	var lods := lod_meshes(asset)
	var bands := [0.0, BUSH_LOD1_FROM, BUSH_LOD2_FROM, BUSH_LOD2_END]
	for level in lods.size():
		_range(_instances(parent, lods[level], transforms, "%s_LOD%d" % [asset, level], BUSH_SHADOWS[level]), bands[level], bands[level + 1])

## One grass or flower chunk: all clumps up to GRASS_NEAR, every other clump (scaled up 15 % to keep
## the cover) out to GRASS_FAR, where the shader has already sunk them into the ground.
## Sparse flower drifts skip the thinned band: one MultiMesh to GRASS_FAR is fewer draws.
## `normals` (optional, one per transform) are the terrain normals under the clumps; the
## grass shader lights each blade with them so the meadow shades like the ground.
static func add_grass_chunk(parent: Node3D, asset: String, transforms: Array, normals: Array = []) -> void:
	if transforms.is_empty(): return
	var mesh := lod_meshes(asset)[0]
	var custom: Array = []
	for n: Vector3 in normals: custom.append(Color(n.x, n.y, n.z, 0.0))
	if asset in FLOWERS:
		_range(_instances(parent, mesh, transforms, asset, false, custom), 0.0, GRASS_FAR)
		return
	_range(_instances(parent, mesh, transforms, asset, false, custom), 0.0, GRASS_NEAR)
	var sparse: Array = []
	var sparse_custom: Array = []
	for i in range(0, transforms.size(), 2):
		var t: Transform3D = transforms[i]
		sparse.append(Transform3D(t.basis.scaled(Vector3.ONE * 1.15), t.origin))
		if not custom.is_empty(): sparse_custom.append(custom[i])
	_range(_instances(parent, mesh, sparse, asset + "_mid", false, sparse_custom), GRASS_NEAR, GRASS_FAR)
