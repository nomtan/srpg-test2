extends CanvasLayer
## SRPG battle screen (srpg_battle.gd): the turn order across the top, the phase / turn / victory
## panel and the camera angles at the top right, the command menu beside the acting unit, the
## acting ally's card at the bottom left, the targeted enemy's at the bottom right and the
## controls along the bottom. Parchment cards with navy headings and gold rims.

signal command_pressed(index: int)
signal angle_pressed(index: int)

const PARCHMENT := Color("#f4ecd6")
const PARCHMENT_DEEP := Color("#e6d8b4")
const GOLD := Color("#c19a4b")
const GOLD_LIGHT := Color("#f2d27a")
const NAVY := Color("#1b2a4e")
const INK := Color("#2b2216")
const ALLY := Color("#24508f")
const ENEMY := Color("#9a2323")
const HP_ALLY := Color("#4fcf5a")
const HP_ENEMY := Color("#e34545")
const MP := Color("#3f8de0")
## Camera angle buttons in map layout (srpg_quarter: 0 south-east, 1 north-east, 2 north-west,
## 3 south-west) with their keys.
const ANGLES := [[2, "北西", "3"], [1, "北東", "2"], [3, "南西", "4"], [0, "南東", "1"]]

var root: Control
var order_row: HBoxContainer
var phase_label: Label
var phase_band: PanelContainer
var turn_label: Label
var goal_label: Label
var angle_buttons: Dictionary = {}
var menu: PanelContainer
var menu_rows: Array[Button] = []
var ally_card: Dictionary
var enemy_card: Dictionary
var banner: PanelContainer
var banner_label: Label
var banner_tween: Tween


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_order()
	_build_phase()
	_build_menu()
	ally_card = _build_card(false)
	enemy_card = _build_card(true)
	_build_hints()
	_build_banner()


# --- Building ------------------------------------------------------------------

func _style(bg: Color, border := GOLD, width := 3, radius := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style

func _label(text: String, size: int, color := INK, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _bar(fill: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var back := _style(Color("#3a3a40"), Color("#20202a"), 2, height / 2)
	back.shadow_size = 0
	var front := _style(fill, fill.darkened(0.25), 1, height / 2)
	front.shadow_size = 0
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", front)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

func _ignore_mouse(node: Node) -> void:
	for child in node.find_children("*", "Control", true, false):
		if not child is Button: child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_order() -> void:
	order_row = HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 10)
	order_row.alignment = BoxContainer.ALIGNMENT_CENTER
	order_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	order_row.offset_top = 24
	order_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(order_row)

func _build_phase() -> void:
	var panel := PanelContainer.new()
	var style := _style(PARCHMENT)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -24
	panel.offset_top = 18
	panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	phase_band = PanelContainer.new()
	var band := _style(NAVY, GOLD, 0, 6)
	band.corner_radius_bottom_left = 0
	band.corner_radius_bottom_right = 0
	band.shadow_size = 0
	band.set_content_margin_all(8)
	phase_band.add_theme_stylebox_override("panel", band)
	column.add_child(phase_band)
	phase_label = _label("PLAYER TURN", 32, GOLD_LIGHT, 4)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_band.add_child(phase_label)
	turn_label = _label("ターン 1 / 12", 28)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(turn_label)
	var rule := ColorRect.new()
	rule.color = GOLD
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)
	goal_label = _label("勝利条件  ›  敵の全滅", 22)
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(goal_label)
	# Camera angles, laid out like the map; the lit one is the current view.
	var angles := HBoxContainer.new()
	angles.alignment = BoxContainer.ALIGNMENT_CENTER
	angles.add_theme_constant_override("separation", 12)
	column.add_child(angles)
	angles.add_child(_label("カメラ", 18))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	angles.add_child(grid)
	for angle in ANGLES:
		var button := Button.new()
		button.text = "%s %s" % [angle[2], angle[1]]
		button.custom_minimum_size = Vector2(96, 30)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func() -> void: angle_pressed.emit(angle[0]))
		grid.add_child(button)
		angle_buttons[angle[0]] = button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	column.add_child(spacer)
	_ignore_mouse(panel)

