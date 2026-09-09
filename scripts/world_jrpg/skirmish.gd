extends Node3D
## Tactical overlay on the live exploration terrain; the explorer node is reused.
const Actor = preload("res://scripts/world_jrpg/pixel_actor.gd")
const N := 11
const CELL := 1.0
var origin := Vector3.ZERO
var world: Node3D
var adjacency: Dictionary = {}
var tiles: Dictionary = {}
var animation_time := 0.12
var camera: Camera3D
var finished: Callable
var hero: Node3D
var hero_cell := Vector2i(3, 5)
var hp: int:
	get: return hero_data.hp if hero_data else 60
	set(value):
		if hero_data: hero_data.hp = value
var hero_data: BattleUnit
var manager: UnitManager
var turn_manager: TurnManager
var combat_grid: GridSystem
var attacks: AttackSystem
var skills: SkillSystem
var skill_db: SkillDatabase
var stage := "menu"
var turn_start := Vector2i.ZERO
var pending_target := Vector2i(-1, -1)
var selected_skill: SkillData
var buttons: Dictionary = {}
var action_box: VBoxContainer
var cursor_cell := Vector2i(3, 5)
var camera_focus := Vector3.ZERO
var camera_yaw := 0.4
var camera_pitch := 1.0
var camera_distance := 27.0
var enemies: Array[Dictionary] = []
var moved := false
var attacked := false
var busy := false
var resolved := false
var hud: CanvasLayer
var status: Label
var _pad := GamepadInput.new()
var end_button: Button
var exit_button: Button
var turn := 1

func begin(map: Node3D, explorer: Node3D, view: Camera3D, callback: Callable) -> void:
	world = map
	hero = explorer
	camera = view
	finished = callback
	# The grid is anchored to the exact exploration position. The hero is reused.
	origin = hero.position - Vector3(hero_cell.x, 0, hero_cell.y)
	for z in N:
		for x in N:
			var cell := Vector2i(x, z)
			var point := _point(cell)
			if not world._can_walk(point, point): continue
			var tile := MeshInstance3D.new()
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(0.91, 0.91)
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material = mat
			tile.mesh = mesh
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tile.position = point + Vector3(0, 0.015, 0)
			add_child(tile)
			tiles[cell] = tile
	for cell: Vector2i in tiles:
		adjacency[cell] = []
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if tiles.has(next) and _terrain_edge(cell, next): adjacency[cell].append(next)
	var connected := _search(hero_cell, N * N, false)
	for desired in [Vector2i(7, 4), Vector2i(7, 6)]:
		var chosen := Vector2i(-1, -1)
		var score := 10000
		for cell: Vector2i in connected:
			if connected[cell].cost < 4 or connected[cell].cost > 8 or _occupied(cell): continue
			if _distance(cell, desired) < score:
				chosen = cell
				score = _distance(cell, desired)
		if chosen.x < 0: continue
		var actor := Actor.new()
		actor.palette_name = "enemy"
		add_child(actor)
		actor.position = _point(chosen)
		var label := Label3D.new()
		label.text = "魔物"
		label.position.y = 2.8
		label.font_size = 26
		label.pixel_size = 0.009
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("efd0a0")
		actor.add_child(label)
		enemies.append({"actor": actor, "cell": chosen, "hp": 24, "label": label})
	camera_focus = _point(Vector2i(5, 5))
	_update_camera()
	_setup_rules()
	_setup_hud()
	turn_manager.actor_ready.connect(_actor_ready)
	turn_manager.start_battle()

func _point(cell: Vector2i) -> Vector3:
	var x := origin.x + cell.x * CELL
	var z := origin.z + cell.y * CELL
	return Vector3(x, world._surface(x, z) + 0.05, z)

func _distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _occupied(cell: Vector2i) -> bool:
	for enemy in enemies:
		if enemy.hp > 0 and enemy.cell == cell: return true
	return false

