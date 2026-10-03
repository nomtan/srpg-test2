@tool
extends Node3D
## Standalone slash effect: a pre-shaped arc played from a SwordSlashProfile, never reading a weapon.
## play() places it once in the anchor's frame (character space); it stays there unless the profile follows.
## Open scenes/fx/sword_slash.tscn, pick a profile and tick Preview to tune it in the editor.
const SHADER = preload("res://scripts/world_jrpg/sword_slash.gdshader")
const SEGMENTS := 64
# Profile values passed straight to the generated material.
const UNIFORMS := ["trail_length", "thickness", "core_color", "glow_color", "fade_color", "intensity", "peak_flash",
	"afterglow_width", "afterglow_stretch", "afterglow_fade"]

signal finished

@export var profile: SwordSlashProfile:
	set(value):
		profile = value
		if is_node_ready(): _build()
## Loop the effect in the editor (and in game when nothing else plays it).
@export var preview := false

## Extra rate from the attack clip (its speed scale, so hit-stop freezes the arc too).
var time_scale := 1.0
var playing := false
var _time := 0.0
var _anchor: Node3D
var _stop_fade := 0.0
var _opacity := 1.0
var _arc: MeshInstance3D
var _material: Material

func _ready() -> void:
	top_level = true
	_arc = MeshInstance3D.new()
	_arc.name = "Arc"
	_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arc, false, INTERNAL_MODE_FRONT)
	_build()
	_arc.visible = false

## Start from the beginning; a replay discards the previous one. The arc is placed in anchor's frame
## (this node's own frame without one).
func play(anchor: Node3D = null) -> void:
	if profile == null: return
	_anchor = anchor
	if anchor: global_transform = anchor.global_transform
	_time = 0.0
	_stop_fade = 0.0
	_opacity = 1.0
	playing = true
	_arc.visible = true
	_update()

## End now, or fade out over fade seconds (an interrupted attack).
func stop(fade := 0.0) -> void:
	if not playing: return
	if fade > 0.0:
		_stop_fade = fade
		return
	playing = false
	_anchor = null
	_arc.visible = false
	finished.emit()

func _process(delta: float) -> void:
	if not playing:
		if preview and profile:
			# Re-read the profile each loop so inspector edits show up.
			_build()
			play()
		return
	if profile == null:
		stop()
		return
	if _anchor and profile.follow_character:
		if is_instance_valid(_anchor): global_transform = _anchor.global_transform
	_time += delta * time_scale * profile.speed
	if _stop_fade > 0.0:
		_opacity -= delta / _stop_fade
	if _time >= profile.swing_time + profile.afterglow_time or _opacity <= 0.0:
		_stop_fade = 0.0
		stop()
		return
	_update()

func _update() -> void:
	var total := maxf(profile.swing_time + profile.afterglow_time, 1e-4)
	var shader := _material as ShaderMaterial
	if shader == null: return
	shader.set_shader_parameter("progress", _time / total)
	shader.set_shader_parameter("peak", profile.swing_time / total)
	shader.set_shader_parameter("opacity", _opacity)

func _build() -> void:
	if _arc == null: return
	if profile == null:
		_arc.mesh = null
		return
	_arc.transform = profile.placement()
	_arc.mesh = profile.mesh if profile.mesh else _arc_mesh()
	if profile.material:
		_material = profile.material.duplicate()
	else:
		var shader := ShaderMaterial.new()
		shader.shader = SHADER
		for key: String in UNIFORMS:
			shader.set_shader_parameter(key, profile.get(key))
		_material = shader
	_material.render_priority = profile.render_priority
	_arc.material_override = _material
	_update()

# Flat band in the local XZ plane from radius - width out to radius, starting on +X and sweeping about +Y.
func _arc_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var inner := maxf(profile.radius - profile.width, 0.0)
	for index in SEGMENTS + 1:
		var along := float(index) / SEGMENTS
		var direction := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(profile.sweep_degrees) * along)
		vertices.append_array([direction * inner, direction * profile.radius])
		uvs.append_array([Vector2(along, 0.0), Vector2(along, 1.0)])
		if index < SEGMENTS:
			var base := index * 2
			indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
