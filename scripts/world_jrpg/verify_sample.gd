extends SceneTree
## Headless integration checks: traversable routes, interactions and battle lifecycle.
const World = preload("res://scripts/world_jrpg/world.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
	else: print("PASS: ", message)

func _initialize() -> void:
	call_deferred("_run")

func wait_for_hero(world: Node3D) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while world.battle != null and (world.battle.busy or not world.battle.turn_manager.is_player_turn()):
		if Time.get_ticks_msec() > deadline:
			check(false, "CT turn progression timed out")
			return false
		await process_frame
	return world.battle != null

func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func pad_event(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _run() -> void:
	seed(7319)
	root.size = Vector2i(1280, 720)
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	var weather: Node = world.field_weather
	var previous_time: int = weather.time_index
	var previous_weather: int = weather.weather_index
	world._unhandled_input(pad_event(JOY_BUTTON_LEFT_SHOULDER))
	world._unhandled_input(pad_event(JOY_BUTTON_RIGHT_SHOULDER))
	check(weather.time_index == previous_time and weather.weather_index == previous_weather, "LB/RB no longer change time or weather")
	var spawn_position: Vector3 = world.player.position
	var original_yaw: float = world.yaw
	world.yaw = 0
	var move_key := key_event(KEY_D)
	move_key.physical_keycode = KEY_D
	Input.parse_input_event(move_key)
	Input.flush_buffered_events()
	world._process(0.01)
	check(is_equal_approx(world.player.position.x - spawn_position.x, 0.045), "Walking retains 4.5 units per second")
	world.player.position = spawn_position
	var sprint_key := key_event(KEY_SHIFT)
	sprint_key.physical_keycode = KEY_SHIFT
	Input.parse_input_event(sprint_key)
	Input.flush_buffered_events()
	world._process(0.01)
	check(is_equal_approx(world.player.position.x - spawn_position.x, 0.16) and world.player.running, "Running is 16 units per second, twice previous speed")
	move_key = move_key.duplicate()
	sprint_key = sprint_key.duplicate()
	move_key.pressed = false
	sprint_key.pressed = false
	Input.parse_input_event(move_key)
	Input.parse_input_event(sprint_key)
	Input.flush_buffered_events()
	world._process(0)
	check(not world.player.walking and not world.player.running, "Releasing movement returns to idle")
	world.player.position = spawn_position
	world.yaw = original_yaw
	var conditions_valid := true
	for time_index in 4:
		for weather_index in 4:
			# Use the actual button callbacks, including their captured indices.
			weather.time_buttons[time_index].pressed.emit()
			weather.weather_buttons[weather_index].pressed.emit()
			conditions_valid = conditions_valid and weather.time_index == time_index and weather.weather_index == weather_index
			conditions_valid = conditions_valid and weather.time_buttons[time_index].button_pressed and weather.weather_buttons[weather_index].button_pressed
			conditions_valid = conditions_valid and weather.particles.emitting == (weather_index in [1, 3]) and weather.particles.visible == (weather_index in [1, 3])
			for mesh: BoxMesh in World.Batch.meshes.values():
				if mesh.material.shader != World.Batch.SURFACE: continue
				conditions_valid = conditions_valid and is_equal_approx(mesh.material.get_shader_parameter("wetness"), 1.0 if weather_index == 1 else 0.0)
				conditions_valid = conditions_valid and is_equal_approx(mesh.material.get_shader_parameter("snow_cover"), 0.8 if weather_index == 3 else 0.0)
				conditions_valid = conditions_valid and is_equal_approx(mesh.material.get_shader_parameter("night_light"), 1.0 if time_index == 3 else 0.0)
	check(conditions_valid, "All 16 time/weather button combinations apply to particles and terrain")
	weather.apply_conditions(1, 0)
	var midday_light: float = weather.sun.light_energy
	var midday_angle: Vector3 = weather.sun.rotation_degrees
	weather.apply_conditions(0, 0)
	check(weather.sun.rotation_degrees != midday_angle, "Morning changes sunlight direction")
	weather.apply_conditions(3, 2)
	check(weather.sun.light_energy < midday_light and world.world_environment.fog_sky_affect < 1.0, "Night/cloudy changes light and retains visible cloud sky")
	weather.apply_conditions(2, 0)
	check(World.SIZE * World.SIZE == 160000, "400 x 400 world: 9.765625 times original area")
	var start := Vector2i(32, 60)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var from := Vector3(cell.x + 0.5, world._surface(cell.x + 0.5, cell.y + 0.5) + 0.05, cell.y + 0.5)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next): continue
			var point := Vector3(next.x + 0.5, world._surface(next.x + 0.5, next.y + 0.5) + 0.05, next.y + 0.5)
			if world._can_walk(point, from):
				seen[next] = true
				queue.append(next)
	check(seen.size() > 105000, "Exploration connected land: %d cells" % seen.size())
	for npc in world.npcs:
		var reachable := false
		for cell: Vector2i in seen:
			var point := Vector3(cell.x + 0.5, world._surface(cell.x + 0.5, cell.y + 0.5), cell.y + 0.5)
			if point.distance_to(npc.actor.position) < 3.1: reachable = true
		check(reachable, "Walk from spawn to NPC: " + str(npc.data.id))
	for goal in [Vector2i(87, 80), Vector2i(100, 25), Vector2i(24, 30), Vector2i(47, 105), Vector2i(47, 117), Vector2i(370, 80), Vector2i(210, 350), Vector2i(305, 65), Vector2i(350, 300)]:
		check(seen.has(goal), "Landmark route: " + str(goal))
	check(not world._can_walk(Vector3(40, 14, 59), Vector3(35, 14, 59)), "Cliff edge blocks walking")
	check(not world._can_walk(Vector3(37, 3.5, 74), Vector3(34, 3.5, 74)), "House collision")
	check(not world._can_walk(Vector3(64, 1, 120), Vector3(64, 3.5, 109)), "Sea collision")
	world._show_dialog("Test", ["First", "Second"])
	check(world.mode == "dialog" and world.dialog_panel.visible, "Dialogue locks exploration")
	world._unhandled_input(pad_event(JOY_BUTTON_A))
	check(world.dialog_index == 1, "Gamepad A advances dialogue")
	world._unhandled_input(pad_event(JOY_BUTTON_B))
	check(world.mode == "explore", "Gamepad B closes dialogue")
	world.player.position = world.encounter_position + Vector3(0, 0.05, 0)
	var original_actor_id := world.player.get_instance_id()
	var encounter_start: Vector3 = world.player.position
	world._process(0.01)
	check(world.mode == "dialog", "Arrival triggers encounter event")
	world._close_dialog()
	check(world.mode == "battle" and world.player.visible, "Encounter keeps explorer visible on world map")
	var battle: Node3D = world.battle
	world._input(pad_event(JOY_BUTTON_X))
	check(not world.player.use_3d and world.player.sprite.visible and battle.hero == world.player, "Gamepad X switches battle hero to original 2D actor")
	world._input(key_event(KEY_V))
	check(world.player.use_3d and world.player.model.visible and world.player.position == encounter_start, "V restores 3D without teleporting or replacing battle actor")
	check(battle.hero == world.player and battle.hero.get_instance_id() == original_actor_id, "Exact exploration actor reused")
	check(world.player.position == encounter_start, "Starting battle does not teleport the explorer")
	check(battle.enemies.size() == 2, "Enemies spawn on reachable world terrain")
	var terrain_valid := true
	for cell: Vector2i in battle.tiles:
		var point: Vector3 = battle._point(cell)
		if not world._can_walk(point, point): terrain_valid = false
		if absf(battle.tiles[cell].position.y - world._surface(point.x, point.z) - 0.065) > 0.001: terrain_valid = false
	check(terrain_valid, "Overlay follows only valid world surfaces")
	battle.animation_time = 0.001
	check(battle.turn_manager is TurnManager and battle.attacks is AttackSystem and battle.skills is SkillSystem, "Main combat/CT/skill implementations reused")
	check(battle.turn_manager.current_actor == battle.hero_data and battle.hero_data.ct >= 100, "CT speed selects ready hero")
	check(root.gui_get_focus_owner() == battle.buttons.move, "Battle menu has initial controller focus")
	await process_frame
	root.push_input(pad_event(JOY_BUTTON_A))
	var release := pad_event(JOY_BUTTON_A)
	release.pressed = false
	root.push_input(release)
	Input.flush_buffered_events()
	await process_frame
	check(battle.stage == "move" and root.gui_get_focus_owner() == null, "Gamepad A opens movement and releases menu focus")
	battle._unhandled_input(pad_event(JOY_BUTTON_B))
	check(battle.stage == "menu" and root.gui_get_focus_owner() != null, "Gamepad B restores menu focus")
	var starting_cell: Vector2i = battle.hero_cell
	var chosen_cell := starting_cell
	for cell: Vector2i in battle._reachable():
		if cell != starting_cell:
			chosen_cell = cell
			break
	await battle._command("move")
	await battle._select(chosen_cell)
	check(battle.moved and world.player.position.is_equal_approx(battle._point(chosen_cell)), "Menu movement animates the exploration actor")
	await battle._command("cancel")
	check(not battle.moved and battle.hero_cell == starting_cell and world.player.position == encounter_start, "Provisional move can be canceled before action")
	var camera_before: Transform3D = world.camera.transform
	battle._unhandled_input(key_event(KEY_Q))
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	battle._unhandled_input(wheel)
	battle._pan_camera(Vector2.RIGHT, 0.1)
	check(world.camera.transform != camera_before and battle.camera_distance < 27, "Battle camera rotates, zooms and pans")
	await battle._command("wait")
	await battle._command("south")
	check(battle.hero_data.ct == 20 and battle.hero_data.facing == BattleUnit.FacingDirection.SOUTH, "Wait preserves CT 20 and chosen facing")
	await process_frame
	check(battle.busy and battle.turn_manager.current_actor.team == "enemy", "CT schedules enemy turns")
	camera_before = world.camera.transform
	battle._unhandled_input(key_event(KEY_E))
	check(world.camera.transform != camera_before, "Camera input remains available during enemy action")
	var retained_camera: Transform3D = world.camera.transform
	await wait_for_hero(world)
	check(world.camera.transform == retained_camera, "Turn changes preserve camera position")
	await battle._command("skill")
	await battle._command("guard_stance")
	check(battle.stage == "confirm" and battle.hero_data.ap == 30, "Skill confirmation shows preview without spending AP")
	await battle._command("cancel")
	check(battle.hero_data.ap == 30 and not battle.attacked, "Canceling skill preview does not consume action")
	await battle._command("guard_stance")
	await battle._command("confirm")
	check(battle.hero_data.ap == 24 and battle.hero_data.temporary_defense_bonus == 3 and battle.attacked, "Main guard skill consumes AP and applies defense buff")
	await battle._command("guard_stance")
	check(battle.hero_data.ap == 24 and battle.stage == "menu", "Second skill is blocked within the same turn")
	var hero_hp: int = battle.hp
	weather.weather_buttons[3].pressed.emit()
	weather.time_buttons[3].pressed.emit()
	check(weather.controls.visible and weather.weather_index == 3 and battle.hp == hero_hp and battle.hero_data.ap == 24, "Weather UI works during battle without resetting combat")
	weather.apply_conditions(2, 0)
	await battle._command("move")
	await battle._select(chosen_cell)
	check(battle.moved and battle.attacked and battle.stage == "facing", "Movement is also allowed after action")
	await battle._command("east")
	check(battle.hero_data.ct == 0, "Action resets CT to 0")
	var second_attack_checked := false
	var preview_checked := false
	for turn_index in 20:
		if not await wait_for_hero(world): break
		var found: Dictionary = battle._reachable()
		var best: Vector2i = battle.hero_cell
		var score := 10000
		for cell: Vector2i in found:
			for enemy in battle.enemies:
				if enemy.hp <= 0: continue
				var cost: int = battle._distance(cell, enemy.cell) * 10 + int(found[cell].cost)
				if cost < score:
					best = cell
					score = cost
		if best != battle.hero_cell:
			await battle._command("move")
			await battle._select(best)
		for enemy in battle.enemies:
			if enemy.hp > 0 and battle._can_attack(battle.hero_cell, enemy.cell):
				var health_before: int = enemy.hp
				await battle._command("attack")
				await battle._select(enemy.cell)
				if not preview_checked:
					check(battle.stage == "confirm" and enemy.hp == health_before, "Normal attack needs confirmation and shows damage/hit preview")
					preview_checked = true
				await battle._command("cancel")
				await battle._command("power_slash" if battle.hero_data.ap >= 5 else "attack")
				await battle._select(enemy.cell)
				await battle._command("confirm")
				if world.battle != null and enemy.hp > 0 and not second_attack_checked:
					var remaining: int = enemy.hp
					await battle._command("attack")
					await battle._select(enemy.cell)
					await battle._command("confirm")
					check(enemy.hp == remaining and battle.attacked, "Second attack blocked")
					second_attack_checked = true
				break
		if world.battle != null:
			await battle._command("wait")
			await battle._command("south")
	check(world.cleared and world.mode == "dialog" and world.player.visible, "Victory ends encounter on same map")
	var winning_position: Vector3 = world.player.position
	check(winning_position.distance_to(encounter_start) < 12 and winning_position != encounter_start, "Victory preserves last tactical position")
	world._close_dialog()
	world._process(0.01)
	check(world.mode == "explore" and world.player.position == winning_position, "Exploration resumes where battle ended")
	await process_frame
	check(world.player.get_instance_id() == original_actor_id and world.player.get_parent() == world, "Battle cleanup preserves explorer")
	world.player.position = encounter_start
	world._start_battle()
	world.battle.animation_time = 0.0
	world.battle.hp = 1
	for i in 8:
		if not await wait_for_hero(world): break
		await world.battle._command("wait")
		await world.battle._command("south")
	await wait_for_hero(world)
	check(not world.cleared and world.player.position == encounter_start, "Defeat recovers at encounter entry on same map")
	world._close_dialog()
	world._process(0.01)
	check(world.mode == "explore" and world.encounter_rearm, "Defeat cannot immediately retrigger encounter")
	world.player.position = encounter_start + Vector3(-5, 0, 0)
	world._process(0.01)
	check(not world.encounter_rearm, "Leaving encounter allows a retry")
	# Exercise terrain integration away from the scripted encounter.
	for point in [Vector2(35, 59), Vector2(world._river(80), 80)]:
		world.player.position = Vector3(point.x, world._surface(point.x, point.y) + 0.05, point.y)
		world._start_battle()
		battle = world.battle
		var blocked := 0
		var high := -INF
		var low := INF
		var edges_valid := true
		for z in battle.N:
			for x in battle.N:
				if not battle.tiles.has(Vector2i(x, z)): blocked += 1
		for cell: Vector2i in battle.adjacency:
			high = maxf(high, battle._point(cell).y)
			low = minf(low, battle._point(cell).y)
			for neighbor: Vector2i in battle.adjacency[cell]:
				if not battle._terrain_edge(cell, neighbor): edges_valid = false
		check(edges_valid and blocked > 0, "Cliff / river obstacles excluded: " + str(point))
		if point.x == 35: check(high > low, "Tactical grid samples multiple terrain elevations")
		await process_frame
		var cell: Vector2i = battle.hero_cell
		var screen: Vector2 = battle.camera.unproject_position(battle._point(cell) + Vector3(0, 0.015, 0))
		check(battle._pick_cell(screen) == cell, "Height-aware mouse picking: " + str(point))
		battle._complete(false)
		world._close_dialog()
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)
