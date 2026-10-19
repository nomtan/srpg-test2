extends RefCounted
## Ghibli / BotW grass carpet for JRPGWorldSample2: one procedural blade patch per 1 m
## cell, packed edge to edge so the ground never shows between clumps. The look comes
## from open_field_meadow_grass.gdshader (ground-normal shading, root->tip ramp, soft
## painted light, sunlit tips); this side builds the patch meshes and the MultiMeshes.
##
## A patch is a unit-height disc of curved, tapered blades. Its instance basis carries
## the height (Y axis length) and shears X / Z along the terrain slope so every blade
## root sits on the ground while the blades stay upright.
const MATERIAL = preload("res://assets/environment/vegetation/materials/meadow_grass.tres")
## Blades in the near patch; the mid patch keeps the first MID_SHARE of them, wider.
const NEAR_BLADES := 90
const MID_SHARE := 0.3
## Patch disc radius (m): a little over half a cell, so neighbors overlap.
const RADIUS := 0.68
## Near patches draw up to NEAR_END, mid patches from there to FAR_END (cell centers);
## the shader thins near blades to the mid density and sinks the mid ones into the ground
## ahead of each boundary.
const CELL := 10.0
const NEAR_END := 30.0
const FAR_END := 76.0
const MARGIN := 4.0
## Wind lean and the outward splay reach past the mesh AABB.
const CULL_MARGIN := 0.8
static var _near: ArrayMesh
static var _mid: ArrayMesh

static func near_mesh() -> ArrayMesh:
	if _near == null: _near = _patch(NEAR_BLADES, 1.0, 3)
	return _near

static func mid_mesh() -> ArrayMesh:
	if _mid == null: _mid = _patch(int(NEAR_BLADES * MID_SHARE), 1.7, 2)
	return _mid

## A patch of `count` blades. Blades come out of one fixed seed, so the mid patch is
## exactly the near patch's first blades: the hand-over keeps the same silhouettes.
## Vertex COLOR: r = root->tip tone, g = wind weight, b = per-blade phase, a = thinning
## rank (blades with a higher rank drop out first with distance). UV.y = height above
## the blade root in patch units (the shader sinks / shrinks blades with it).
static func _patch(count: int, width_scale: float, rows: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for b in count:
		# Same random sequence for every blade regardless of the mesh being built.
		var r := RADIUS * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var edge := r / RADIUS
		# Clumps rise toward their middle and fray to short blades at the rim.
		var height := lerpf(1.0, 0.55, edge * edge) * rng.randf_range(0.72, 1.08)
		var width := rng.randf_range(0.03, 0.05) * width_scale
		# Lean: outward from the clump with a random swing, stronger on the outer blades.
		var lean_angle := a + rng.randf_range(-0.9, 0.9)
		var lean := Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * rng.randf_range(0.12, 0.3) * (0.5 + edge)
		var face := Vector3(-lean.z, 0.0, lean.x).normalized() if lean.length() > 0.001 else Vector3.RIGHT
		face = face.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		var phase := rng.randf()
		var rank := float(b) / float(NEAR_BLADES)
		var tone := 0.62 + 0.38 * height
		var base := vertices.size()
		var steps: Array = [0.0, 0.42, 0.78] if rows == 3 else [0.0, 0.55]
		for t: float in steps:
			var spine := root + lean * t * t * height + Vector3(0.0, t * height, 0.0)
			var half := width * 0.5 * (1.0 - t * 0.75)
			for side in [-1.0, 1.0]:
				vertices.append(spine + face * half * side)
				colors.append(Color(t * tone, pow(t, 1.4), phase, rank))
				uvs.append(Vector2(phase, t * height))
				normals.append(Vector3.UP)
		vertices.append(root + lean * height + Vector3(0.0, height, 0.0))
		colors.append(Color(tone, 1.0, phase, rank))
		uvs.append(Vector2(phase, height))
		normals.append(Vector3.UP)
		for s in steps.size() - 1:
			var i := base + s * 2
			indices.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
		var last := base + (steps.size() - 1) * 2
		indices.append_array([last, last + 1, last + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, MATERIAL)
	return mesh

## Patch transform at `position` (the ground point) with a blade height in meters and a
## yaw; `normal` is the terrain normal there.
static func patch_transform(position: Vector3, normal: Vector3, height: float, yaw: float, spread := 1.0) -> Transform3D:
	var n := normal if normal.y > 0.2 else Vector3.UP
	var shear := Basis(Vector3(1.0, -n.x / n.y, 0.0), Vector3.UP, Vector3(0.0, -n.z / n.y, 1.0))
	return Transform3D(shear * Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(spread, height, spread)), position)

## Near and mid MultiMeshes for one CELL. `normals` (one per transform) are the terrain
## normals the shader lights the blades with.
static func add_cell(parent: Node3D, transforms: Array, normals: Array, node_name: String) -> void:
	if transforms.is_empty(): return
	for band in 2:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		# Compatibility renderer: custom data only reaches INSTANCE_CUSTOM while the
		# per-instance color slot is in use too (white keeps the vertex colors).
		multi.use_colors = true
		multi.mesh = near_mesh() if band == 0 else mid_mesh()
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
			var n: Vector3 = normals[i]
			multi.set_instance_custom_data(i, Color(n.x, n.y, n.z, 0.0))
			multi.set_instance_color(i, Color.WHITE)
		var instance := MultiMeshInstance3D.new()
		instance.name = node_name + ("" if band == 0 else "_mid")
		instance.multimesh = multi
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = CULL_MARGIN
		instance.visibility_range_begin = 0.0 if band == 0 else NEAR_END
		instance.visibility_range_end = NEAR_END if band == 0 else FAR_END
		instance.visibility_range_begin_margin = 0.0 if band == 0 else MARGIN
		instance.visibility_range_end_margin = MARGIN
		parent.add_child(instance)
