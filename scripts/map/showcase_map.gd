extends Node3D

## Phase16-Step5: 見本市シーン。全地形要素+装飾+ユニットを1枚の10x10ジオラマに
## 詰め込み、量産前の最終品質判定に使う。以後はビジュアル回帰確認用に固定する。
## テーマ/環境/カメラはPhase16AssetPreviewと同じ本番設定（theme_default.tres /
## battle_atmosphere.tres / CameraController）をそのまま使う。

const BATTLE_ENVIRONMENT: Environment = preload("res://assets/environment/battle_atmosphere.tres")
const ScreenshotCaptureScript := preload("res://scripts/debug/screenshot_capture.gd")

const MAP_SIZE := 10

# 3構図のプリセット。標準アングル（focus_offsetの向き）は維持し、
# 中心位置とズーム(size)だけ変える。
const COMPOSITIONS := {
	"standard": {"size": 18.0, "target": Vector3(5.0, 1.0, 4.5)},
	"overview": {"size": 26.0, "target": Vector3(5.0, 1.0, 4.5)},
	"closeup": {"size": 5.5, "target": Vector3(6.8, 1.5, 3.2)},
}

@export var visual_theme: MapVisualTheme = preload("res://assets/terrain/theme_default.tres")

var camera_controller: CameraController
var camera: Camera3D


func _ready() -> void:
	var renderer := VoxelMap.new()
	renderer.name = "MapRenderer"
	renderer.visual_theme = visual_theme
	add_child(renderer)
	renderer.build_from_map_data(_create_showcase_map())
	_create_units()
	_create_lighting_and_camera()
	_apply_composition(_composition_from_cmdline())
	var screenshot := ScreenshotCaptureScript.new()
	screenshot.name = "ScreenshotCapture"
	add_child(screenshot)


func _create_showcase_map() -> MapData:
	# カメラは概ね -x/+z 方向を奥にして見下ろす（standard構図の場合、画面手前
	# ≒ x大・z小）。地形は「奥に高台、その手前(x側)に水辺」の順に置き、
	# 高台自身の崖がカメラと水辺の間に入って死角を作らないようにする
	# （Phase16-Step4で見つかった「崖の死角」問題と同じ罠を避けるため）。
	var data := MapData.new()
	data.width = MAP_SIZE
	data.depth = MAP_SIZE
	for z in data.depth:
		for x in data.width:
			var cell := MapCellVisualData.new()
			cell.position = Vector2i(x, z)
			cell.height = 1
			cell.terrain = "grass"

			# 石の高台（x3-6, z2-5）。東端(x6)が3段の崖を見せる頂上で、
			# すぐ東の水辺に面する。
			if x >= 3 and x <= 6 and z >= 2 and z <= 5:
				cell.terrain = "stone_road"
				cell.height = 3 if x == 6 else 2

			# 水辺の入江（x7-8, z2-4）。高台の崖に接し、東側は草原と接する。
			if x >= 7 and x <= 8 and z >= 2 and z <= 4:
				cell.terrain = "water"
				cell.height = 0

			# 溶岩だまり（石地形の南に接する1x2、同じ高さでフラットに連結）。
			if x >= 3 and x <= 4 and z == 6:
				cell.terrain = "lava"
				cell.height = 2

			# 階段（高台への1段接続）。
			if x == 5 and z == 6:
				cell.terrain = "stair"
				cell.height = 2

			# 土の小道（草原を縦に横切る、幅1マス）。
			if x == 1 and z >= 1 and z <= 8:
				cell.terrain = "dirt"

			_add_showcase_props(cell)
			data.cells.append(cell)
	data.rebuild_lookup()
	return data


func _add_showcase_props(cell: MapCellVisualData) -> void:
	const GRASS_PATCH_CELLS := [
		Vector2i(0, 0), Vector2i(0, 5), Vector2i(2, 0), Vector2i(8, 7),
		Vector2i(9, 6), Vector2i(2, 8), Vector2i(6, 8),
	]
	const BROKEN_STONE_CELLS := [Vector2i(6, 2), Vector2i(3, 3), Vector2i(7, 5)]
	const FLAG_CELL := Vector2i(6, 4)

	var kind := ""
	if cell.position in GRASS_PATCH_CELLS: kind = "grass_patch"
	elif cell.position in BROKEN_STONE_CELLS: kind = "broken_stone"
	elif cell.position == FLAG_CELL: kind = "flag_placeholder"
	if kind.is_empty(): return

	var prop := MapDecorationData.new()
	prop.kind = kind
	prop.grid_position = cell.position
	prop.rotation_degrees = float((cell.position.x * 37 + cell.position.y * 19) % 360)
	cell.props.append(prop)


func _create_units() -> void:
	var units := Node3D.new()
	units.name = "Units"
	add_child(units)
	# 草原に2体（自軍）、高台に2体（敵軍）。「駒が乗った状態」の判定用。
	_spawn_showcase_unit(units, "showcase_ally_1", "Ally 1", Vector2i(0, 2), "player", 1)
	_spawn_showcase_unit(units, "showcase_ally_2", "Ally 2", Vector2i(2, 6), "player", 1)
	_spawn_showcase_unit(units, "showcase_enemy_1", "Enemy 1", Vector2i(4, 4), "enemy", 2)
	_spawn_showcase_unit(units, "showcase_enemy_2", "Enemy 2", Vector2i(6, 3), "enemy", 3)


func _spawn_showcase_unit(parent: Node3D, id: String, display_name: String, grid_pos: Vector2i, team: String, height: int) -> void:
	var unit := BattleUnit.new()
	unit.configure(id, display_name, grid_pos, team)
	unit.setup_visual()
	parent.add_child(unit)
	unit.position = Vector3(grid_pos.x + 0.5, float(height) + 0.05, grid_pos.y + 0.5)
	unit.face_toward(Vector2i(5, 5))


func _create_lighting_and_camera() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.environment = BATTLE_ENVIRONMENT
	add_child(environment_node)

	# Main.tscnのDirectionalLight3Dと同一値（Phase16-Step4で確定した本番値）。
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	light.light_color = Color(1, 0.949, 0.839, 1)
	light.light_energy = 1.3
	light.shadow_enabled = false
	light.shadow_opacity = 0.35
	light.shadow_bias = 0.05
	add_child(light)

	camera_controller = CameraController.new()
	camera_controller.name = "CameraController"
	add_child(camera_controller)
	camera = camera_controller.setup()
	camera.current = true


func _composition_from_cmdline() -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--composition="):
			var comp_name := arg.get_slice("=", 1)
			if comp_name in COMPOSITIONS: return comp_name
	return "standard"


func _apply_composition(comp_name: String) -> void:
	if not camera_controller or not camera: return
	var comp: Dictionary = COMPOSITIONS.get(comp_name, COMPOSITIONS["standard"])
	camera_controller.focus_target = comp.target
	camera.size = comp.size
	camera.position = camera_controller.focus_target + camera_controller.focus_offset
	camera.look_at_from_position(camera.position, camera_controller.focus_target, Vector3.UP)
	print("[ShowcaseMap] composition = ", comp_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_1: _apply_composition("standard")
			KEY_2: _apply_composition("overview")
			KEY_3: _apply_composition("closeup")
			KEY_Q:
				camera_controller.rotate_view(-1)
				return
			KEY_E:
				camera_controller.rotate_view(1)
				return
			_: return
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: camera_controller.zoom_camera(1.5)
			MOUSE_BUTTON_WHEEL_DOWN: camera_controller.zoom_camera(-1.5)
			_: return
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		camera_controller.pan(event.relative)
		get_viewport().set_input_as_handled()
