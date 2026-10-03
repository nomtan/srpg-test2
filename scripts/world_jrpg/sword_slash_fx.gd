extends Node3D
## Sword swing effect: a crescent with a solid white-hot band swept by the blade, and hit-stop at impact.
## Built in world space each frame from the blade's sampled edge.
const SHADER = preload("res://scripts/world_jrpg/sword_slash_fx.gdshader")
const LIFETIME := 0.26
const SUBDIVISIONS := 8
# Ribbon edge along the blade in grip space; the effect reaches well past the tip.
const INNER := Vector3(0, 0.15, 0)
const OUTER := Vector3(0, 0.78, 0)
const HIT_STOP := 0.06

var blade: Node3D
var player: AnimationPlayer
var timings: Dictionary
var inner := INNER
var outer := OUTER
var _samples: Array = []
var _last_time := -1.0
var _slash: MeshInstance3D

func setup(sword_grip: Node3D, animation_player: AnimationPlayer, clip_timings: Dictionary, edge_inner := INNER, edge_outer := OUTER) -> void:
	blade = sword_grip
	player = animation_player
	timings = clip_timings
	inner = edge_inner
	outer = edge_outer

func _ready() -> void:
	top_level = true
	_slash = MeshInstance3D.new()
	_slash.mesh = ImmediateMesh.new()
	_slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_slash.material_override = material
	add_child(_slash)

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
			_samples.append({"inner": blade.global_transform * inner, "outer": blade.global_transform * outer, "age": 0.0})
		if _last_time >= 0.0 and _last_time < timing.impact and time >= timing.impact:
			_impact(timing.get("hit_stop", true))
	_last_time = time
	_rebuild()

func _impact(hit_stop := true) -> void:
	if not hit_stop: return
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
