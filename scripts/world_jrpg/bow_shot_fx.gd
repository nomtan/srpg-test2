extends Node3D
## Bow shot effect: the live bowstring, the nocked arrow between the hands, and the loosed arrow's flight
## with a fading trail and a star flash at release.
## Built in world space each frame from the bow and the drawing hand.
const FLASH_SHADER = preload("res://scripts/world_jrpg/sword_slash_flash.gdshader")
const OUTLINE := Color(0.12, 0.14, 0.38)
const STRING_COLOR := Color(0.95, 0.9, 0.78)
# String thickness in bow units (the bow model's own scale).
const STRING_RADIUS := 0.0035
# The released string rings for a moment: amplitude (bow units), frequency (rad/s) and damping (1/s).
const TWANG := Vector3(0.05, 75.0, 12.0)
const FLIGHT_TIME := 0.8
const TRAIL_SAMPLES := 9
const TRAIL_WIDTH := 0.05

var bow: Node3D
var nock: Node3D
var player: AnimationPlayer
var timings: Dictionary
var make_arrow: Callable
# Bow-local points: the string's ends and where the arrow rests on the grip.
var string_top: Vector3
var string_bottom: Vector3
var arrow_rest: Vector3
var _held: Node3D
var _strings: Array[MeshInstance3D] = []
var _flights: Array = []
var _trail: MeshInstance3D
var _flash: MeshInstance3D
var _last_time := -1.0
var _last_clip := ""
var _since_release := INF

## bow_node is the bow model in its authored frame (string side +X); nock_node sits at the drawing hand's palm.
## arrow_factory returns a new arrow pivot: nock at its origin, pointing along +Y at unit scale.
func setup(bow_node: Node3D, nock_node: Node3D, animation_player: AnimationPlayer, clip_timings: Dictionary,
		arrow_factory: Callable, top: Vector3, bottom: Vector3, rest: Vector3) -> void:
	bow = bow_node
	nock = nock_node
	player = animation_player
	timings = clip_timings
	make_arrow = arrow_factory
	string_top = top
	string_bottom = bottom
	arrow_rest = rest

func _ready() -> void:
	top_level = true
	var string_material := StandardMaterial3D.new()
	string_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	string_material.albedo_color = STRING_COLOR
	for index in 2:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = 4
		cylinder.rings = 0
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		var segment := MeshInstance3D.new()
		segment.name = "BowString%d" % index
		segment.mesh = cylinder
		segment.material_override = string_material
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(segment)
		_strings.append(segment)
	_held = make_arrow.call()
	_held.name = "NockedArrow"
	_held.visible = false
	add_child(_held)
	_trail = MeshInstance3D.new()
	_trail.name = "ArrowTrail"
	_trail.mesh = ImmediateMesh.new()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trail_material := StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = trail_material
	add_child(_trail)
	_flash = MeshInstance3D.new()
	_flash.mesh = QuadMesh.new()
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_material := ShaderMaterial.new()
	flash_material.shader = FLASH_SHADER
	flash_material.set_shader_parameter("outline_color", OUTLINE)
	_flash.material_override = flash_material
	_flash.visible = false
	add_child(_flash)

## Whether an arrow is nocked at this point of the given clip.
func is_nocked(clip: String, time: float) -> bool:
	var timing: Dictionary = timings.get(clip, {})
	return not timing.is_empty() and time >= timing.nock and time < timing.release

func _process(delta: float) -> void:
	global_transform = Transform3D.IDENTITY
	var clip: String = player.current_animation if player and player.is_playing() else ""
	var time: float = player.current_animation_position if not clip.is_empty() else -1.0
	var timing: Dictionary = timings.get(clip, {})
	if not timing.is_empty() and clip == _last_clip and _last_time < timing.release and time >= timing.release and is_visible_in_tree():
		_loose(timing)
	_last_clip = clip
	_last_time = time
	_since_release += delta
	var drawing := is_nocked(clip, time)
	_update_string(drawing)
	_held.visible = drawing
	if drawing:
		_held.global_transform = _arrow_transform()
	_fly(delta)

## Nock at the drawing hand, pointing at the arrow rest on the grip.
func _arrow_transform() -> Transform3D:
	var from := nock.global_position
	var aim := bow.global_transform * arrow_rest - from
	if aim.length() < 0.02:
		aim = bow.global_basis * Vector3.LEFT
	return Transform3D(Basis(Quaternion(Vector3.UP, aim.normalized())).scaled(Vector3.ONE * _unit()), from)

