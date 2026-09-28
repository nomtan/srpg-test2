extends Node3D
## Cel-look sword swing effect: a flat-banded, outlined crescent swept by the blade,
## and shards, a star flash and hit-stop at impact.
## Built in world space each frame from the blade's sampled edge.
const SHADER = preload("res://scripts/world_jrpg/sword_slash_fx.gdshader")
const FLASH_SHADER = preload("res://scripts/world_jrpg/sword_slash_flash.gdshader")
const OUTLINE := Color(0.12, 0.14, 0.38)
const LIFETIME := 0.26
const SUBDIVISIONS := 4
# Ribbon edge along the blade in grip space; the effect reaches well past the tip.
const INNER := Vector3(0, 0.15, 0)
const OUTER := Vector3(0, 0.78, 0)
const HIT_STOP := 0.06

var blade: Node3D
var player: AnimationPlayer
var timings: Dictionary
var _samples: Array = []
var _last_time := -1.0
var _slash: MeshInstance3D
var _dust: CPUParticles3D
var _flash: MeshInstance3D

func setup(sword_grip: Node3D, animation_player: AnimationPlayer, clip_timings: Dictionary) -> void:
	blade = sword_grip
	player = animation_player
	timings = clip_timings

func _ready() -> void:
	top_level = true
	_slash = _ribbon({"highlight_color": Color(0.97, 1.0, 1.0), "base_color": Color(0.38, 0.82, 1.0),
		"shade_color": Color(0.36, 0.42, 0.95), "tail_color": Color(0.62, 0.44, 1.0), "outline_color": OUTLINE})
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 14
	_dust.lifetime = 0.35
	_dust.explosiveness = 0.95
	_dust.local_coords = false
	_dust.particle_flag_align_y = true
	_dust.direction = Vector3(0, 0.25, 1)
	_dust.spread = 75.0
	_dust.gravity = Vector3.ZERO
	_dust.damping_min = 6.0
	_dust.damping_max = 9.0
	# Cel shards pop and shrink away rather than fading out.
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(0.6, 0.8))
	shrink.add_point(Vector2(1, 0))
	_dust.scale_amount_curve = shrink
	_dust.mesh = _streak_mesh()
	add_child(_dust)
	_flash = MeshInstance3D.new()
	_flash.mesh = QuadMesh.new()
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_material := ShaderMaterial.new()
	flash_material.shader = FLASH_SHADER
	flash_material.set_shader_parameter("outline_color", OUTLINE)
	_flash.material_override = flash_material
	_flash.visible = false
	add_child(_flash)

func _ribbon(parameters: Dictionary) -> MeshInstance3D:
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = ImmediateMesh.new()
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	for key: String in parameters:
		material.set_shader_parameter(key, parameters[key])
	ribbon.material_override = material
	add_child(ribbon)
	return ribbon

# Two crossed diamond spikes so the velocity-aligned shards read from any camera angle.
# A slightly larger dark spike sits between two light faces as the ink outline.
func _streak_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in [[OUTLINE, 1.6, 0.0], [Color(0.95, 0.98, 1.0), 1.0, 0.004], [Color(0.95, 0.98, 1.0), 1.0, -0.004]]:
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var side: Vector3 = axis * 0.035 * layer[1]
			var lift: Vector3 = Vector3.UP.cross(axis) * layer[2]
			var corners := [Vector3.UP * -0.03 * layer[1], side + Vector3.UP * 0.12, Vector3.UP * (0.5 + 0.03 * layer[1]), -side + Vector3.UP * 0.12]
			for index in [0, 1, 2, 0, 2, 3]:
				tool.set_color(layer[0])
				tool.add_vertex(corners[index] + lift)
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh

func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for sample: Dictionary in _samples:
		sample.age += delta
	_samples = _samples.filter(func(sample: Dictionary) -> bool: return sample.age < LIFETIME)
	var clip: String = player.current_animation if player and player.is_playing() else ""
	var timing: Dictionary = timings.get(clip, {})
	var time: float = player.current_animation_position if not timing.is_empty() else -1.0
	if not timing.is_empty() and is_visible_in_tree():
		var window: Vector2 = timing.trail
		if time >= window.x and time <= window.y:
			_samples.append({"inner": blade.global_transform * INNER, "outer": blade.global_transform * OUTER, "age": 0.0})
		if _last_time >= 0.0 and _last_time < timing.impact and time >= timing.impact:
			_impact()
	_last_time = time
	_rebuild()

func _impact() -> void:
	var tip := blade.global_transform * OUTER
	var reach := (blade.global_transform * OUTER - blade.global_transform * INNER).length()
	var ground := get_parent() as Node3D
	var floor_y: float = ground.global_position.y if ground else tip.y
	_dust.global_position = Vector3(tip.x, floor_y + reach * 0.05, tip.z)
	var forward := (tip - blade.global_position) * Vector3(1, 0, 1)
	if not forward.is_zero_approx():
		_dust.global_basis = Basis.looking_at(-forward.normalized(), Vector3.UP)
	_dust.initial_velocity_min = reach * 2.0
	_dust.initial_velocity_max = reach * 4.5
	_dust.scale_amount_min = reach * 0.35
	_dust.scale_amount_max = reach * 0.8
	_dust.restart()
	_flash.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * reach * 0.9), tip)
	_flash.visible = true
	var material := _flash.material_override as ShaderMaterial
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, 0.16)
	tween.tween_callback(_flash.hide)
	# Brief hit-stop sells the weight of the contact frame.
	var clip := player.current_animation
	var speed := player.speed_scale
	player.speed_scale = speed * 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(player) and player.current_animation == clip: player.speed_scale = speed)

func _rebuild() -> void:
	var slash_mesh := _slash.mesh as ImmediateMesh
	slash_mesh.clear_surfaces()
	var points := _smoothed()
	if points.size() >= 2:
		_strip(slash_mesh, points, LIFETIME, func(point: Dictionary) -> Array: return [point.inner, point.outer])

func _strip(mesh: ImmediateMesh, points: Array, lifetime: float, edge: Callable) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for point: Dictionary in points:
		var pair: Array = edge.call(point)
		var age: float = clampf(point.age / lifetime, 0.0, 1.0)
		mesh.surface_set_uv(Vector2(age, 0.0))
		mesh.surface_add_vertex(pair[0])
		mesh.surface_set_uv(Vector2(age, 1.0))
		mesh.surface_add_vertex(pair[1])
	mesh.surface_end()

# Catmull-Rom between frame samples keeps the arc round during very fast swings.
func _smoothed() -> Array:
	var count := _samples.size()
	if count < 3: return _samples.duplicate()
	var result: Array = []
	for index in count - 1:
		var p0: Dictionary = _samples[maxi(index - 1, 0)]
		var p1: Dictionary = _samples[index]
		var p2: Dictionary = _samples[index + 1]
		var p3: Dictionary = _samples[mini(index + 2, count - 1)]
		for step in SUBDIVISIONS:
			var t := float(step) / SUBDIVISIONS
			result.append({
				"inner": _catmull(p0.inner, p1.inner, p2.inner, p3.inner, t),
				"outer": _catmull(p0.outer, p1.outer, p2.outer, p3.outer, t),
				"age": lerpf(p1.age, p2.age, t),
			})
	result.append(_samples[-1])
	return result

func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)