func _build_menu() -> void:
	menu = PanelContainer.new()
	var style := _style(PARCHMENT)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 30
	style.content_margin_bottom = 12
	menu.add_theme_stylebox_override("panel", style)
	menu.custom_minimum_size = Vector2(250, 0)
	menu.visible = false
	root.add_child(menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	menu.add_child(column)
	# The heading tab sits on the top rim.
	var tab := PanelContainer.new()
	var tab_style := _style(NAVY, GOLD, 2, 6)
	tab_style.content_margin_left = 22
	tab_style.content_margin_right = 22
	tab_style.content_margin_top = 2
	tab_style.content_margin_bottom = 2
	tab.add_theme_stylebox_override("panel", tab_style)
	tab.add_child(_label("コマンド", 18, Color.WHITE))
	tab.top_level = true
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.name = "Tab"
	menu.add_child(tab)

func set_commands(items: Array) -> void:
	var column := menu.get_child(0) as VBoxContainer
	for row in menu_rows: row.queue_free()
	menu_rows.clear()
	for index in items.size():
		var item: Dictionary = items[index]
		var row := Button.new()
		row.text = "  %s   %s" % [item.icon, item.label]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 46)
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override("font_size", 26)
		row.disabled = not item.enabled
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var flat := StyleBoxFlat.new()
			flat.bg_color = Color(0, 0, 0, 0)
			flat.set_corner_radius_all(6)
			row.add_theme_stylebox_override(state, flat)
		row.add_theme_color_override("font_color", INK)
		row.add_theme_color_override("font_hover_color", INK)
		row.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
		row.pressed.connect(func() -> void: command_pressed.emit(index))
		row.mouse_entered.connect(func() -> void:
			if not row.disabled: highlight_command(index))
		column.add_child(row)
		menu_rows.append(row)

## Lights row `index` like the mockup's selection: a navy bar with gold rim and white text.
func highlight_command(index: int) -> void:
	for i in menu_rows.size():
		var row := menu_rows[i]
		var lit := StyleBoxFlat.new()
		lit.set_corner_radius_all(6)
		if i == index:
			lit.bg_color = Color("#1f4fa8")
			lit.border_color = GOLD_LIGHT
			lit.set_border_width_all(2)
		else:
			lit.bg_color = Color(0, 0, 0, 0)
		for state in ["normal", "hover", "pressed"]:
			row.add_theme_stylebox_override(state, lit)
		var text := Color.WHITE if i == index else INK
		row.add_theme_color_override("font_color", text)
		row.add_theme_color_override("font_hover_color", text)
		row.add_theme_color_override("font_pressed_color", text)

## Shows the menu with its top-left corner near `at` (screen pixels), kept on screen.
func show_menu(at: Vector2) -> void:
	menu.visible = true
	menu.reset_size()
	var screen := root.get_viewport_rect().size
	var size := menu.get_combined_minimum_size()
	menu.position = Vector2(clampf(at.x, 16, screen.x - size.x - 16), clampf(at.y, 60, screen.y - size.y - 270))
	var tab := menu.get_node("Tab") as Control
	tab.reset_size()
	tab.global_position = menu.global_position + Vector2((size.x - tab.get_combined_minimum_size().x) * 0.5, -14)

func hide_menu() -> void:
	menu.visible = false

## A unit card: portrait, side tag, name and level, HP and MP gauges, and a footer row.
func _build_card(enemy: bool) -> Dictionary:
	var panel := PanelContainer.new()
	var style := _style(PARCHMENT)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT if enemy else Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if enemy else Control.GROW_DIRECTION_END
	panel.offset_bottom = -72
	if enemy: panel.offset_right = -24
	else: panel.offset_left = 24
	panel.visible = false
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var frame := PanelContainer.new()
	var frame_style := _style(PARCHMENT_DEEP, ENEMY if enemy else ALLY, 3, 6)
	frame_style.shadow_size = 0
	frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(frame)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(180, 180)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var tag_holder := HBoxContainer.new()
	column.add_child(tag_holder)
	var tag := PanelContainer.new()
	var tag_style := _style(ENEMY if enemy else ALLY, GOLD, 1, 4)
	tag_style.shadow_size = 0
	tag_style.content_margin_left = 12
	tag_style.content_margin_right = 12
	tag.add_theme_stylebox_override("panel", tag_style)
	var job := _label("", 18, Color.WHITE)
	tag.add_child(job)
	tag_holder.add_child(tag)
	var title := HBoxContainer.new()
	column.add_child(title)
	var name_label := _label("", 34)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	var level := _label("", 28)
	title.add_child(level)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	column.add_child(hp_row)
	hp_row.add_child(_label("HP", 22))
	var hp_bar := _bar(HP_ENEMY if enemy else HP_ALLY, 18)
	hp_row.add_child(hp_bar)
	var hp_text := _label("", 26)
	hp_text.custom_minimum_size = Vector2(130, 0)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_row.add_child(hp_text)
	var mp_row := HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 10)
	column.add_child(mp_row)
	mp_row.add_child(_label("MP", 22))
	var mp_bar := _bar(MP, 18)
	mp_row.add_child(mp_bar)
	var mp_text := _label("", 26)
	mp_text.custom_minimum_size = Vector2(130, 0)
	mp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mp_row.add_child(mp_text)
	var footer := _label("", 20)
	column.add_child(footer)
	_ignore_mouse(panel)
	return {"panel": panel, "portrait": portrait, "job": job, "name": name_label, "level": level,
		"hp_bar": hp_bar, "hp_text": hp_text, "mp_bar": mp_bar, "mp_text": mp_text, "footer": footer}

