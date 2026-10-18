extends Node3D
## Effects of the one-handed sword skill (sword/skill): spinning cuts that leave rings of cel-shaded blue flame,
## a dash streak, a vertical crescent of flame with dark-ink tendrils, and a leaping plunge that ends in a white
## flash, a light pillar, a swirling shell, a nebula on the ground and twinkling stars.
## Pieces spawn as the clip passes their time and are placed in the character's frame at the start of the cast
## (skeleton space: +Z forward, -X the sword side, about 1 unit tall). They run on the clip's speed scale, so the
## hit-stops freeze them too, and an interrupted cast fades them out.
const SHADER = preload("res://scripts/world_jrpg/sword_skill_fx.gdshader")
enum {FLAME, WIND, CRESCENT, FLASH, PILLAR, SHELL, NEBULA, STAR, SMOKE, SPARKS, INK, STREAK}
# Clip times (seconds) of the moments the pieces are timed against.
const SPINS := [0.12, 0.42, 0.62]
const BIG_SPIN := 1.06
const DASH := 1.38
const CRESCENT_CUT := 1.82
const FINISH := 2.98
const HIT_STOP := 0.08
const CANCEL_FADE := 0.12
const GROUND_LIFT := 0.04

static var _plane: PlaneMesh
static var _quad: QuadMesh
static var _sphere: SphereMesh

var player: AnimationPlayer
var frame: Node3D
var clip := ""
var _clip := ""
var _last_time := -1.0
var _anchor := Transform3D.IDENTITY
# Pending pieces of this cast, sorted by time, and the live ones.
var _events: Array[Dictionary] = []
var _pieces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func setup(animation_player: AnimationPlayer, character_frame: Node3D, skill_clip: String) -> void:
	player = animation_player
	frame = character_frame
	clip = skill_clip
	top_level = true
	if _plane == null:
		_plane = PlaneMesh.new()
		_plane.size = Vector2(2, 2)
		_quad = QuadMesh.new()
		_quad.size = Vector2(2, 2)
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 32
		_sphere.rings = 16

func _process(delta: float) -> void:
	if player == null: return
	var current := String(player.current_animation) if player.is_playing() else ""
	var time: float = player.current_animation_position if current == clip else -1.0
	if current == clip and (_clip != clip or time < _last_time):
		_begin()
	elif _clip == clip and current != clip:
		# Cut short (another clip took over): drop what has not started and fade the rest.
		if _last_time < player.get_animation(clip).length - 0.05:
			_events.clear()
			for piece in _pieces: piece.fading = true
	_clip = current
	if current == clip and is_visible_in_tree():
		while not _events.is_empty() and time >= _events[0].t:
			_spawn(_events.pop_front())
		if _last_time < FINISH and time >= FINISH: _hit_stop()
	_last_time = time
	var rate := player.speed_scale if current == clip else 1.0
	for index in range(_pieces.size() - 1, -1, -1):
		var piece: Dictionary = _pieces[index]
		if not _advance(piece, delta, rate):
			piece.node.queue_free()
			_pieces.remove_at(index)

## A new cast: anchor to where the character stands now and lay out every piece's time.
func _begin() -> void:
	for piece in _pieces: piece.fading = true
	_anchor = frame.global_transform
	_events.clear()
	_rng.randomize()
	_schedule()
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.t < b.t)

