extends Node3D
## Sumi brush strokes around a guardian (guardian_ink_stroke.gdshader on arc ribbons).
## play_summon(): strokes swirl in from wide arcs, spiral up and condense onto the body while it forms.
## play_dismiss(): strokes peel off the body and scatter outward and upward while it is erased.
## Sizes are metres in the guardian root's frame (unscaled), tuned for a 2 m guardian and scaled by `height`.

const STROKE_SHADER := preload("res://assets/characters/_shared/materials/guardian_ink_stroke.gdshader")
const SEGMENTS := 28
const BURST_STROKES := 16

## Guardian height in metres (the strokes climb over it).
var height := 2.0
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
## Burst strokes: {node, mode ("in" / "out"), delay, life, angle, spin, r0, r1, y0, y1, tilt}.
var _burst: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = STROKE_SHADER
	_rng.seed = hash(get_path()) if is_inside_tree() else 7


## Strokes spiral in onto the body over `seconds`.
func play_summon(seconds := 1.1) -> void:
	_start_burst("in", seconds)


## Strokes scatter off the body over `seconds`.
func play_dismiss(seconds := 0.9) -> void:
	_start_burst("out", seconds)


func is_busy() -> bool:
	return not _burst.is_empty()


func _start_burst(mode: String, seconds: float) -> void:
	_clear_burst()
	_time = 0.0
	for i in BURST_STROKES:
		var dir := 1 if i % 2 == 0 else -1
		var node := _stroke_node(_rng.randf_range(1.3, 2.6), _rng.randf_range(0.14, 0.3), dir)
		var stroke := {"node": node, "mode": mode, "dir": dir, "angle": TAU * i / BURST_STROKES + _rng.randf_range(-0.3, 0.3),
			"spin": _rng.randf_range(2.0, 3.4), "seed": _rng.randf() * 10.0,
			"tilt": Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))}
		if mode == "in":
			stroke.delay = _rng.randf_range(0.0, seconds * 0.35)
			stroke.life = seconds * _rng.randf_range(0.55, 0.65)
			stroke.r0 = _rng.randf_range(0.95, 1.4) * _size()
			stroke.r1 = _rng.randf_range(0.18, 0.32) * _size()
			stroke.y0 = height * _rng.randf_range(-0.05, 0.35)
			stroke.y1 = height * _rng.randf_range(0.3, 0.95)
		else:
			stroke.delay = _rng.randf_range(0.0, seconds * 0.4)
			stroke.life = seconds * _rng.randf_range(0.5, 0.6)
			stroke.r0 = _rng.randf_range(0.18, 0.32) * _size()
			stroke.r1 = _rng.randf_range(1.0, 1.6) * _size()
			stroke.y0 = height * _rng.randf_range(0.15, 0.9)
			stroke.y1 = stroke.y0 + height * _rng.randf_range(0.2, 0.45)
		node.set_instance_shader_parameter("seed", stroke.seed)
		_burst.append(stroke)
	_update_burst()


func _clear_burst() -> void:
	for stroke: Dictionary in _burst:
		(stroke.node as Node3D).queue_free()
	_burst.clear()


func _process(delta: float) -> void:
	if not _burst.is_empty():
		_time += delta
		_update_burst()


func _update_burst() -> void:
	var done := true
	for stroke: Dictionary in _burst:
		var node := stroke.node as MeshInstance3D
		var q: float = (_time - float(stroke.delay)) / float(stroke.life)
		if q < 0.0:
			node.visible = false
			done = false
			continue
		if q > 1.0:
			node.visible = false
			continue
		done = false
		node.visible = true
		var drawn: float
		var erased: float
		var radius: float
		var fade := 1.0
		if stroke.mode == "in":
			# Painted on quickly, spiralling inward; the tail is eaten as it reaches the body.
			var reach := 1.0 - pow(1.0 - q, 2.2)
			radius = lerpf(stroke.r0, stroke.r1, reach)
			drawn = clampf(q * 2.0, 0.0, 1.0)
			erased = smoothstep(0.45, 1.0, q)
			_place(node, stroke, q, radius, lerpf(stroke.y0, stroke.y1, reach))
		else:
			# Torn off the body: snaps out, flies wide and thins away.
			var reach := 1.0 - pow(1.0 - q, 1.6)
			radius = lerpf(stroke.r0, stroke.r1, reach)
			drawn = clampf(q * 2.6, 0.0, 1.0)
			erased = smoothstep(0.3, 1.0, q)
			fade = 1.0 - smoothstep(0.7, 1.0, q)
			_place(node, stroke, q, radius, lerpf(stroke.y0, stroke.y1, reach))
		node.set_instance_shader_parameter("draw", drawn)
		node.set_instance_shader_parameter("erase", minf(erased, drawn))
		node.set_instance_shader_parameter("opacity", fade)
	if done:
		_clear_burst()


## Stroke radii are tuned for a 2 m guardian; they grow with its height.
func _size() -> float:
	return height / 2.0


func _place(node: Node3D, stroke: Dictionary, q: float, radius: float, y: float) -> void:
	# Turning by yaw moves the arc angle by +yaw; the head sits at dir * span, so it leads.
	var yaw: float = stroke.angle + stroke.dir * stroke.spin * q
	node.transform = Transform3D(Basis.from_euler(stroke.tilt) * Basis(Vector3.UP, yaw).scaled(Vector3.ONE * radius), Vector3(0, y, 0))


## A ribbon on the unit circle around +Y spanning `span` radians (dir -1 runs the other way), `width`
## tall (relative to the radius). UV.x runs 0 (tail) to 1 (head), UV.y across.
func _stroke_node(span: float, width: float, dir: int) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in SEGMENTS + 1:
		var u := float(k) / SEGMENTS
		var a := dir * span * u
		var radial := Vector3(cos(a), 0.0, -sin(a))
		# Slight helix so a stroke climbs as it goes.
		var rise := width * 0.6 * u
		for side in 2:
			vertices.append(radial + Vector3(0, (float(side) - 0.5) * width + rise, 0))
			normals.append(radial)
			uvs.append(Vector2(u, float(side)))
		if k < SEGMENTS:
			var i := k * 2
			indices.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Strokes swing wide of their unit mesh: keep them from being culled.
	node.extra_cull_margin = 2.0
	add_child(node)
	return node
