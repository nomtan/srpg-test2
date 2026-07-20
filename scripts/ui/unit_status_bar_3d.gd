class_name UnitStatusBar3D
extends Sprite3D

const VIEWPORT_SIZE := Vector2i(128, 19)
const BAR_LEFT := 2.0
const BAR_WIDTH := 124.0
const HP_BAR_HEIGHT := 7.0
const AP_BAR_HEIGHT := 5.0
const ALLY_HP_COLOR := Color("#278cff")
const ALLY_AP_COLOR := Color("#37cfe1")
const ENEMY_HP_COLOR := Color("#ef4b4b")
const ENEMY_AP_COLOR := Color("#f29a3f")
const BACKGROUND_COLOR := Color(0.025, 0.03, 0.045, 0.95)

var hp_fill: ColorRect
var ap_fill: ColorRect


func configure(unit_team: String) -> void:
	name = "StatusBars"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = false
	no_depth_test = true
	pixel_size = 0.009
	double_sided = true
	render_priority = 10
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

	var viewport := SubViewport.new()
	viewport.name = "StatusBarViewport"
	viewport.size = VIEWPORT_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)

	var hp_background := _create_bar_background(root, 2.0, HP_BAR_HEIGHT)
	hp_fill = _create_bar_fill(hp_background, ALLY_HP_COLOR if unit_team == "player" else ENEMY_HP_COLOR)

	var ap_background := _create_bar_background(root, 12.0, AP_BAR_HEIGHT)
	ap_fill = _create_bar_fill(ap_background, ALLY_AP_COLOR if unit_team == "player" else ENEMY_AP_COLOR)

	texture = viewport.get_texture()


func update_values(hp: int, max_hp: int, ap: int, max_ap: int) -> void:
	var hp_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 0.0
	var ap_ratio := clampf(float(ap) / float(max_ap), 0.0, 1.0) if max_ap > 0 else 0.0
	if hp_fill:
		hp_fill.size = Vector2(BAR_WIDTH * hp_ratio, HP_BAR_HEIGHT)
	if ap_fill:
		ap_fill.size = Vector2(BAR_WIDTH * ap_ratio, AP_BAR_HEIGHT)


func _create_bar_background(parent: Control, y: float, height: float) -> ColorRect:
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.position = Vector2(BAR_LEFT - 1.0, y - 1.0)
	background.size = Vector2(BAR_WIDTH + 2.0, height + 2.0)
	parent.add_child(background)
	return background


func _create_bar_fill(parent: Control, color: Color) -> ColorRect:
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2.ONE
	fill.size = Vector2(BAR_WIDTH, parent.size.y - 2.0)
	parent.add_child(fill)
	return fill