func _schedule() -> void:
	# Spinning cuts: a ring of flame for each turn, the second a tight ring of wind, then a bigger ring.
	_add(SPINS[0], FLAME, "ground", Vector3(0, GROUND_LIFT, 0), 3.2, 0.55, {"param": Vector4(0.6, 0.3, 1.6, 0), "grow": 1.08})
	_add(SPINS[1], WIND, "ground", Vector3(0, GROUND_LIFT + 0.01, 0), 2.2, 0.45, {"param": Vector4(0.35, 0.62, 3, 0.6), "intensity": 1.6})
	_add(SPINS[2], FLAME, "ground", Vector3(0, GROUND_LIFT, 0), 3.5, 0.6, {"param": Vector4(0.6, 0.3, 1.6, 0), "grow": 1.08})
	_add(BIG_SPIN, FLAME, "ground", Vector3(0, GROUND_LIFT, 0), 4.2, 0.75, {"param": Vector4(0.62, 0.32, 1.8, 0), "grow": 1.1})
	_add(BIG_SPIN, WIND, "ground", Vector3(0, GROUND_LIFT + 0.01, 0), 4.6, 0.5, {"param": Vector4(0.62, 0.78, 2, 0.15)})
	for start: float in [SPINS[0] + 0.18, SPINS[2] + 0.2, BIG_SPIN + 0.22]:
		_scatter_ground_ink(start, 6, 1.0, 2.1)
		_scatter_dots(start - 0.08, 12, 2.0, 0.6, 0.4)
	# Dash: a line of light forward along the ground, a star flaring where it ends.
	var dash := Vector3(-0.45, 0, 1).normalized()
	_add(DASH, STREAK, Basis(Vector3.UP, atan2(-dash.z, dash.x)), dash * 2.2 + Vector3(0, GROUND_LIFT, 0), Vector3(2.2, 1, 0.07), 0.35, {"intensity": 1.5})
	_add(DASH + 0.08, STAR, "billboard", dash * 4.2 + Vector3(0, 0.15, 0), 1.1, 0.35, {"param": Vector4(0.95, 0, 0, 0), "intensity": 1.6})
	# Vertical cut: ink blots trace the coming arc, then the crescent bursts out of it.
	var center := Vector3(-0.05, 1.45, 0.75)
	for index in 7:
		var angle := deg_to_rad(lerpf(15.0, 165.0, index / 6.0))
		var at := center + Vector3(0, cos(angle), sin(angle)) * 1.7
		_add(CRESCENT_CUT - 0.1 + index * 0.008, INK, "billboard", at, _rng.randf_range(0.25, 0.4), 0.2, {})
	_add(CRESCENT_CUT, CRESCENT, Basis(Vector3.UP, -PI / 2), center, 2.0, 0.8, {"param": Vector4(0.45, 0.7, 0, 0), "intensity": 0.95, "drift": Vector3(0, 0.25, 0.1)})
	_add(CRESCENT_CUT + 0.02, SPARKS, "billboard", Vector3(-0.15, 0.6, 0.5), 0.9, 0.3, {"intensity": 1.6})
	for index in 3:
		_add(CRESCENT_CUT + 0.03 + index * 0.05, SMOKE, "billboard", Vector3(_rng.randf_range(-0.35, 0.1), _rng.randf_range(0.45, 0.8), _rng.randf_range(0.1, 0.45)),
			_rng.randf_range(0.6, 0.85), _rng.randf_range(0.9, 1.15), {"drift": Vector3(0.05, 0.25, -0.15), "grow": 1.5, "priority": 0})
	_add(CRESCENT_CUT + 0.06, FLAME, "ground", Vector3(0, GROUND_LIFT, 1.0), 2.4, 0.6, {"param": Vector4(0.42, 0.38, 0, 0)})
	for index in 14:
		var angle := deg_to_rad(_rng.randf_range(0.0, 170.0))
		_add(CRESCENT_CUT + _rng.randf_range(0.08, 0.3), STAR, "billboard", center + Vector3(_rng.randf_range(-0.2, 0.2), cos(angle), sin(angle)) * 1.8,
			_rng.randf_range(0.15, 0.3), _rng.randf_range(0.35, 0.6), {"drift": Vector3(0, 0.6, 0)})
	# Finisher: flash, pillar, shell, shock rings, the nebula and its stars.
	_add(FINISH, FLASH, "billboard", Vector3(0, 0.7, 0.25), 6.0, 0.25, {"intensity": 1.6, "priority": 4})
	_add(FINISH, PILLAR, "ybillboard", Vector3(0, 4.0, 0.25), Vector3(0.75, 4.0, 1), 0.55, {"intensity": 1.4, "priority": 3})
	_add(FINISH + 0.02, SHELL, "sphere", Vector3(0, 0.6, 0.25), 1.2, 0.65, {"grow": 1.8, "intensity": 0.7})
	_add(FINISH, WIND, "ground", Vector3(0, GROUND_LIFT + 0.02, 0.25), 3.5, 0.6, {"param": Vector4(0.15, 0.75, 4, 0.8), "intensity": 1.5})
	_add(FINISH + 0.03, WIND, "ground", Vector3(0, GROUND_LIFT + 0.01, 0.25), 5.0, 0.45, {"param": Vector4(0.1, 0.92, 1, 0.2), "intensity": 0.7})
	_add(FINISH + 0.32, WIND, "ground", Vector3(0, GROUND_LIFT + 0.02, 0.25), 2.0, 0.6, {"param": Vector4(0.3, 0.6, 3, 1.0)})
	_add(FINISH, NEBULA, "ground", Vector3(0, GROUND_LIFT - 0.01, 0.25), 6.5, 1.3, {"intensity": 0.8, "priority": -1})
	for index in 26:
		var at := _ring_point(0.8, 3.8) + Vector3(0, _rng.randf_range(0.1, 2.3), 0)
		_add(FINISH + _rng.randf_range(0.05, 0.6), STAR, "billboard", at, _rng.randf_range(0.35, 0.75), _rng.randf_range(0.35, 0.7),
			{"param": Vector4(_rng.randf_range(0.75, 1.0), 0, 0, 0), "intensity": 1.4})
	_scatter_dots(FINISH + 0.02, 50, 4.2, 2.2, 0.7)