func _inside(cell: Vector2i) -> bool:
	return tiles.has(cell)

func _terrain_edge(a: Vector2i, b: Vector2i) -> bool:
	var from := _point(a)
	for i in range(1, 9):
		var point := _point(a).lerp(_point(b), float(i) / 8.0)
		point.y = world._surface(point.x, point.z) + 0.05
		if not world._can_walk(point, from): return false
		from = point
	return true

func _search(start: Vector2i, budget: int, occupied: bool = true) -> Dictionary:
	var found := {start: {"cost": 0, "previous": start}}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var here: Vector2i = frontier.pop_front()
		if found[here].cost >= budget: continue
		for next: Vector2i in adjacency.get(here, []):
			if found.has(next): continue
			if occupied and (_occupied(next) or (next == hero_cell and start != hero_cell)): continue
			found[next] = {"cost": found[here].cost + 1, "previous": here}
			frontier.append(next)
	return found

func _reachable() -> Dictionary:
	return _search(hero_cell, hero_data.move_range if hero_data else 4)

func _can_attack(a: Vector2i, b: Vector2i) -> bool:
	return b in adjacency.get(a, [])

func _route(found: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	var cell := target
	while found[cell].previous != cell:
		route.push_front(cell)
		cell = found[cell].previous
	return route

func _walk(actor: Node3D, route: Array[Vector2i]) -> void:
	actor.walking = true
	actor.running = false
	for cell in route:
		var target := _point(cell)
		var direction := target - actor.position
		actor.world_facing = Vector3(direction.x, 0, direction.z).normalized()
		actor.facing = (1 if direction.x > 0 else 2) if absf(direction.x) > absf(direction.z) else (0 if direction.z > 0 else 3)
		if animation_time > 0:
			var tween := create_tween()
			# Follow the sampled surface through each voxel step, never through cliffs.
			var start := actor.position
			tween.tween_method(func(t: float):
				var p := start.lerp(target, t)
				actor.position = Vector3(p.x, world._surface(p.x, p.z) + 0.05, p.z)
			, 0.0, 1.0, animation_time)
			await tween.finished
		else: actor.position = target
	actor.walking = false

func _pick_cell(screen: Vector2) -> Vector2i:
	# Intersect the actual height of each cell, including bridges and slopes.
	var ray := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var nearest := INF
	var result := Vector2i(-1, -1)
	for cell: Vector2i in tiles:
		var p := _point(cell)
		var hit: Variant = Plane(Vector3.UP, p.y + 0.015).intersects_ray(ray, direction)
		if hit == null: continue
		if absf(hit.x - p.x) > 0.5 or absf(hit.z - p.z) > 0.5: continue
		var d := ray.distance_squared_to(hit)
		if d < nearest:
			nearest = d
			result = cell
	# Clicking the visible sprite also selects that enemy's ground cell.
	for enemy in enemies:
		if enemy.hp > 0 and camera.unproject_position(enemy.actor.position + Vector3(0, 1.0, 0)).distance_to(screen) < 18:
			return enemy.cell
	return result

func _setup_rules() -> void:
	# Use the production CT, combat preview/damage and skill implementations.
	combat_grid = GridSystem.new()
	add_child(combat_grid)
	for z in N:
		for x in N:
			var cell := Vector2i(x, z)
			var p := _point(cell)
			combat_grid.cells[cell] = GridCell.new(x, z, roundi(p.y), "grass", tiles.has(cell))
			combat_grid.cells[cell].blocks_line_of_sight = not tiles.has(cell)
	manager = UnitManager.new()
	manager.grid = combat_grid
	add_child(manager)
	hero_data = _data_unit("explorer", "旅人", "player", hero_cell, 60, 12, 4, 12)
	hero_data.max_ap = 30
	hero_data.ap = 30
	for i in enemies.size():
		var enemy: Dictionary = enemies[i]
		enemy.data = _data_unit("enemy_%d" % i, "魔物%d" % (i + 1), "enemy", enemy.cell, 24, 9, 4, 8 + i * 2)
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	turn_manager.setup(manager)
	var los := LineOfSight.new()
	add_child(los)
	los.setup(combat_grid)
	attacks = AttackSystem.new()
	add_child(attacks)
	attacks.setup(combat_grid, los)
	var elements := ElementSystem.new()
	add_child(elements)
	skills = SkillSystem.new()
	add_child(skills)
	skills.setup(combat_grid, manager, attacks, elements, los)
	skill_db = SkillDatabase.new()
	add_child(skill_db)
	skill_db.configure_phase_11_5_scaling()
	_sync_units()

func _data_unit(id: String, title: String, team: String, cell: Vector2i, health: int, power: int, defense: int, speed: int) -> BattleUnit:
	var data := BattleUnit.new()
	data.configure(id, title, cell, team)
	data.set_combat_stats(health, power, defense, 95, 5)
	data.agility = speed
	manager.add_child(data)
	manager.units.append(data)
	return data

func _sync_units() -> void:
	for cell: GridCell in combat_grid.cells.values(): cell.occupied_unit = null
	hero_data.grid_x = hero_cell.x
	hero_data.grid_z = hero_cell.y
	hero.facing = [3, 1, 0, 2][int(hero_data.facing)]
	hero.world_facing = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][int(hero_data.facing)]
	combat_grid.set_occupied_unit(hero_cell, hero_data)
	for enemy in enemies:
		var data: BattleUnit = enemy.data
		data.grid_x = enemy.cell.x
		data.grid_z = enemy.cell.y
		enemy.hp = data.hp
		enemy.actor.facing = [3, 1, 0, 2][int(data.facing)]
		enemy.actor.visible = data.is_alive()
		if data.is_alive(): combat_grid.set_occupied_unit(enemy.cell, data)
		enemy.label.text = "%s  %d / %d" % [data.unit_name, data.hp, data.max_hp]

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.13, 0.95)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 5)
	panel.add_child(action_box)
	status = Label.new()
	status.custom_minimum_size.x = 292
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 16)
	action_box.add_child(status)
	for spec in [["move", "移動"], ["attack", "攻撃"], ["skill", "スキル"], ["wait", "待機 / 行動終了"], ["confirm", "実行する"], ["cancel", "キャンセル [Esc]"], ["north", "北を向く"], ["east", "東を向く"], ["south", "南を向く"], ["west", "西を向く"], ["power_slash", "強斬り  AP 5"], ["guard_stance", "ガードスタンス  AP 6"], ["retreat", "退却"]]:
		var button := Button.new()
		button.text = spec[1]
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 30
		button.pressed.connect(_command.bind(spec[0]))
		action_box.add_child(button)
		buttons[spec[0]] = button
	end_button = buttons.wait
	exit_button = buttons.retreat

