class_name HpGauge3D
extends MeshInstance3D
## A unit's HP gauge over its head (the SRPG grid view shows it in place of the name label).
## HP lost first shows as a pale trail that drains after a short pause.

const SHADER := preload("res://scripts/ui/hp_gauge_3d.gdshader")
const SIZE := Vector2(0.9, 0.1)
const ALLY_COLOR := Color("#5fd86a")
const ENEMY_COLOR := Color("#ef4b4b")
const TRAIL_DELAY := 0.35
const TRAIL_TIME := 0.45

var ratio := 1.0
var trail := 1.0
var _material := ShaderMaterial.new()
var _trail_tween: Tween


func configure(enemy: bool) -> void:
	var quad := QuadMesh.new()
	quad.size = SIZE
	mesh = quad
	_material.shader = SHADER
	_material.render_priority = 10
	_material.set_shader_parameter("fill_color", ENEMY_COLOR if enemy else ALLY_COLOR)
	_material.set_shader_parameter("aspect", SIZE.x / SIZE.y)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_ratio(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, ratio): return
	var lost := value < ratio
	ratio = value
	_material.set_shader_parameter("ratio", ratio)
	if _trail_tween: _trail_tween.kill()
	if not lost:
		_set_trail(ratio)
		return
	_trail_tween = create_tween()
	_trail_tween.tween_interval(TRAIL_DELAY)
	_trail_tween.tween_method(_set_trail, trail, ratio, TRAIL_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _set_trail(value: float) -> void:
	trail = value
	_material.set_shader_parameter("trail", trail)