func _scatter_ground_ink(start: float, count: int, inner: float, outer: float) -> void:
	for index in count:
		_add(start + _rng.randf_range(0.0, 0.1), INK, "billboard", _ring_point(inner, outer) + Vector3(0, 0.08, 0), _rng.randf_range(0.15, 0.3), _rng.randf_range(0.35, 0.55), {})

func _scatter_dots(start: float, count: int, radius: float, height: float, spread: float) -> void:
	for index in count:
		_add(start + _rng.randf_range(0.0, spread), STAR, "billboard", _ring_point(0.3, radius) + Vector3(0, _rng.randf_range(0.03, height), 0),
			_rng.randf_range(0.12, 0.28), _rng.randf_range(0.4, 0.9), {"drift": Vector3(0, _rng.randf_range(0.1, 0.4), 0)})

func _ring_point(inner: float, outer: float) -> Vector3:
	var angle := _rng.randf() * TAU
	var r := sqrt(_rng.randf_range(inner * inner, outer * outer))
	return Vector3(cos(angle) * r, 0, sin(angle) * r)

## One piece at clip time t: placement is "ground" (flat), "billboard", "ybillboard", "sphere" or a Basis
## for a fixed quad; size is a uniform scale or a Vector3.
func _add(t: float, mode: int, placement: Variant, at: Vector3, size: Variant, life: float, options: Dictionary) -> void:
	_events.append({"t": t, "mode": mode, "placement": placement, "at": at,
		"size": size if size is Vector3 else Vector3.ONE * float(size), "life": life, "options": options})

func _spawn(event: Dictionary) -> void:
	var options: Dictionary = event.options
	var placement: Variant = event.placement
	# A Basis places a fixed quad; otherwise the placement names how the piece faces.
	var kind: String = placement if placement is String else "quad"
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape: Mesh = _quad
	if kind == "ground" or event.mode == STREAK: shape = _plane
	elif kind == "sphere": shape = _sphere
	mesh.mesh = shape
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("mode", event.mode)
	material.set_shader_parameter("billboard", 1 if kind == "billboard" else (2 if kind == "ybillboard" else 0))
	material.set_shader_parameter("seed", _rng.randf_range(0.0, 50.0))
	material.set_shader_parameter("intensity", options.get("intensity", 1.0))
	material.set_shader_parameter("param", options.get("param", Vector4.ZERO))
	material.render_priority = options.get("priority", 0 if event.mode in [INK, SMOKE] else (1 if event.mode == FLAME else 2))
	mesh.material_override = material
	add_child(mesh)
	var piece := {"node": mesh, "material": material, "age": 0.0, "life": event.life, "at": event.at, "size": event.size,
		"basis": placement if placement is Basis else Basis.IDENTITY, "grow": options.get("grow", 1.0),
		"drift": options.get("drift", Vector3.ZERO), "fading": false, "opacity": 1.0}
	_pieces.append(piece)
	_advance(piece, 0.0, 1.0)

func _advance(piece: Dictionary, delta: float, rate: float) -> bool:
	piece.age += delta * rate
	if piece.fading:
		piece.opacity -= delta / CANCEL_FADE
	var k: float = piece.age / piece.life
	if k >= 1.0 or piece.opacity <= 0.0: return false
	var eased := 1.0 - pow(1.0 - k, 3.0)
	var size: Vector3 = piece.size * lerpf(1.0, piece.grow, eased)
	var local := Transform3D((piece.basis as Basis).scaled_local(size), piece.at + (piece.drift as Vector3) * piece.age)
	(piece.node as Node3D).global_transform = _anchor * local
	piece.material.set_shader_parameter("progress", k)
	piece.material.set_shader_parameter("opacity", piece.opacity)
	return true

## The plunge's own hit-stop (the clip's impact, the crescent, gets the slash player's).
func _hit_stop() -> void:
	var speed := player.speed_scale
	player.speed_scale = speed * 0.05
	get_tree().create_timer(HIT_STOP, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(player) and player.current_animation == clip: player.speed_scale = speed)
