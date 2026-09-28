extends Node3D
## Stylized sword swing effect: a crescent ribbon swept by the blade, a grey wind
## streak along the ground below it, and a dust burst, flash and hit-stop at impact.
## Built in world space each frame from the blade's sampled edge.
const SHADER = preload("res://scripts/world_jrpg/sword_slash_fx.gdshader")
const LIFETIME := 0.26
const GROUND_LIFETIME := 0.42
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
var _ground: MeshInstance3D
var _dust: CPUParticles3D
var _flash: OmniLight3D

func setup(sword_grip: Node3D, animation_player: AnimationPlayer, clip_timings: Dictionary) -> void:
	blade = sword_grip
	player = animation_player
	timings = clip_timings

func _ready() -> void:
	top_level = true
	_slash = _ribbon(Color(0.93, 0.99, 1.0), Color(0.42, 0.8, 1.0), Color(0.6, 0.46, 1.0), 1.0)
	_ground = _ribbon(Color(0.9, 0.92, 0.95), Color(0.66, 0.68, 0.72), Color(0.55, 0.56, 0.6), 0.55)
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
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.88, 0.92, 0.9))
	fade.set_color(1, Color(0.6, 0.62, 0.66, 0.0))
	_dust.color_ramp = fade
	_dust.mesh = _streak_mesh()
	add_child(_dust)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.6, 0.85, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)

func _ribbon(edge: Color, core: Color, tail: Color, opacity: float) -> MeshInstance3D:
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = ImmediateMesh.new()
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("edge_color", edge)
	material.set_shader_parameter("core_color", core)
	material.set_shader_parameter("tail_color", tail)
	material.set_shader_parameter("opacity", opacity)
	ribbon.material_override = material
	add_child(ribbon)
	return ribbon

# Two crossed quads so the velocity-aligned streaks read from any camera angle.
func _streak_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var side: Vector3 = axis * 0.02
		var corners := [-side, side, side + Vector3.UP * 0.5, -side + Vector3.UP * 0.5]
		for index in [0, 1, 2, 0, 2, 3]:
			tool.set_uv(Vector2(float(index in [1, 2]), float(index in [2, 3])))
			tool.add_vertex(corners[index])
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# Soft ends: fade the streak toward both tips.
	var ramp := Gradient.new()
	ramp.set_offset(1, 1.0)
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.35, Color.WHITE)
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh

func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	for sample: Dictionary in _samples:
		sample.age += delta
	_samples = _samples.filter(func(sample: Dictionary) -> bool: return sample.age < GROUND_LIFETIME)
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
	_flash.global_position = tip
	_flash.omni_range = reach * 1.6
	_flash.light_energy = 1.4
	create_tween().tween_property(_flash, "light_energy", 0.0, 0.18)
	# Brief hit-stop sells the weight of the contact frame.
	var clip := player.current_animation
	var speed := player.speed_scale
	player.speed_scale = speed * 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(player) and player.current_animation == clip: player.speed_scale = speed)

func _rebuild() -> void:
	var slash_mesh := _slash.mesh as ImmediateMesh
	var ground_mesh := _ground.mesh as ImmediateMesh
	slash_mesh.clear_surfaces()
	ground_mesh.clear_surfaces()
	var points := _smoothed()
	var slash := points.filter(func(point: Dictionary) -> bool: return point.age < LIFETIME)
	if slash.size() >= 2:
		_strip(slash_mesh, slash, LIFETIME, func(point: Dictionary) -> Array: return [point.inner, point.outer])
	if points.size() >= 2:
		var ground := get_parent() as Node3D
		var floor_y: float = ground.global_position.y if ground else 0.0
		# Project the swept arc onto the ground as a wider wind streak.
		_strip(ground_mesh, points, GROUND_LIFETIME, func(point: Dictionary) -> Array:
			var lift: float = (point.outer - point.inner).length() * 0.04 + floor_y
			var inner: Vector3 = point.inner.lerp(point.outer, 0.35)
			var outer: Vector3 = point.outer + (point.outer - point.inner) * 0.3
			return [Vector3(inner.x, lift, inner.z), Vector3(outer.x, lift, outer.z)])

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
