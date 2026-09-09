extends Node
## Weather is independent of exploration/battle HUD visibility and combat state.
const Batch = preload("res://scripts/world_jrpg/voxel_batch.gd")
const SKY_SHADER = preload("res://scripts/world_jrpg/atmosphere.gdshader")
const PRECIP_SHADER = preload("res://scripts/world_jrpg/precipitation.gdshader")
const TIMES := ["朝", "昼", "夕方", "夜"]
const WEATHER := ["晴れ", "雨", "曇り", "雪"]
const PROFILES := [
	{"sun":"ffe4b5", "energy":0.9, "angle":Vector3(-20,-100,0), "ambient":"a8bed0", "fill":0.4, "top":"6f9cbd", "horizon":"efd8b3"},
	{"sun":"fff5dc", "energy":1.15, "angle":Vector3(-65,-45,0), "ambient":"bccddd", "fill":0.43, "top":"467da9", "horizon":"c7deea"},
	{"sun":"ffd19a", "energy":0.95, "angle":Vector3(-23,-55,0), "ambient":"aeb9c6", "fill":0.34, "top":"65788f", "horizon":"e9c19a"},
	{"sun":"b2c9f3", "energy":0.22, "angle":Vector3(-34,45,0), "ambient":"6b80aa", "fill":0.24, "top":"091326", "horizon":"27394e"}
]
var world: Node3D
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var particles: CPUParticles3D
var controls: CanvasLayer
var time_index := 2
var weather_index := 0
var time_buttons: Array[Button] = []
var weather_buttons: Array[Button] = []
var base_fog := 0.0018
var clock := 0.0

func setup(map: Node3D, light: DirectionalLight3D) -> void:
	world = map
	sun = light
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	world.world_environment.sky = sky
	particles = CPUParticles3D.new()
	particles.name = "RainAndSnow"
	particles.emitting = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(17, 10, 17)
	particles.direction = Vector3(0, -1, 0)
	particles.local_coords = false
	particles.preprocess = 2.0
	world.add_child(particles)
	_create_controls()
	apply_conditions(time_index, weather_index)

func _create_controls() -> void:
	controls = CanvasLayer.new()
	controls.name = "FieldConditionsUI"
	controls.layer = 10
	add_child(controls)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -224
	panel.offset_right = -20
	panel.offset_top = 24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.15, 0.93)
	style.border_color = Color("a99367")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	controls.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	for section in 2:
		var label := Label.new()
		label.text = "時間帯" if section == 0 else "天気"
		label.modulate = Color("ead4a8")
		box.add_child(label)
		var grid := GridContainer.new()
		grid.columns = 2
		box.add_child(grid)
		var group := ButtonGroup.new()
		for index in 4:
			var button := Button.new()
			button.text = TIMES[index] if section == 0 else WEATHER[index]
			button.toggle_mode = true
			button.button_group = group
			button.custom_minimum_size = Vector2(82, 34)
			button.focus_mode = Control.FOCUS_NONE
			grid.add_child(button)
			if section == 0:
				time_buttons.append(button)
				button.pressed.connect(func(): apply_conditions(index, weather_index))
			else:
				weather_buttons.append(button)
				button.pressed.connect(func(): apply_conditions(time_index, index))

func apply_conditions(time: int, weather: int) -> void:
	time_index = clampi(time, 0, 3)
	weather_index = clampi(weather, 0, 3)
	var p: Dictionary = PROFILES[time_index]
	var storm := weather_index != 0
	var night := time_index == 3
	sun.rotation_degrees = p.angle
	sun.light_color = Color(p.sun)
	sun.light_energy = float(p.energy) * (0.28 if storm else 1.0)
	var env: Environment = world.world_environment
	env.ambient_light_color = Color(p.ambient)
	env.ambient_light_energy = float(p.fill) * (0.85 if storm else 1.0)
	var top := Color(p.top)
	var horizon := Color(p.horizon)
	if storm:
		top = top.lerp(Color("536170") if not night else Color("182030"), 0.75)
		horizon = horizon.lerp(Color("9aa7ad") if not night else Color("30394c"), 0.75)
	sky_material.set_shader_parameter("zenith", top)
	sky_material.set_shader_parameter("horizon", horizon)
	sky_material.set_shader_parameter("cloud_lit", Color("7486a5") if night else Color(p.sun).lerp(Color.WHITE, 0.7))
	sky_material.set_shader_parameter("cloud_shade", Color("192438") if night else Color("626f7c"))
	sky_material.set_shader_parameter("sun_direction", sun.global_basis.z)
	sky_material.set_shader_parameter("coverage", [0.4, 0.95, 0.83, 0.9][weather_index])
	sky_material.set_shader_parameter("night", 1.0 if night else 0.0)
	base_fog = [0.0018, 0.009, 0.0045, 0.007][weather_index]
	env.fog_light_color = horizon
	env.fog_light_energy = 0.32 if night else 0.65
	# Keep distant terrain hazy without replacing the entire sky with fog color.
	env.fog_sky_affect = 0.3 if storm else 0.08
	Batch.field_conditions(1.0 if weather_index == 1 else 0.0, 0.8 if weather_index == 3 else 0.0, 1.0 if night else 0.0)
	particles.emitting = false
	particles.visible = weather_index in [1, 3]
	if weather_index in [1, 3]:
		var snow := weather_index == 3
		particles.amount = 1000 if snow else 1500
		particles.lifetime = 6.0 if snow else 2.0
		particles.initial_velocity_min = 1.0 if snow else 12.0
		particles.initial_velocity_max = 2.0 if snow else 18.0
		particles.gravity = Vector3(0.25, -0.35, 0.1) if snow else Vector3(-1, -10, 0)
		particles.spread = 20.0 if snow else 3.0
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.10, 0.10) if snow else Vector2(0.025, 0.8)
		var material := ShaderMaterial.new()
		material.shader = PRECIP_SHADER
		material.set_shader_parameter("tint", Color(0.9, 0.94, 1.0, 0.9) if snow else Color(0.65, 0.78, 0.91, 0.6))
		mesh.material = material
		particles.mesh = mesh
		particles.restart()
		particles.emitting = true
	for i in 4:
		time_buttons[i].set_pressed_no_signal(i == time_index)
		weather_buttons[i].set_pressed_no_signal(i == weather_index)
	_update_field()

func _update_field() -> void:
	if not world.camera: return
	world.world_environment.fog_density = base_fog * minf(1, 100.0 / world.distance) if world.mode != "battle" else base_fog
	var forward: Vector3 = -world.camera.global_basis.z
	forward.y = 0
	particles.global_position = world.camera.global_position + forward.normalized() * 12 + Vector3(0, 4, 0)
	particles.rotation.y = world.camera.rotation.y

func _process(delta: float) -> void:
	clock += delta
	sky_material.set_shader_parameter("wind_clock", clock)
	_update_field()
