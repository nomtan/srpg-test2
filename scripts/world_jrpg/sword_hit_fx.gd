extends Node3D
## Contact effect where a blow lands: a flash and jagged star burst (sword_hit_burst.gdshader) and a burst of sparks.
## With a hit-stop (`hold`), it plays up to the star fully open, freezes there with its sparks until the hit-stop
## ends, then finishes; it frees itself after LIFETIME plus the freeze.
const BURST_SHADER = preload("res://scripts/world_jrpg/sword_hit_burst.gdshader")
const LIFETIME := 0.2
# Effect time at which the star burst is fully open: where a hit-stop freezes it.
const HOLD_AT := 0.07
# Quad size; the shader keeps the effect within 1.6 m except the long diagonal points (its `extent`, 2.5).
const BURST_SIZE := 4.0
const SPARK_COLOR := Color(0.72, 0.84, 1.0)

## Hit-stop seconds from the moment of contact; set before adding the effect to the tree.
var hold := 0.0
## On-screen turn of the effect in degrees, counterclockwise; set before adding the effect to the tree.
var tilt_degrees := 0.0

func _ready() -> void:
	top_level = true
	var burst := MeshInstance3D.new()
	burst.name = "Burst"
	burst.mesh = QuadMesh.new()
	burst.scale = Vector3.ONE * BURST_SIZE
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = BURST_SHADER
	material.set_shader_parameter("seed", randf())
	material.set_shader_parameter("tilt", deg_to_rad(tilt_degrees))
	burst.material_override = material
	add_child(burst)
	var sparks := _make_sparks()
	add_child(sparks)
	var set_elapsed := func(value: float) -> void: material.set_shader_parameter("elapsed", value)
	var tween := create_tween()
	if hold > HOLD_AT:
		# Resumes when the hit-stop ends, in step with the attacker.
		tween.tween_method(set_elapsed, 0.0, HOLD_AT, HOLD_AT)
		tween.tween_callback(func() -> void: sparks.speed_scale = 0.0)
		tween.tween_interval(hold - HOLD_AT)
		tween.tween_callback(func() -> void: sparks.speed_scale = 1.0)
		tween.tween_method(set_elapsed, HOLD_AT, LIFETIME, LIFETIME - HOLD_AT)
	else:
		tween.tween_method(set_elapsed, 0.0, LIFETIME, LIFETIME)
	tween.tween_callback(queue_free)

func _make_sparks() -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	mesh.material = material
	sparks.mesh = mesh
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.amount = 18
	sparks.lifetime = LIFETIME
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 2.5
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -6.0, 0)
	sparks.damping_min = 6.0
	sparks.damping_max = 10.0
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, SPARK_COLOR)
	fade.set_color(1, Color(SPARK_COLOR, 0.0))
	sparks.color_ramp = fade
	sparks.emitting = true
	return sparks
