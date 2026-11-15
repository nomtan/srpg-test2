extends "res://scripts/world_jrpg/world.gd"
## LineupStageSample: a flat white stage for comparing characters side by side. JRPGWorldSample's
## explorer, camera, HUD, weather panel and input are reused; the terrain is a level white floor at
## y 0 with the biome debug grid (open_field_world.gd's CELL_SIZE cells, aligned to the world
## origin) drawn in grey, under a plain white background. No NPCs, encounters or obstacles: one
## explorer (switchable through character_roster) walks freely, and the scene's own children (e.g.
## character_lineup.gd) stand on the floor.

## Battle cells of the field world (open_field_world.gd CELL_SIZE), drawn as the grey grid.
const CELL_SIZE := 1.5
const FLOOR_COLOR := Color(1, 1, 1)
const GRID_COLOR := Color(0.62, 0.62, 0.62)
const BACKGROUND_COLOR := Color(1, 1, 1)
const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 floor_color : source_color;
uniform vec3 grid_color : source_color;
uniform float cell = 1.5;
uniform float line_px = 1.2;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz / cell;
	vec2 w = fwidth(p);
	vec2 d = abs(fract(p - 0.5) - 0.5) / max(w, vec2(1e-5));
	float line = 1.0 - clamp(min(d.x, d.y) - line_px * 0.5 + 0.5, 0.0, 1.0);
	// Fade far lines into the floor so the distance does not turn grey with moire.
	line *= 1.0 - smoothstep(0.35, 0.8, max(w.x, w.y));
	ALBEDO = mix(floor_color, grid_color, line);
}
"""


func _cache_heights() -> void:
	pass


func _height(_x: float, _z: float) -> float:
	return 0.0


func _expanded_height(_x: float, _z: float) -> float:
	return 0.0


func _surface(_x: float, _z: float) -> float:
	return 0.0


func _build_world() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = FLOOR_SHADER
	material.set_shader_parameter("floor_color", FLOOR_COLOR)
	material.set_shader_parameter("grid_color", GRID_COLOR)
	material.set_shader_parameter("cell", CELL_SIZE)
	var stage := MeshInstance3D.new()
	stage.name = "Floor"
	stage.mesh = floor_mesh
	stage.material_override = material
	stage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.position = Vector3(SIZE * 0.5, 0.0, SIZE * 0.5)
	add_child(stage)


func _setup_view() -> void:
	super._setup_view()
	# FieldWeather sets the light, ambient and fog colour, but never the background or fog switch.
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = BACKGROUND_COLOR
	world_environment.fog_enabled = false


func _spawn_characters() -> void:
	story = {}
	cleared = true
	player = Explorer.new()
	if player_model: player.model_scene = player_model
	# A roster scene starts the way switching to it shows it: turned to the explorer's axes, unlabelled.
	player.start_in_roster_layout = player.model_scene in character_roster
	player.use_3d = use_3d_player
	player.name = "Explorer"
	add_child(player)
	player.position = Vector3(player_spawn_position.x, 0.05, player_spawn_position.z)
	# Facing -Z, toward a row placed in front of the spawn, with the camera behind.
	player.world_facing = Vector3(0, 0, -1)
	yaw = 0.0
	pitch = 0.3
	distance = 9.0
	for index in character_roster.size():
		if character_roster[index] == player.model_scene:
			player_roster_index = index
	if character_text and player.model:
		character_text.text = "操作キャラ：" + player.model.display_name
	_sync_weapon_buttons()
	# world.gd's _process reads the marker only for encounters, which this stage has none of.
	encounter_marker = Node3D.new()
	encounter_marker.visible = false
	add_child(encounter_marker)
	encounter_position = Vector3(-1000, 0, -1000)


func _can_walk(p: Vector3, _from: Vector3) -> bool:
	return p.x >= 1 and p.z >= 1 and p.x < SIZE - 1 and p.z < SIZE - 1


func _region() -> String:
	return "比較ステージ"


func _process(delta: float) -> void:
	super._process(delta)
	if mode == "explore" and prompt_text:
		prompt_text.text = "目標 : 並んだキャラクターと見比べよう（升目は %.1f m）" % CELL_SIZE
