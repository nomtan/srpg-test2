extends SceneTree
## SRPG mode in JRPGWorldSample2 (F4): the explore HUD gives way to the battle screen, an ally moves
## and strikes through the command menu, the enemies take their turn, the camera steps through its
## four angles, and leaving puts everything back.
## godot --headless --path . --script scripts/world_jrpg/verify_srpg.gd
## Rendered frames: drop --headless and append -- --capture-dir=<dir>.
const SAMPLE = preload("res://samples/JRPGWorldSample2.tscn")
var failed := false
var capture_dir := ""

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	if capture_dir.is_empty(): return
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(capture_dir.path_join("srpg_%s.png" % name))

func wait_for(battle: Node, states: Array, seconds := 20.0) -> bool:
	var waited := 0.0
	while not battle.state in states and waited < seconds:
		await process_frame
		waited += 1.0 / 60.0
	return battle.state in states

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.get_slice("=", 1)
	var world := SAMPLE.instantiate()
	root.add_child(world)
	await process_frame
	await create_timer(1.0).timeout
	var player_start: Vector3 = world.player.position
	var enemy_starts: Array = world.enemies.map(func(e: Node3D) -> Vector3: return e.position)
	world._set_srpg_mode(true)
	var battle: Node = world.srpg_battle
	check(not world.hud.visible and not world.field_weather.controls.visible, "SRPG mode hides the explore HUD and the weather panel")
	check(await wait_for(battle, ["menu"]), "The battle opens on the command menu")
	check(battle.units.size() == 2 + world.enemies.size(), "Explorer, sparring partner and every field enemy take part (%d)" % battle.units.size())
	check(battle.active.body == world.player and battle.hud.menu.visible, "The explorer acts first, with the menu beside it")
	check(battle.hud.menu_rows.size() == 5 and battle.hud.menu_rows[0].text.contains("移動"), "Menu: 移動 / 攻撃 / スキル / アイテム / 待機")
	await shot("menu")

	# 移動: walk to the free cell of the move range nearest the enemies.
	var hero = battle.active
	battle.command = battle.MOVE
	battle._decide()
	check(battle.state == "move" and battle.reach.size() > 1, "移動 shows the move range (%d cells)" % battle.reach.size())
	var goal: Vector2i = hero.corner
	var enemy_unit = battle.units[2]
	for corner: Vector2i in battle.reach:
		if battle._free_for(hero, corner) and battle._distance(corner, 1, enemy_unit.corner, enemy_unit.size) < battle._distance(goal, 1, enemy_unit.corner, enemy_unit.size):
			goal = corner
	battle._set_cursor(goal, true)
	await shot("move")
	battle._decide()
	check(await wait_for(battle, ["menu"]), "The explorer walks there and the menu comes back")
	check(hero.corner == goal and hero.moved and not battle._enabled(battle.MOVE), "It stands on the chosen cell and cannot move again (%s)" % [hero.corner])
	check(world.player.position.distance_to(battle._block_center(goal, 1)) < 0.2, "The explorer's body is on that cell")

	# 攻撃: stand it beside a goblin and strike.
	var spot: Vector2i = battle._free_cell_near(enemy_unit.corner + Vector2i.LEFT, hero)
	for direction: Vector2i in battle.DIRECTIONS:
		var cell: Vector2i = enemy_unit.corner + direction
		if battle._free_for(hero, cell):
			spot = cell
			break
	hero.corner = spot
	battle._place(hero)
	battle.command = battle.ATTACK
	battle._decide()
	check(battle.state == "attack" and battle.cursor == enemy_unit.corner, "攻撃 shows the attack range with the cursor on the goblin beside it")
	check(battle.hud.enemy_card.panel.visible and battle.hud.enemy_card.name.text == enemy_unit.name, "The targeted enemy's card shows")
	await shot("attack")
	var hp: int = enemy_unit.hp
	battle._decide()
	check(await wait_for(battle, ["menu", "enemy", "over"]), "The blow plays out")
	check(enemy_unit.hp < hp, "The goblin loses HP (%d -> %d)" % [hp, enemy_unit.hp])
	check(battle.state == "menu" and battle.active != hero, "Moved and acted, the explorer is done and the partner's turn begins")

	# The partner waits; the enemies take their turn.
	battle.command = battle.WAIT
	battle._decide()
	check(battle.state == "enemy", "With every ally done, the enemy turn starts")
	var before: Array = battle.units.map(func(u) -> Vector2i: return u.corner)
	check(await wait_for(battle, ["menu", "over"], 60.0), "The enemy turn plays out")
	var after: Array = battle.units.map(func(u) -> Vector2i: return u.corner)
	check(before != after, "Enemies walk toward the allies")
	check(battle.turn == 2 or battle.state == "over", "Turn 2 begins (%d)" % battle.turn)
	await shot("turn2")

	# Camera: four quarter angles, by key and by button.
	for index in 4:
		battle._on_angle_pressed(index)
		check(world.srpg_quarter() == index, "Camera angle %d" % index)
	battle._turn_camera(1)
	check(world.srpg_quarter() == 0, "Q / E step round the four angles")
	var near: float = world.distance
	world.zoom_srpg_camera(0.5)
	world.tilt_srpg_camera(0.3)
	await create_timer(0.1).timeout
	check(world.distance < near - 0.1 and world.distance > world.srpg_distance + 0.1, "Zoom eases in rather than jumping (%.2f -> %.2f of %.2f)" % [near, world.distance, world.srpg_distance])
	await create_timer(1.5).timeout
	check(absf(world.distance - world.srpg_distance) < 0.05, "Zoom settles on its target")
	check(absf(world.pitch - world.srpg_pitch) < 0.01 and world.pitch > world.SRPG_PITCH + 0.25, "Tilt raises the camera and settles (%.2f)" % world.pitch)
	await create_timer(0.5).timeout
	await shot("angle")

	world._set_srpg_mode(false)
	check(world.hud.visible and world.field_weather.controls.visible and world.mode == "explore", "Leaving restores the explore HUD")
	check(world.player.position.distance_to(player_start) < 0.05, "The explorer is back where SRPG mode began")
	await create_timer(4.0).timeout
	var home: Array = world.enemies.map(func(e: Node3D) -> bool: return e.position.distance_to(enemy_starts[world.enemies.find(e)]) < 0.2 and not e.is_dead())
	check(not home.has(false), "Every enemy is back on its spot, alive (%s)" % [home])
	check(not is_instance_valid(battle), "The battle frees itself")
	quit(1 if failed else 0)