func _actor_ready(actor: BattleUnit) -> void:
	if resolved: return
	turn = turn_manager.turn_count
	if actor == hero_data:
		busy = false
		moved = false
		attacked = false
		turn_start = hero_cell
		cursor_cell = hero_cell
		stage = "menu"
		_refresh("行動を選択してください。")
	else:
		busy = true
		stage = "enemy"
		_refresh("%s の手番" % actor.unit_name)
		call_deferred("_act_enemy", actor)

func _refresh(message: String) -> void:
	if not status: return
	_sync_units()
	var names: PackedStringArray = []
	for unit in turn_manager.estimate_turn_order(4): names.append(unit.unit_name)
	var current := turn_manager.current_actor.unit_name if turn_manager.current_actor else "—"
	status.text = "街道の襲撃 / CT %d\n手番：%s\n次：%s\nHP %d / 60　AP %d / 30\n移動 %s　行動 %s\n\n%s\n\n矢印 / 中ドラッグ：カメラ移動\nQ/E・右ドラッグ：回転\nホイール：距離　R：旅人へ\nWASD：マス選択　Enter：決定\n" % [turn, current, " → ".join(names), hp, hero_data.ap, "済" if moved else "未", "済" if attacked else "未", message]
	status.text += "左スティック：選択　右：カメラ移動\nA：決定　B：戻る　Y：待機\nLB/RB：回転　LT/RT：距離\n右押込：旅人へ\n"
	for key: String in buttons:
		var show_button := (stage == "menu" and key in ["move", "attack", "skill", "wait", "cancel", "retreat"]) or (stage == "confirm" and key in ["confirm", "cancel"]) or (stage in ["move", "attack", "skill_target"] and key == "cancel") or (stage == "skills" and key in ["power_slash", "guard_stance", "cancel"]) or (stage == "facing" and key in ["north", "east", "south", "west"])
		buttons[key].visible = show_button and not busy
		buttons[key].disabled = busy or resolved
	buttons.move.disabled = moved and attacked
	buttons.attack.disabled = attacked
	buttons.skill.disabled = attacked
	buttons.power_slash.disabled = hero_data.ap < 5
	buttons.guard_stance.disabled = hero_data.ap < 6
	var focused := get_viewport().gui_get_focus_owner()
	if stage in ["menu", "skills", "facing", "confirm"] and not busy:
		if focused == null or not focused.is_visible_in_tree() or (focused is BaseButton and focused.disabled):
			for button: Button in buttons.values():
				if button.visible and not button.disabled:
					button.grab_focus()
					break
	elif focused != null:
		focused.release_focus()
	var reachable := _search(turn_start if moved and not attacked else hero_cell, hero_data.move_range)
	for cell: Vector2i in tiles:
		var color := Color(0.7, 0.8, 0.8, 0.03)
		if stage == "move" and reachable.has(cell): color = Color(0.22, 0.72, 0.9, 0.35)
		if stage == "attack" and _can_attack(hero_cell, cell): color = Color(0.95, 0.35, 0.2, 0.32)
		if stage == "skill_target" and _distance(cell, hero_cell) <= selected_skill.max_range: color = Color(0.7, 0.45, 0.95, 0.3)
		if _occupied(cell): color = Color(0.85, 0.3, 0.18, 0.3)
		if cell == hero_cell: color = Color(0.95, 0.8, 0.3, 0.35)
		if cell == cursor_cell: color.a = maxf(color.a, 0.5)
		tiles[cell].mesh.material.albedo_color = color