func _build_hints() -> void:
	var strip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(NAVY, 0.92)
	style.border_color = GOLD
	style.border_width_top = 2
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	strip.add_theme_stylebox_override("panel", style)
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(strip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 22)
	strip.add_child(row)
	for hint in [["Enter / Ⓐ", "決定"], ["Esc / Ⓑ", "キャンセル"], ["Q・E / Ⓡ←→", "カメラ回転"], ["R・F / Ⓡ↑↓", "カメラの高さ"], ["1-4", "視点切替"],
			["ホイール / LR", "カメラズーム"], ["Tab / Ⓧ", "危険範囲の表示"], ["T / ≡", "ターン終了"], ["F4", "探索に戻る"]]:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		var key := PanelContainer.new()
		var key_style := _style(Color("#f0f0f0"), Color("#9aa3b5"), 1, 10)
		key_style.shadow_size = 0
		key_style.content_margin_left = 8
		key_style.content_margin_right = 8
		key.add_theme_stylebox_override("panel", key_style)
		key.add_child(_label(hint[0], 16, NAVY))
		pair.add_child(key)
		pair.add_child(_label(hint[1], 20, Color.WHITE))
		row.add_child(pair)
	_ignore_mouse(strip)

func _build_banner() -> void:
	banner = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(NAVY, 0.85)
	style.border_color = GOLD
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	banner.add_theme_stylebox_override("panel", style)
	banner.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	banner_label = _label("", 64, GOLD_LIGHT, 8)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)


# --- Updating ------------------------------------------------------------------

func set_phase(enemy_phase: bool, turn: int, limit: int) -> void:
	phase_label.text = "ENEMY TURN" if enemy_phase else "PLAYER TURN"
	(phase_band.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color("#5a1620") if enemy_phase else NAVY
	turn_label.text = "ターン  %d / %d" % [turn, limit]

func set_angle(index: int) -> void:
	for key: int in angle_buttons:
		var button: Button = angle_buttons[key]
		var lit := key == index
		var style := _style(NAVY if lit else PARCHMENT_DEEP, GOLD if lit else Color("#b9a77a"), 2, 5)
		style.shadow_size = 0
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, style)
		var text := GOLD_LIGHT if lit else INK
		button.add_theme_color_override("font_color", text)
		button.add_theme_color_override("font_hover_color", text)
		button.add_theme_color_override("font_pressed_color", text)

## The turn order: each unit's portrait framed in its side's color with an HP bar under it;
## the acting unit's frame is gold, units done for the turn dim and fallen ones gray out.
func set_order(units: Array, active) -> void:
	for child in order_row.get_children(): child.free()
	for unit in units:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame := PanelContainer.new()
		var lit: bool = unit == active
		var style := _style(PARCHMENT_DEEP, GOLD_LIGHT if lit else (ENEMY if unit.enemy else ALLY), 4 if lit else 3, 6)
		style.set_content_margin_all(0)
		frame.add_theme_stylebox_override("panel", style)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var portrait := TextureRect.new()
		portrait.texture = unit.portrait
		var side := 86 if lit else 72
		portrait.custom_minimum_size = Vector2(side, side)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(portrait)
		column.add_child(frame)
		var bar := _bar(HP_ENEMY if unit.enemy else HP_ALLY, 10)
		bar.max_value = unit.max_hp
		bar.value = unit.hp
		column.add_child(bar)
		if not unit.alive(): column.modulate = Color(0.35, 0.35, 0.35, 0.8)
		elif unit.done and not lit: column.modulate = Color(0.75, 0.75, 0.75)
		column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		order_row.add_child(column)

## Fills the left (ally) or right (enemy) card from `unit`, or hides it for null.
func show_unit(enemy_side: bool, unit) -> void:
	var card := enemy_card if enemy_side else ally_card
	card.panel.visible = unit != null
	if unit == null: return
	card.portrait.texture = unit.portrait
	card.job.text = "◆ " + unit.job
	card.name.text = unit.name
	card.level.text = "Lv. %d" % unit.level
	card.hp_bar.max_value = unit.max_hp
	card.hp_bar.value = unit.hp
	card.hp_text.text = "%d / %d" % [unit.hp, unit.max_hp]
	card.mp_bar.max_value = maxi(unit.max_mp, 1)
	card.mp_bar.value = unit.mp
	card.mp_text.text = "%d / %d" % [unit.mp, unit.max_mp]
	if unit.enemy:
		card.footer.text = "属性  %s　　移動 %dマス　　跳躍 %d" % [unit.element, unit.move, unit.jump]
	else:
		card.footer.text = "移動 %dマス　　跳躍 %d　　攻撃力 %d" % [unit.move, unit.jump, unit.power]

## A heading across the middle of the screen that fades in and out.
func show_banner(text: String, color := GOLD_LIGHT, hold := 0.9) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	if banner_tween: banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_property(banner, "modulate:a", 1.0, 0.2)
	if hold >= 0.0:
		banner_tween.tween_interval(hold)
		banner_tween.tween_property(banner, "modulate:a", 0.0, 0.3)
