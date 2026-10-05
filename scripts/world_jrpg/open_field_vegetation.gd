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
const BUSHES := ["bush_a", "bush_b", "bush_c"]
const GRASSES := ["grass_short", "grass_normal", "grass_tall", "grass_wild"]
const FLOWERS := ["flower_grass_a", "flower_grass_b"]
## Blender material slot name -> shared runtime material.
const SLOT_MATERIALS := {"Trunk": TRUNK_MATERIAL, "Leaves": FOLIAGE_MATERIAL, "LeafCards": LEAF_CARD_MATERIAL,
	"LeafCore": LEAF_CARD_MATERIAL, "NeedleCards": NEEDLE_CARD_MATERIAL, "NeedleCore": NEEDLE_CARD_MATERIAL,
	"BlossomCards": BLOSSOM_CARD_MATERIAL, "BlossomCore": BLOSSOM_CARD_MATERIAL, "Grass": GRASS_MATERIAL, "Flower": FLOWER_MATERIAL}
## Tree LOD bands, measured by Godot from the camera to each MultiMesh's AABB center.
## LOD0/LOD1 live in FINE_CHUNK cells under a COARSE_CHUNK LOD2/LOD3 cell (see
## add_tree_chunk), so a tree's own distance stays within ~11 m / ~23 m of its cell's.
const LOD1_FROM := 34.0
const LOD2_FROM := 80.0
const LOD3_FROM := 160.0
const LOD_MARGIN := 4.0
const FINE_CHUNK := 16.0
const COARSE_CHUNK := 32.0
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
static var meshes: Dictionary = {}
## Leaf-card trees: per LOD, the "<Kind>Cards" surface index (-1 when that LOD has none).
static var card_surfaces: Dictionary = {}
## Leaf-card trees: per LOD, [body mesh (trunk + cores), cards mesh or null].
static var card_parts: Dictionary = {}

## LOD meshes of one asset, finest first, with the shared materials assigned.
static func lod_meshes(asset: String) -> Array[Mesh]:
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
				mesh.surface_set_material(surface, SLOT_MATERIALS[key])
		meshes[asset] = list
		if asset in CARD_TREES: card_surfaces[asset] = cards
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
			var body := ArrayMesh.new()
			var cards: ArrayMesh = null
			for surface in lods[l].get_surface_count():
				var target := body
				if surface == index:
					cards = ArrayMesh.new()
					target = cards
				target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lods[l].surface_get_arrays(surface))
				target.surface_set_material(target.get_surface_count() - 1, lods[l].surface_get_material(surface))
			parts.append([body, cards])
		card_parts[asset] = parts
	return card_parts[asset][level]

static func shader_materials() -> Array[ShaderMaterial]:
	return [TRUNK_MATERIAL, FOLIAGE_MATERIAL, LEAF_CARD_MATERIAL, NEEDLE_CARD_MATERIAL, BLOSSOM_CARD_MATERIAL, GRASS_MATERIAL, FLOWER_MATERIAL]

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

static func _instances(parent: Node3D, mesh: Mesh, transforms: Array, node_name: String, shadows: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
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
	if asset not in CARD_TREES:
		list.append(_instances(parent, lod_meshes(asset)[level], transforms, node_name, shadows))
		return list
	var parts := split_cards(asset, level)
	list.append(_instances(parent, parts[0], transforms, node_name, shadows))
	if parts[1] != null: list.append(_instances(parent, parts[1], transforms, node_name + "_cards", false))
	return list

static func _range(instance: GeometryInstance3D, begin: float, end: float) -> void:
	instance.visibility_range_begin = begin
	instance.visibility_range_end = end
	instance.visibility_range_begin_margin = LOD_MARGIN if begin > 0.0 else 0.0
	instance.visibility_range_end_margin = LOD_MARGIN if end > 0.0 else 0.0

## Instances one tree asset over a COARSE_CHUNK cell with hierarchical LOD: the cell's
## LOD2 MultiMesh is the visibility parent of FINE_CHUNK LOD0/LOD1 MultiMeshes, which
## only draw once the camera is inside LOD2's begin distance. No tree is ever drawn
## twice or skipped across a band, and far cells cost one draw per band.
static func add_tree_chunk(parent: Node3D, asset: String, transforms: Array) -> void:
	if transforms.is_empty(): return
	var lods := lod_meshes(asset)
	var far_parts := _tree_instances(parent, asset, 2, transforms, "%s_LOD2" % asset, LOD_SHADOWS[2])
	for part in far_parts: _range(part, LOD2_FROM, LOD3_FROM if lods.size() > 3 else 0.0)
	var far := far_parts[0]
	if lods.size() > 3:
		for part in _tree_instances(parent, asset, 3, transforms, "%s_LOD3" % asset, LOD_SHADOWS[3]): _range(part, LOD3_FROM, 0.0)
	var cells := {}
	for t: Transform3D in transforms:
		var key := Vector2i(floori(t.origin.x / FINE_CHUNK), floori(t.origin.z / FINE_CHUNK))
		if not cells.has(key): cells[key] = []
		cells[key].append(t)
	for key: Vector2i in cells:
		for level in 2:
			for near in _tree_instances(parent, asset, level, cells[key], "%s_LOD%d_%d_%d" % [asset, level, key.x, key.y], LOD_SHADOWS[level]):
				_range(near, 0.0 if level == 0 else LOD1_FROM, LOD1_FROM if level == 0 else 0.0)
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
static func add_grass_chunk(parent: Node3D, asset: String, transforms: Array) -> void:
	if transforms.is_empty(): return
	var mesh := lod_meshes(asset)[0]
	if asset in FLOWERS:
		_range(_instances(parent, mesh, transforms, asset, false), 0.0, GRASS_FAR)
		return
	_range(_instances(parent, mesh, transforms, asset, false), 0.0, GRASS_NEAR)
	var sparse: Array = []
	for i in range(0, transforms.size(), 2):
		var t: Transform3D = transforms[i]
		sparse.append(Transform3D(t.basis.scaled(Vector3.ONE * 1.15), t.origin))
	_range(_instances(parent, mesh, sparse, asset + "_mid", false), GRASS_NEAR, GRASS_FAR)