func _command(command: String) -> void:
	if busy or resolved or not turn_manager.is_player_turn(): return
	match command:
		"move":
			if moved and attacked: return
			stage = "move"
			_refresh("移動先を選択。行動前なら移動を取り消せます。")
		"attack":
			if attacked: return
			selected_skill = null
			stage = "attack"
			_refresh("攻撃する相手を選択してください。")
		"skill":
			if attacked: return
			stage = "skills"
			_refresh("スキルを選択してください。")
		"power_slash", "guard_stance":
			if attacked: return
			selected_skill = skill_db.get_skill(command)
			if not skills.can_use_skill(hero_data, selected_skill): return
			stage = "skill_target"
			if command == "guard_stance": _preview(hero_cell)
			else: _refresh("スキルを使う相手を選択してください。")
		"wait":
			stage = "facing"
			_refresh("終了時の向きを選択してください。待機はCTを20残します。")
		"confirm": await _execute_pending()
		"cancel": await _cancel()
		"north", "east", "south", "west":
			if stage != "facing": return
			var direction := ["north", "east", "south", "west"].find(command)
			hero_data.set_facing(direction as BattleUnit.FacingDirection)
			hero.facing = [3, 1, 0, 2][direction]
			hero.world_facing = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][direction]
			busy = true
			stage = "resolving"
			_refresh("次の手番へ…")
			turn_manager.finish_actor_turn(hero_data, not attacked)
		"retreat": _complete(false)