## World size of one skeleton unit (the character's display scale).
func _unit() -> float:
	return nock.global_basis.get_scale().x

func _update_string(drawing: bool) -> void:
	var anchor := (string_top + string_bottom) * 0.5
	var drawn := bow.global_transform.affine_inverse() * nock.global_position
	# The string follows the hand only once it is pulled back past the braced line.
	if drawing and drawn.x > anchor.x:
		anchor = drawn
	elif _since_release < 1.0:
		anchor.x += TWANG.x * sin(_since_release * TWANG.y) * exp(-_since_release * TWANG.z)
	var points := [string_top, anchor, string_bottom].map(func(point: Vector3) -> Vector3: return bow.global_transform * point)
	var radius := STRING_RADIUS * bow.global_basis.get_scale().x
	for index in 2:
		var from: Vector3 = points[index]
		var span: Vector3 = points[index + 1] - from
		var side := span.cross(Vector3.FORWARD if absf(span.normalized().z) < 0.9 else Vector3.RIGHT).normalized()
		var depth := side.cross(span).normalized()
		_strings[index].global_transform = Transform3D(Basis(side * radius, span, depth * radius), from + span * 0.5)

## Release the nocked arrow along its aim, with the clip's speed and drop.
func _loose(timing: Dictionary) -> void:
	_since_release = 0.0
	var start := _arrow_transform()
	var arrow: Node3D = make_arrow.call()
	arrow.name = "LoosedArrow"
	add_child(arrow)
	arrow.global_transform = start
	var tip := start * Vector3(0, 1, 0)
	_flights.append({"node": arrow, "velocity": start.basis.y.normalized() * timing.speed,
		"gravity": timing.get("gravity", 0.0), "age": 0.0, "trail": [tip], "color": timing.get("trail", Color.WHITE)})
	_flash.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * timing.get("flash", 0.4) * _unit()), bow.global_transform * arrow_rest)
	_flash.visible = true
	var material := _flash.material_override as ShaderMaterial
	var tween := create_tween()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("progress", value), 0.0, 1.0, 0.16)
	tween.tween_callback(_flash.hide)

func _fly(delta: float) -> void:
	var mesh := _trail.mesh as ImmediateMesh
	mesh.clear_surfaces()
	for flight: Dictionary in _flights:
		flight.age += delta
		flight.velocity += Vector3.DOWN * flight.gravity * delta
		var arrow: Node3D = flight.node
		var scale := arrow.global_basis.get_scale().x
		arrow.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, (flight.velocity as Vector3).normalized())).scaled(Vector3.ONE * scale),
			arrow.global_position + flight.velocity * delta)
		var trail: Array = flight.trail
		trail.append(arrow.global_transform * Vector3(0, 0.15, 0))
		if trail.size() > TRAIL_SAMPLES: trail.pop_front()
		# Fade the whole arrow out over its last moments instead of popping away.
		var fade := clampf((FLIGHT_TIME - flight.age) / 0.15, 0.0, 1.0)
		_draw_trail(mesh, trail, flight.color, fade, TRAIL_WIDTH * scale)
		arrow.visible = fade > 0.0
	for flight: Dictionary in _flights.filter(func(flight: Dictionary) -> bool: return flight.age >= FLIGHT_TIME):
		(flight.node as Node3D).queue_free()
	_flights = _flights.filter(func(flight: Dictionary) -> bool: return flight.age < FLIGHT_TIME)

## Two crossed ribbons along the arrow's recent path, thinning and fading toward the oldest sample.
func _draw_trail(mesh: ImmediateMesh, trail: Array, color: Color, fade: float, width: float) -> void:
	if trail.size() < 2: return
	var along: Vector3 = (trail[-1] - trail[0]).normalized()
	for axis in [Vector3.UP, along.cross(Vector3.UP).normalized()]:
		if axis.is_zero_approx(): continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for index in trail.size():
			var weight := float(index) / (trail.size() - 1)
			var edge: Vector3 = axis * width * weight
			mesh.surface_set_color(Color(color, color.a * weight * fade))
			mesh.surface_add_vertex(trail[index] - edge)
			mesh.surface_set_color(Color(color, color.a * weight * fade))
			mesh.surface_add_vertex(trail[index] + edge)
		mesh.surface_end()
