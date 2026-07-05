class_name VoxelMap
extends Node3D

var grid: GridSystem

# Top face colors (visible surface) — Minecraft-style bright terrain
var top_colors := {
	"grass":       Color("#5a9e3a"),
	"dirt":        Color("#9a7055"),
	"stone":       Color("#909090"),
	"rock":        Color("#4a4a4a"),
	"forest":      Color("#2d5c25"),
	"water":       Color("#3a7fd5"),
	"lava":        Color("#ff5500"),
	"high_ground": Color("#8ab870"),
	"wall":        Color("#5a5a60"),
}

# Side/body colors — dirt-like undersides as in Minecraft grass blocks
var side_colors := {
	"grass":       Color("#a87550"),
	"dirt":        Color("#966744"),
	"stone":       Color("#969696"),
	"rock":        Color("#5e5e5e"),
	"forest":      Color("#806044"),
	"water":       Color("#3978c4"),
	"lava":        Color("#6b2410"),
	"high_ground": Color("#9b806c"),
	"wall":        Color("#65656e"),
}


func build_from_grid(source_grid: GridSystem) -> void:
	grid = source_grid
	for child in get_children():
		child.queue_free()
	_create_background_plane()
	for grid_pos: Vector2i in grid.cells:
		var cell := grid.get_cell(grid_pos)
		for level in cell.height:
			_create_block(grid_pos, level, cell)


func _create_background_plane() -> void:
	# グリッド端(x/z=0や39付近)に視点が寄ると、カメラを回転・ズームしても
	# 実グリッド外は何も描画されず背景色が見えて「マップが欠けた」ように見える。
	# 実際のセルより一回り低い位置に大きな地面を敷いて、その見た目の空白を埋める。
	var margin := 60.0
	var bg := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GridSystem.WIDTH + margin * 2.0, GridSystem.DEPTH + margin * 2.0)
	bg.mesh = plane
	bg.position = Vector3(GridSystem.WIDTH * 0.5, 0.97, GridSystem.DEPTH * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = top_colors.get("grass", Color("#5a9e3a"))
	mat.roughness = 1.0
	bg.material_override = mat
	add_child(bg)


func _create_block(grid_pos: Vector2i, level: int, cell: GridCell) -> void:
	var is_top := level == cell.height - 1
	var world_pos := Vector3(grid_pos.x + 0.5, float(level) + 0.5, grid_pos.y + 0.5)

	if cell.terrain == "water":
		if is_top:
			_create_water_surface(world_pos)
		return

	if cell.terrain == "lava":
		if is_top:
			_create_lava_surface(world_pos)
		return

	# Body block — sides use darker dirt/rock color
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.96
	body.mesh = box
	body.position = world_pos
	var side_col: Color = side_colors.get(cell.terrain, Color.GRAY)
	if cell.height > 1:
		# Keep lower blocks darker for depth, but do not let tall columns lose
		# their terrain color before lighting and shadows are applied.
		var depth_shade := minf(float(cell.height - level - 1) * 0.04, 0.14)
		side_col = side_col.darkened(depth_shade)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = side_col
	# Keep the terrain hue readable even on faces turned away from the light.
	bmat.emission_enabled = true
	bmat.emission = side_col.darkened(0.65)
	bmat.emission_energy_multiplier = 0.25
	bmat.roughness = 0.95
	body.material_override = bmat
	add_child(body)

	# Top face — bright terrain color, overlaid just above the box
	if is_top:
		var top := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.96, 0.96)
		top.mesh = plane
		top.position = world_pos + Vector3(0.0, 0.481, 0.0)
		var top_col: Color = top_colors.get(cell.terrain, Color.WHITE)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = top_col
		tmat.roughness = 0.9
		top.material_override = tmat
		add_child(top)


func _create_lava_surface(world_pos: Vector3) -> void:
	# Dark obsidian base
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(0.96, 0.55, 0.96)
	bed.mesh = bed_mesh
	bed.position = world_pos + Vector3(0.0, -0.12, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#1a0800")
	bmat.roughness = 1.0
	bed.material_override = bmat
	add_child(bed)

	# Glowing lava surface
	var lava := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.96, 0.96)
	lava.mesh = plane
	lava.position = world_pos + Vector3(0.0, 0.3, 0.0)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("#ff4400")
	lmat.emission_enabled = true
	lmat.emission = Color("#ff2200")
	lmat.emission_energy_multiplier = 2.0
	lmat.roughness = 0.0
	lava.material_override = lmat
	add_child(lava)


func _create_water_surface(world_pos: Vector3) -> void:
	# Shallow river bed
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(0.96, 0.5, 0.96)
	bed.mesh = bed_mesh
	bed.position = world_pos + Vector3(0.0, -0.1, 0.0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#4a3828")
	bmat.roughness = 1.0
	bed.material_override = bmat
	add_child(bed)

	# Translucent water surface plane
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.96, 0.96)
	water.mesh = plane
	water.position = world_pos + Vector3(0.0, 0.35, 0.0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.23, 0.50, 0.84, 0.78)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.05
	wmat.metallic = 0.1
	water.material_override = wmat
	add_child(water)