func _select(cell: Vector2i) -> void:
	if busy or resolved or not turn_manager.is_player_turn() or not _inside(cell): return
	cursor_cell = cell
	if stage == "move":
		var start := turn_start if moved and not attacked else hero_cell
		var found := _search(start, hero_data.move_range)
		if not found.has(cell) or _occupied(cell): return
		busy = true
		_refresh("移動中…")
		if moved and not attacked:
			var back := _search(hero_cell, N * N)
			await _walk(hero, _route(back, turn_start))
		await _walk(hero, _route(found, cell))
		hero_cell = cell
		moved = cell != turn_start
		hero_data.has_moved = moved
		busy = false
		stage = "facing" if attacked else "menu"
		_refresh("移動しました。行動を選択してください。")
	elif stage in ["attack", "skill_target"]:
		_preview(cell)
	elif stage == "menu" and cell == hero_cell:
		_refresh("行動を選択してください。")

func _target_at(cell: Vector2i) -> BattleUnit:
	return manager.unit_at(cell)

func _preview(cell: Vector2i) -> void:
	_sync_units()
	var target := _target_at(cell)
	if selected_skill:
		if not skills.can_use_skill(hero_data, selected_skill) or not skills.can_target_skill(hero_data, selected_skill, cell): return
		if selected_skill.max_range == 1 and not _can_attack(hero_cell, cell): return
		var preview := skills.calculate_preview(hero_data, selected_skill, cell)
		pending_target = cell
		stage = "confirm"
		_refresh("%s：予測 %d / 命中 %d%%\nAP %d 消費。実行しますか？" % [selected_skill.skill_name, preview.value, preview.hit_rate, selected_skill.ap_cost])
	elif target and _can_attack(hero_cell, cell) and attacks.can_attack(hero_data, target):
		var preview := attacks.get_battle_preview(hero_data, target)
		pending_target = cell
		stage = "confirm"
		_refresh("予測ダメージ %d / 命中 %d%%\n%s / 高低差 %d\n実行しますか？" % [preview.damage, preview.hit_rate, preview.direction, preview.height_diff])

func _execute_pending() -> void:
	if stage != "confirm" or attacked: return
	busy = true
	_refresh("行動中…")
	var message := ""
	if selected_skill:
		if selected_skill.target_type == SkillData.TargetType.ENEMY: hero_data.face_toward(pending_target)
		var result := skills.execute_skill(hero_data, selected_skill, pending_target)
		if not result.get("success", false):
			busy = false
			stage = "menu"
			_refresh("スキルを使用できません。")
			return
		message = selected_skill.skill_name + " を使用した。"
	else:
		var result := await attacks.execute_attack(hero_data, _target_at(pending_target))
		message = "%d ダメージ" % int(result.damage) if result.hit else "Miss"
	attacked = true
	hero_data.has_used_action = true
	_sync_units()
	if manager.are_all_enemies_defeated():
		_complete(true)
		return
	busy = false
	stage = "facing" if moved else "menu"
	_refresh(message)

func _cancel() -> void:
	if stage == "menu" and moved and not attacked:
		busy = true
		await _walk(hero, _route(_search(hero_cell, N * N), turn_start))
		hero_cell = turn_start
		moved = false
		hero_data.has_moved = false
		busy = false
	stage = "menu"
	selected_skill = null
	_refresh("行動を選択してください。")

func _act_enemy(actor: BattleUnit) -> void:
	if resolved: return
	var enemy: Dictionary = {}
	for entry in enemies:
		if entry.data == actor: enemy = entry
	if enemy.is_empty(): return
	await get_tree().create_timer(0.3).timeout
	if resolved: return
	var found := _search(enemy.cell, N * N)
	var best: Vector2i = enemy.cell
	var best_score := 10000
	for cell: Vector2i in found:
		var score := _distance(cell, hero_cell) * 100 + int(found[cell].cost)
		if _can_attack(cell, hero_cell): score = int(found[cell].cost)
		if score < best_score:
			best = cell
			best_score = score
	var full_route := _route(found, best)
	var route: Array[Vector2i] = []
	for i in mini(actor.move_range, full_route.size()): route.append(full_route[i])
	await _walk(enemy.actor, route)
	if not route.is_empty(): enemy.cell = route.back()
	_sync_units()
	if _can_attack(enemy.cell, hero_cell): await attacks.execute_attack(actor, hero_data)
	if not hero_data.is_alive():
		_complete(false)
		return
	_refresh("敵の行動終了")
	turn_manager.finish_actor_turn(actor, false)

func _complete(won: bool) -> void:
	if resolved: return
	resolved = true
	turn_manager.stop_battle()
	finished.call(won)

func _update_camera() -> void:
	camera.position = camera_focus + Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera.position.y = maxf(camera.position.y, world._surface(camera.position.x, camera.position.z) + 2.0)
	camera.look_at(camera_focus)

func _pan_camera(motion: Vector2, delta: float) -> void:
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var back := Vector3(sin(camera_yaw), 0, cos(camera_yaw))
	camera_focus += (right * motion.x + back * motion.y) * delta * camera_distance * 0.6
	camera_focus.x = clampf(camera_focus.x, origin.x - 20, origin.x + N + 20)
	camera_focus.z = clampf(camera_focus.z, origin.z - 20, origin.z + N + 20)
	_update_camera()

func _process(delta: float) -> void:
	if not camera or resolved: return
	var motion := Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	motion = (motion + GamepadInput.stick(true)).limit_length()
	if not motion.is_zero_approx(): _pan_camera(motion, delta)
	var zoom := GamepadInput.zoom()
	if not is_zero_approx(zoom):
		camera_distance = clampf(camera_distance * exp(-zoom * delta), 12, 65)
		_update_camera()
	var movement := _pad.step(delta, not busy and stage in ["move", "attack", "skill_target"])
	if movement != Vector2i.ZERO:
		cursor_cell = (cursor_cell + movement).clamp(Vector2i.ZERO, Vector2i(N - 1, N - 1))
		_refresh("左スティック：マス選択　A / ×：決定")

func _unhandled_input(event: InputEvent) -> void:
	event = GamepadInput.as_key(event, {JOY_BUTTON_A: KEY_ENTER, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_Y: KEY_SPACE, JOY_BUTTON_LEFT_SHOULDER: KEY_Q, JOY_BUTTON_RIGHT_SHOULDER: KEY_E, JOY_BUTTON_RIGHT_STICK: KEY_R})
	if resolved: return
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera_yaw -= event.relative.x * 0.006
			camera_pitch = clampf(camera_pitch + event.relative.y * 0.005, 0.35, 1.35)
			_update_camera()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE): _pan_camera(-event.relative, 0.002)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_distance = maxf(12, camera_distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_distance = minf(65, camera_distance * 1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT: _select(_pick_cell(event.position))
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: camera_yaw -= PI / 2
			KEY_E: camera_yaw += PI / 2
			KEY_R: camera_focus = hero.position
			KEY_ESCAPE: _command("cancel")
			KEY_SPACE: _command("wait")
			KEY_ENTER:
				if stage == "confirm": _command("confirm")
				else: _select(cursor_cell)
			KEY_W: cursor_cell.y = maxi(0, cursor_cell.y - 1)
			KEY_S: cursor_cell.y = mini(N - 1, cursor_cell.y + 1)
			KEY_A: cursor_cell.x = maxi(0, cursor_cell.x - 1)
			KEY_D: cursor_cell.x = mini(N - 1, cursor_cell.x + 1)
		_update_camera()
		if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]: _refresh("マスを選択して Enter で決定。")
	get_viewport().set_input_as_handled()
