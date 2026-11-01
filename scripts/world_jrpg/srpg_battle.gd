extends Node
## SRPG battle on the open field (SRPG mode, F4): the explorer and the sparring partner against the
## field enemies, on the world's tactical cells. Player turn: each ally picks commands from the
## menu (移動 / 攻撃 / スキル / アイテム / 待機), moving once and acting once; enemy turn: each
## enemy walks toward the nearest ally and strikes when it ends beside one. Every unit's portrait
## is shot from the field at the start. Stats are placeholders until units carry real data.
## Leaving SRPG mode (finish) puts every unit back as it stood before the battle.

const Hud = preload("res://scripts/ui/srpg_hud.gd")
const DamageNumber = preload("res://scripts/effect/damage_number_3d.gd")
const TURN_LIMIT := 12
## Seconds per tactical cell walked.
const STEP_TIME := 0.4
const SKILL_COST := 12
const SKILL_POWER := 1.6
const POTION_HEAL := 100
const POTIONS := 3
## Bow reach in tactical cells (other weapons strike the cells beside the unit).
const BOW_RANGE := 4
## Placeholder stats: [job, level, hp, mp, power, defense, move, jump (m)].
const EXPLORER_STATS := ["剣士 / 戦士", 12, 280, 48, 64, 18, 4, 2]
const ARCHER_JOB := "弓使い / 狩人"
const PARTNER_STATS := ["見習い / 戦士", 10, 220, 30, 52, 14, 4, 2]
const ENEMY_STATS := {
	"goblin": ["戦士 / ゴブリン", 8, 120, 12, 46, 10, 3, 1],
	"wolf": ["獣 / ウルフ", 9, 150, 0, 50, 8, 5, 2],
	"grimm": ["魔獣 / グリム", 14, 320, 24, 70, 20, 3, 1],
}
const COMMANDS := [["移動", "➜"], ["攻撃", "⚔"], ["スキル", "✦"], ["アイテム", "⚗"], ["待機", "⌛"]]
const MOVE := 0
const ATTACK := 1
const SKILL := 2
const ITEM := 3
const WAIT := 4
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const NOWHERE := Vector2i(-100000, -100000)
const PORTRAIT_SIZE := 256

## One unit on the grid: `body` is moved and turned, `visual` carries the clips, name label and
## HP gauge (the explorer's model; the node itself for everyone else). A unit takes the
## `size` x `size` square of tactical cells from `corner`.
class Unit:
	var body: Node3D
	var visual: Node3D
	var name := ""
	var job := ""
	var level := 1
	var hp := 1
	var max_hp := 1
	var mp := 0
	var max_mp := 0
	var power := 1
	var defense := 0
	var move := 4
	var jump := 2
	var reach := 1
	var element := "無"
	var enemy := false
	var corner := Vector2i.ZERO
	var size := 1
	var moved := false
	var acted := false
	var done := false
	var portrait: Texture2D
	var start: Transform3D

	func alive() -> bool:
		return hp > 0

var world: Node3D
var hud: Hud
var units: Array[Unit] = []
var active: Unit
## intro (shooting portraits), menu, move, attack, free (cursor roams), busy, enemy, over.
var state := "intro"
var turn := 1
var enemy_phase := false
var command := MOVE
var cursor := NOWHERE
## The active unit's move: corner -> the corner it is entered from.
var reach := {}
## Attack (or skill) chosen in the menu.
var skill := false
var danger := false
## Where the active ally stood before moving, for taking the move back.
var move_from := NOWHERE
var potions := POTIONS
## What the camera looks at: a moving or striking unit's body, else focus_target.
var follow: Node3D
var focus_target := Vector3.ZERO
var ended := false
var occupied_before := {}
var tweens: Array[Tween] = []
var pad := GamepadInput.new()
var pad_turn_ready := true
var mouse_moved := false
var mouse_at := Vector2.ZERO


func begin(field: Node3D) -> void:
	world = field
	occupied_before = world.occupied_cells.duplicate()
	var player: Node3D = world.player
	player.stand_now()
	var stats := EXPLORER_STATS.duplicate()
	var ranged: bool = player.sword_combat != null and player.sword_combat.is_ranged()
	if ranged: stats[0] = ARCHER_JOB
	var hero := _add_unit(player, player.model, player.model.display_name, stats, false, 1)
	hero.reach = BOW_RANGE if ranged else 1
	var partner: Node3D = world.sparring_partner
	if partner:
		_add_unit(partner, partner, partner.display_name, PARTNER_STATS, false, 1)
		if partner.animation_player and partner.animation_player.has_animation("walk"):
			partner.animation_player.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
	for enemy: Node3D in world.enemies:
		_add_unit(enemy, enemy, enemy.display_name, ENEMY_STATS.get(enemy.enemy_id, ENEMY_STATS.goblin), true, enemy.footprint)
		enemy.revives = false
	# The explorer may stand anywhere: it takes the nearest free cell, at its middle.
	hero.corner = _free_cell_near(world.world_position_to_tactical_cell(player.position), hero)
	_place(hero)
	focus_target = hero.body.position + Vector3.UP
	await _shoot_portraits()
	if ended: return
	hud = Hud.new()
	hud.name = "SrpgHud"
	add_child(hud)
	hud.command_pressed.connect(_on_command_pressed)
	hud.angle_pressed.connect(_on_angle_pressed)
	hud.set_angle(world.srpg_quarter())
	world._set_grid_debug(true)
	_start_player_phase()

## Puts every unit back as it stood before the battle; the node frees itself once anything
## still running has had time to notice.
func finish() -> void:
	ended = true
	for tween in tweens:
		if tween.is_valid(): tween.kill()
	if hud: hud.queue_free()
	for unit in units:
		unit.body.visible = true
		if unit.enemy:
			unit.visual.revives = true
			if unit.visual.is_dead(): unit.visual.revive()
			else:
				unit.body.transform = unit.start
				unit.visual.play_animation("idle")
		else:
			unit.body.transform = unit.start
			if unit.body != world.player: unit.visual.play_animation("idle")
	world.player.walking = false
	world.player.locomotion_speed = 0.0
	world.player.cancel_attack()
	world.occupied_cells = occupied_before
	get_tree().create_timer(3.0).timeout.connect(queue_free)

func _add_unit(body: Node3D, visual: Node3D, unit_name: String, stats: Array, enemy: bool, size: int) -> Unit:
	var unit := Unit.new()
	unit.body = body
	unit.visual = visual
	unit.name = unit_name
	unit.job = stats[0]
	unit.level = stats[1]
	unit.max_hp = stats[2]
	unit.hp = unit.max_hp
	unit.max_mp = stats[3]
	unit.mp = unit.max_mp
	unit.power = stats[4]
	unit.defense = stats[5]
	unit.move = stats[6]
	unit.jump = stats[7]
	unit.enemy = enemy
	unit.size = size
	unit.start = body.transform
	var span := _span()
	unit.corner = Vector2i(roundi(body.position.x / span - size * 0.5), roundi(body.position.z / span - size * 0.5))
	units.append(unit)
	return unit


# --- Grid -----------------------------------------------------------------------

func _span() -> float:
	return world.CELL_SIZE * world.TACTICAL_SPAN

## The ground point in the middle of a `size` square of cells from `corner`.
func _block_center(corner: Vector2i, size: int) -> Vector3:
	var at := (Vector2(corner) + Vector2.ONE * size * 0.5) * _span()
	return Vector3(at.x, world._surface(at.x, at.y) + 0.05, at.y)

func _place(unit: Unit) -> void:
	unit.body.position = _block_center(unit.corner, unit.size)

func _cells(corner: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z in size:
		for x in size:
			cells.append(corner + Vector2i(x, z))
	return cells

## Grid steps between two squares of cells (0 when they overlap, 1 when side by side).
func _distance(a: Vector2i, a_size: int, b: Vector2i, b_size: int) -> int:
	var gap_x := maxi(maxi(b.x - (a.x + a_size - 1), a.x - (b.x + b_size - 1)), 0)
	var gap_z := maxi(maxi(b.y - (a.y + a_size - 1), a.y - (b.y + b_size - 1)), 0)
	return gap_x + gap_z

## The living unit on `cell`, other than `except`.
func _occupant(cell: Vector2i, except: Unit = null) -> Unit:
	for unit in units:
		if unit != except and unit.alive() and _distance(unit.corner, unit.size, cell, 1) == 0:
			return unit
	return null

func _height(corner: Vector2i, size: int) -> float:
	var at := _block_center(corner, size)
	return world.get_logical_height(at.x, at.z)

## Whether `unit` can step from `from` to `to`: every cell walkable, no foe in the way and a
## height change within its jump. Friends may be passed through.
func _can_enter(unit: Unit, from: Vector2i, to: Vector2i) -> bool:
	for cell in _cells(to, unit.size):
		var at: Vector3 = world.tactical_cell_to_world_position(cell)
		if not world.is_walkable_at(at.x, at.z): return false
		var other := _occupant(cell, unit)
		if other and other.enemy != unit.enemy: return false
	return absf(_height(to, unit.size) - _height(from, unit.size)) <= unit.jump

## Whether `unit` can stop with its corner on `corner`.
func _free_for(unit: Unit, corner: Vector2i) -> bool:
	for cell in _cells(corner, unit.size):
		if _occupant(cell, unit): return false
	return true

## Every corner `unit` can walk to this turn, each mapped to the corner it is entered from.
func _reachable(unit: Unit) -> Dictionary:
	var came := {unit.corner: unit.corner}
	var steps := {unit.corner: 0}
	var frontier: Array[Vector2i] = [unit.corner]
	while not frontier.is_empty():
		var at: Vector2i = frontier.pop_front()
		if steps[at] == unit.move: continue
		for direction in DIRECTIONS:
			var next := at + direction
			if steps.has(next) or not _can_enter(unit, at, next): continue
			steps[next] = steps[at] + 1
			came[next] = at
			frontier.append(next)
	return came

func _path(came: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [to]
	while came[path[0]] != path[0]:
		path.push_front(came[path[0]])
	return path

## The cells a move of `unit` may end on (whole squares for big units), keyed by cell.
func _move_cells(unit: Unit, came: Dictionary) -> Dictionary:
	var cells := {}
	for corner: Vector2i in came:
		if corner == unit.corner or _free_for(unit, corner):
			for cell in _cells(corner, unit.size): cells[cell] = true
	return cells

## The cells `unit` strikes from `corner`, keyed by cell.
func _attack_cells(unit: Unit, corner: Vector2i) -> Dictionary:
	var cells := {}
	for z in range(-unit.reach, unit.size + unit.reach):
		for x in range(-unit.reach, unit.size + unit.reach):
			var cell := corner + Vector2i(x, z)
			var steps := _distance(corner, unit.size, cell, 1)
			if steps >= 1 and steps <= unit.reach: cells[cell] = true
	return cells

## Foes of `unit` within its reach from where it stands.
func _targets(unit: Unit) -> Array[Unit]:
	var found: Array[Unit] = []
	for other in units:
		if other.alive() and other.enemy != unit.enemy:
			var steps := _distance(unit.corner, unit.size, other.corner, other.size)
			if steps >= 1 and steps <= unit.reach: found.append(other)
	return found

## Every cell some enemy could strike this coming turn.
func _danger_cells() -> Dictionary:
	var cells := {}
	for unit in units:
		if not unit.enemy or not unit.alive(): continue
		var came := _reachable(unit)
		for corner: Vector2i in came:
			if corner == unit.corner or _free_for(unit, corner):
				cells.merge(_attack_cells(unit, corner))
	return cells

func _free_cell_near(start: Vector2i, unit: Unit) -> Vector2i:
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		var at: Vector3 = world.tactical_cell_to_world_position(cell)
		if world.is_walkable_at(at.x, at.z) and _free_for(unit, cell): return cell
		if seen.size() > 400: break
		for direction in DIRECTIONS:
			if not seen.has(cell + direction):
				seen[cell + direction] = true
				frontier.append(cell + direction)
	return start

## Repaints the grid view for the current state: the move range in blue, attack ranges (and
## the danger view) in red, the cursor in yellow.
func _paint() -> void:
	if ended or active == null: return
	var move := {}
	var attack := {}
	match state:
		"menu":
			if command == MOVE and not active.moved: move = _move_cells(active, _reachable(active))
			elif (command == ATTACK or command == SKILL) and not active.acted: attack = _attack_cells(active, active.corner)
		"move":
			move = _move_cells(active, reach)
		"attack":
			attack = _attack_cells(active, active.corner)
	if danger and not enemy_phase:
		attack = attack.duplicate()
		attack.merge(_danger_cells())
	var center := cursor if state == "free" else active.corner
	world.paint_grid(center, active.corner, move, attack)
	world.set_grid_cursor(cursor if state in ["menu", "move", "attack", "free"] else NOWHERE)


# --- Player turn ----------------------------------------------------------------

func _start_player_phase() -> void:
	enemy_phase = false
	for unit in units:
		unit.moved = false
		unit.acted = false
		unit.done = not unit.alive()
	hud.set_phase(false, turn, TURN_LIMIT)
	hud.show_banner("PLAYER TURN")
	_select(_next_ally())

func _next_ally() -> Unit:
	for unit in units:
		if not unit.enemy and not unit.done: return unit
	return null

func _select(unit: Unit) -> void:
	active = unit
	move_from = unit.corner
	command = MOVE if not unit.moved else (ATTACK if not unit.acted else WAIT)
	_open_menu()

func _enabled(index: int) -> bool:
	match index:
		MOVE: return not active.moved
		ATTACK: return not active.acted
		SKILL: return not active.acted and active.mp >= SKILL_COST
		ITEM: return not active.acted and potions > 0 and active.hp < active.max_hp
	return true

func _open_menu() -> void:
	state = "menu"
	cursor = active.corner
	focus_target = active.body.position + Vector3.UP
	if not _enabled(command): command = WAIT
	var items := []
	for index in COMMANDS.size():
		var label: String = COMMANDS[index][0]
		if index == ITEM: label += "  ×%d" % potions
		items.append({"label": label, "icon": COMMANDS[index][1], "enabled": _enabled(index)})
	hud.set_commands(items)
	hud.highlight_command(command)
	_place_menu()
	_paint()
	_refresh_hud()

func _place_menu() -> void:
	var camera: Camera3D = world.camera
	var head := active.body.position + Vector3.UP * 1.2
	if camera.is_position_behind(head): return
	hud.show_menu(camera.unproject_position(head) + Vector2(70, -150))

func _decide() -> void:
	match state:
		"menu":
			if not _enabled(command): return
			match command:
				MOVE:
					state = "move"
					reach = _reachable(active)
					hud.hide_menu()
					_paint()
				ATTACK, SKILL:
					state = "attack"
					skill = command == SKILL
					var foes := _targets(active)
					if not foes.is_empty(): _set_cursor(foes[0].corner, true)
					hud.hide_menu()
					_paint()
					_refresh_hud()
				ITEM: _use_potion()
				WAIT: _end_unit()
		"move":
			if not reach.has(cursor) or (cursor != active.corner and not _free_for(active, cursor)): return
			_move_active(cursor)
		"attack":
			var target := _occupant(cursor, active)
			if target == null or target.enemy == active.enemy or not (target in _targets(active)): return
			_attack_active(target)
		"free":
			var unit := _occupant(cursor)
			if unit and not unit.enemy and not unit.done: _select(unit)

func _cancel() -> void:
	match state:
		"move", "attack":
			_open_menu()
		"menu":
			if active.moved and not active.acted:
				# Takes the move back.
				active.corner = move_from
				_place(active)
				active.moved = false
				command = MOVE
				_open_menu()
			else:
				state = "free"
				hud.hide_menu()
				_paint()
				_refresh_hud()
		"free":
			_open_menu()

func _move_active(to: Vector2i) -> void:
	state = "busy"
	world.set_grid_cursor(NOWHERE)
	world.paint_grid(active.corner, active.corner, {}, {})
	if to != active.corner: await _walk(active, _path(reach, to))
	if ended: return
	active.moved = true
	if active.acted: _end_unit()
	else:
		command = ATTACK
		_open_menu()

func _attack_active(target: Unit) -> void:
	state = "busy"
	world.set_grid_cursor(NOWHERE)
	world.paint_grid(active.corner, active.corner, {}, {})
	await _strike(active, target, skill)
	if ended: return
	active.acted = true
	if _check_end(): return
	if active.moved: _end_unit()
	else:
		command = MOVE
		_open_menu()

func _use_potion() -> void:
	state = "busy"
	hud.hide_menu()
	potions -= 1
	var healed := mini(POTION_HEAL, active.max_hp - active.hp)
	active.hp += healed
	var number := DamageNumber.new()
	number.name = "HealNumber"
	world.add_child(number)
	number.play(healed, active.body.position + Vector3.UP * 1.8)
	number.modulate = Color(0.55, 1.0, 0.6)
	_refresh_hud()
	await _wait(0.8)
	if ended: return
	active.acted = true
	if active.moved: _end_unit()
	else:
		command = MOVE
		_open_menu()

func _end_unit() -> void:
	active.done = true
	var next := _next_ally()
	if next: _select(next)
	else: _run_enemy_phase()

func _end_player_phase() -> void:
	if enemy_phase or state in ["intro", "busy", "over"]: return
	for unit in units:
		if not unit.enemy: unit.done = true
	_run_enemy_phase()


# --- Enemy turn -----------------------------------------------------------------

func _run_enemy_phase() -> void:
	state = "enemy"
	enemy_phase = true
	hud.hide_menu()
	hud.set_phase(true, turn, TURN_LIMIT)
	hud.show_banner("ENEMY TURN", Color("#ff9a8a"))
	world.set_grid_cursor(NOWHERE)
	await _wait(1.1)
	for unit in units:
		if ended: return
		if not unit.enemy or not unit.alive(): continue
		active = unit
		_refresh_hud()
		await _enemy_act(unit)
		if ended or _check_end(): return
	turn += 1
	if turn > TURN_LIMIT:
		_game_over(false, "TIME UP")
		return
	_start_player_phase()

## Walks to the free spot nearest an ally (fewest steps on a tie) and strikes the weakest ally
## beside it.
func _enemy_act(unit: Unit) -> void:
	follow = unit.body
	var came := _reachable(unit)
	world.paint_grid(unit.corner, unit.corner, {}, _move_cells(unit, came))
	await _wait(0.6)
	if ended: return
	var best := unit.corner
	var best_score := INF
	for corner: Vector2i in came:
		if corner != unit.corner and not _free_for(unit, corner): continue
		var nearest := INF
		for other in units:
			if not other.enemy and other.alive():
				nearest = minf(nearest, _distance(corner, unit.size, other.corner, other.size))
		var score := nearest * 100.0 + _path(came, corner).size()
		if score < best_score:
			best_score = score
			best = corner
	world.paint_grid(unit.corner, unit.corner, {}, {})
	if best != unit.corner: await _walk(unit, _path(came, best))
	if ended: return
	var target: Unit = null
	for other in _targets(unit):
		if target == null or other.hp < target.hp: target = other
	if target: await _strike(unit, target, false)
	follow = null


# --- Actions --------------------------------------------------------------------

func _tween() -> Tween:
	var tween := create_tween()
	tweens = tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	tweens.append(tween)
	return tween

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Turns `unit` so its model looks at `toward`. The explorer turns through world_facing, offset by
## however far its model's front sits from it (a model set up without the roster layout looks
## 90 degrees aside).
func _face(unit: Unit, toward: Vector3) -> void:
	var to := toward - unit.body.position
	to.y = 0.0
	if to.is_zero_approx(): return
	if unit.body == world.player:
		var offset := _front(unit).signed_angle_to(world.player.world_facing, Vector3.UP)
		world.player.world_facing = to.normalized().rotated(Vector3.UP, offset)
	else: unit.body.rotation.y = atan2(to.x, to.z)

## Where `unit`'s model faces on the ground: every model looks along its Model node's +Z.
func _front(unit: Unit) -> Vector3:
	var model := marker_model_of(unit)
	var inner := model.get_node_or_null("Model") as Node3D
	var front := (inner if inner else model).global_basis.z
	front.y = 0.0
	return front.normalized() if not front.is_zero_approx() else Vector3.BACK

## Walks `unit` cell by cell along `path` (corners, starting where it stands).
func _walk(unit: Unit, path: Array[Vector2i]) -> void:
	follow = unit.body
	var explorer: bool = unit.body == world.player
	if not explorer: unit.visual.play_animation("walk")
	for index in range(1, path.size()):
		var from := unit.body.position
		var to := _block_center(path[index], unit.size)
		_face(unit, to)
		if explorer:
			world.player.walking = true
			world.player.locomotion_speed = _span() / STEP_TIME
		var tween := _tween()
		tween.tween_method(_step_along.bind(unit.body, from, to), 0.0, 1.0, STEP_TIME)
		await tween.finished
		if ended: return
		unit.corner = path[index]
	if explorer:
		world.player.walking = false
		world.player.locomotion_speed = 0.0
	else: unit.visual.play_animation("idle")
	follow = null

func _step_along(t: float, body: Node3D, from: Vector3, to: Vector3) -> void:
	var at := from.lerp(to, t)
	at.y = world._surface(at.x, at.z) + 0.05
	body.position = at

func _clip_length(unit: Unit, clip: String) -> float:
	var player: AnimationPlayer = unit.visual.get("animation_player")
	if player and player.has_animation(clip): return player.get_animation(clip).length
	return 0.8

## One blow from `attacker` to `target`: the attack clip, the damage at its contact moment, the
## target's reaction, then a short pause.
func _strike(attacker: Unit, target: Unit, use_skill: bool) -> void:
	follow = attacker.body
	_face(attacker, target.body.position)
	if target.body != world.player: _face(target, attacker.body.position)
	if use_skill: attacker.mp -= SKILL_COST
	var amount := _damage(attacker, target, use_skill)
	if attacker.body == world.player:
		var player: Node3D = world.player
		var started: bool = player.skill() if use_skill else false
		if not started: started = player.attack(use_skill)
		var impact := [""]
		var on_impact := func(clip: String) -> void: impact[0] = clip
		player.attack_impact.connect(on_impact)
		var waited := 0.0
		while started and impact[0] == "" and player.attacking and waited < 2.5:
			await get_tree().process_frame
			if ended: return
			waited += get_process_delta_time()
		player.attack_impact.disconnect(on_impact)
		if not started: await _wait(0.3)
		if ended: return
		_hit(target, amount)
		if impact[0] != "":
			var struck: Array[Node3D] = [target.body]
			world._show_hits(struck, impact[0])
		waited = 0.0
		while player.attacking and waited < 2.5:
			await get_tree().process_frame
			if ended: return
			waited += get_process_delta_time()
	else:
		var clips: Array = attacker.visual.attack_clips() if attacker.enemy else ["attack"]
		var clip: String = clips[randi() % clips.size()]
		attacker.visual.play_animation(clip)
		var length := _clip_length(attacker, clip)
		await _wait(length * 0.45)
		if ended: return
		_hit(target, amount)
		await _wait(length * 0.55)
		if ended: return
		if attacker.alive(): attacker.visual.play_animation("idle")
	await _wait(0.35)
	follow = null

func _damage(attacker: Unit, target: Unit, use_skill: bool) -> int:
	var base := maxf(1.0, attacker.power - target.defense * 0.5) * (SKILL_POWER if use_skill else 1.0)
	return maxi(1, roundi(base * randf_range(0.9, 1.1)))

func _hit(target: Unit, amount: int) -> void:
	target.hp = maxi(0, target.hp - amount)
	world._show_damage(target.visual, amount)
	if target.enemy:
		if not target.alive():
			target.visual.fall()
		else:
			target.visual.play_animation("hit")
			get_tree().create_timer(_clip_length(target, "hit")).timeout.connect(_settle.bind(target))
	else:
		_shake(target.body)
		if target.body != world.player: target.visual.play_animation("hit")
		if not target.alive():
			# Allies have no fall yet: they leave the field.
			get_tree().create_timer(0.6).timeout.connect(_knock_out.bind(target))
	_refresh_hud()

func _settle(unit: Unit) -> void:
	if not ended and unit.alive() and unit.body != follow: unit.visual.play_animation("idle")

func _knock_out(unit: Unit) -> void:
	if not ended: unit.body.visible = false

func _shake(body: Node3D) -> void:
	var home := body.position
	var aside := body.global_basis.x * 0.08
	var tween := _tween()
	for offset in [aside, -aside, aside * 0.5, Vector3.ZERO]:
		tween.tween_property(body, "position", home + offset, 0.05)

## Victory once every enemy is down, defeat once every ally is.
func _check_end() -> bool:
	var allies := false
	var foes := false
	for unit in units:
		if unit.alive():
			if unit.enemy: foes = true
			else: allies = true
	if not foes: _game_over(true, "VICTORY")
	elif not allies: _game_over(false, "DEFEAT")
	return not (foes and allies)

func _game_over(won: bool, text: String) -> void:
	state = "over"
	follow = null
	hud.hide_menu()
	world.set_grid_cursor(NOWHERE)
	world.paint_grid(active.corner, active.corner, {}, {})
	hud.show_banner(text + "\nF4 : 探索に戻る", Color("#ffe08a") if won else Color("#ff8a8a"), -1.0)
	_refresh_hud()


# --- Input ----------------------------------------------------------------------

func handle_input(event: InputEvent) -> void:
	if state == "intro" or ended: return
	event = GamepadInput.as_key(event, {JOY_BUTTON_A: KEY_ENTER, JOY_BUTTON_B: KEY_ESCAPE, JOY_BUTTON_X: KEY_TAB,
		JOY_BUTTON_START: KEY_T, JOY_BUTTON_BACK: KEY_H})
	if event is InputEventKey and event.pressed:
		if event.echo and not (event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]): return
		match event.keycode:
			KEY_UP, KEY_W: _direction(Vector2i.UP)
			KEY_DOWN, KEY_S: _direction(Vector2i.DOWN)
			KEY_LEFT, KEY_A: _direction(Vector2i.LEFT)
			KEY_RIGHT, KEY_D: _direction(Vector2i.RIGHT)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _decide()
			KEY_ESCAPE, KEY_BACKSPACE: _cancel()
			KEY_Q: _turn_camera(-1)
			KEY_E: _turn_camera(1)
			KEY_1, KEY_2, KEY_3, KEY_4: _on_angle_pressed(event.keycode - KEY_1)
			KEY_TAB:
				danger = not danger
				_paint()
			KEY_T: _end_player_phase()
			KEY_H: if hud: hud.visible = not hud.visible
	elif event is InputEventMouseMotion:
		mouse_moved = true
		mouse_at = event.position
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: world.zoom_srpg_camera(0.9)
			MOUSE_BUTTON_WHEEL_DOWN: world.zoom_srpg_camera(1.1)
			MOUSE_BUTTON_RIGHT: _cancel()
			MOUSE_BUTTON_LEFT:
				if state in ["move", "attack", "free"]:
					var cell := _pick(event.position)
					if cell == NOWHERE: return
					_set_cursor(cell, false)
					_decide()

func _process(delta: float) -> void:
	if state == "intro" or ended: return
	var step := pad.step(delta)
	if step != Vector2i.ZERO: _direction(step)
	# Right stick: left / right turns to the next quarter view, up / down raises and lowers the
	# camera. LB / RB (and the triggers), R / F and - / = move it while held; the world eases it.
	var look := GamepadInput.stick(true)
	if absf(look.x) > 0.6 and absf(look.x) > absf(look.y) and pad_turn_ready:
		pad_turn_ready = false
		_turn_camera(1 if look.x > 0.0 else -1)
	elif absf(look.x) < 0.3:
		pad_turn_ready = true
	var tilt := look.y if absf(look.y) > absf(look.x) else 0.0
	tilt += float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	if tilt != 0.0: world.tilt_srpg_camera(tilt * 1.2 * delta)
	var zoom := GamepadInput.zoom() + float(GamepadInput.held(JOY_BUTTON_RIGHT_SHOULDER)) - float(GamepadInput.held(JOY_BUTTON_LEFT_SHOULDER))
	zoom += float(Input.is_physical_key_pressed(KEY_EQUAL)) - float(Input.is_physical_key_pressed(KEY_MINUS))
	if zoom != 0.0: world.zoom_srpg_camera(exp(-zoom * 1.4 * delta))
	if mouse_moved and state in ["move", "attack", "free"]:
		mouse_moved = false
		var cell := _pick(mouse_at)
		if cell != NOWHERE and cell != cursor: _set_cursor(cell, false)
	if state == "menu": _place_menu()

func _turn_camera(steps: int) -> void:
	world.turn_srpg_camera(steps * PI * 0.5)
	if hud: hud.set_angle(world.srpg_quarter())

func _on_angle_pressed(index: int) -> void:
	world.set_srpg_quarter(index)
	if hud: hud.set_angle(world.srpg_quarter())

func _on_command_pressed(index: int) -> void:
	if state != "menu": return
	command = index
	_decide()

## A direction key: picks the menu row, or steps the cursor along the grid axis closest to the
## pressed screen direction (turned 45 degrees clockwise, as the quarter view lays the grid's
## axes on the screen diagonals).
func _direction(step: Vector2i) -> void:
	match state:
		"menu":
			if step.y == 0: return
			var index := command
			for i in COMMANDS.size():
				index = posmod(index + step.y, COMMANDS.size())
				if _enabled(index): break
			command = index
			hud.highlight_command(command)
			_paint()
		"move", "attack", "free":
			var basis: Basis = world.camera.global_basis
			var right := Vector2(basis.x.x, basis.x.z).normalized()
			var up := -Vector2(basis.z.x, basis.z.z).normalized()
			var ground := right * step.x - up * step.y + right * -step.y - up * step.x
			_set_cursor(cursor + world._cardinal(ground), true)

func _set_cursor(cell: Vector2i, steer_camera: bool) -> void:
	cursor = cell
	# Mouse picks leave the camera be, or it would slide the ground under the pointer.
	if steer_camera: focus_target = _block_center(cell, 1) + Vector3.UP
	world.set_grid_cursor(cursor)
	if state == "free": _paint()
	_refresh_hud()

## The tactical cell under screen point `at`, marching the view ray down to the ground.
func _pick(at: Vector2) -> Vector2i:
	var camera: Camera3D = world.camera
	var origin := camera.project_ray_origin(at)
	var ray := camera.project_ray_normal(at)
	var t := 0.0
	while t < 160.0:
		var next := t + 0.5
		var point := origin + ray * next
		if point.y <= world.get_visual_height(point.x, point.z):
			var low := t
			var high := next
			for i in 6:
				var middle := (low + high) * 0.5
				var probe := origin + ray * middle
				if probe.y <= world.get_visual_height(probe.x, probe.z): high = middle
				else: low = middle
			return world.world_position_to_tactical_cell(origin + ray * high)
		t = next
	return NOWHERE


# --- World and HUD hooks --------------------------------------------------------

func focus_point() -> Vector3:
	if follow: return follow.position + Vector3.UP
	return focus_target

func marker_holder() -> Node3D:
	if active == null or not active.alive() or state in ["intro", "over"]: return null
	return active.body

func marker_model() -> Node3D:
	return marker_model_of(active) if active else null

## A unit's HP share for its gauge, or -1 for a node that is not in the battle.
func hp_ratio(node: Node3D) -> float:
	for unit in units:
		if unit.visual == node or unit.body == node: return float(unit.hp) / unit.max_hp
	return -1.0

func _refresh_hud() -> void:
	if hud == null or ended: return
	hud.set_order(units, active)
	var hovered: Unit = _occupant(cursor) if state in ["move", "attack", "free"] else null
	var ally: Unit = hovered if hovered and not hovered.enemy else (active if active and not active.enemy else null)
	var foe: Unit = hovered if hovered and hovered.enemy else (active if active and active.enemy else null)
	hud.show_unit(false, ally)
	hud.show_unit(true, foe)


# --- Portraits ------------------------------------------------------------------

## Shoots each unit's head and shoulders from the field with a camera of its own, name labels
## hidden. Headless runs (no renderer) leave the portraits empty.
func _shoot_portraits() -> void:
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE * PORTRAIT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var lens := Camera3D.new()
	lens.fov = 30.0
	viewport.add_child(lens)
	add_child(viewport)
	var labels: Array[Label3D] = []
	for unit in units:
		for label: Label3D in unit.body.find_children("NameLabel", "Label3D", true, false):
			if label.visible:
				label.visible = false
				labels.append(label)
	for unit in units:
		_frame_portrait(lens, unit)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if ended: break
		var image := viewport.get_texture().get_image()
		if image and not image.is_empty(): unit.portrait = ImageTexture.create_from_image(image)
	for label in labels:
		if is_instance_valid(label): label.visible = true
	viewport.queue_free()

## Frames the head from in front: on the head bone when the rig has one (weapons would skew the
## mesh bounds), else on the top of the meshes.
func _frame_portrait(lens: Camera3D, unit: Unit) -> void:
	var forward := _front(unit)
	var skeleton := unit.visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var bone := -1
	if skeleton:
		for index in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(index).to_lower()
			if bone_name == "head": bone = index
			elif bone < 0 and bone_name.contains("head"): bone = index
	if bone >= 0:
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		var height := maxf(head.y - unit.body.global_position.y, 0.3)
		var away := height * 1.3
		lens.global_position = head + forward * away + Vector3.UP * away * 0.12
		lens.look_at(head - Vector3.UP * height * 0.08)
		return
	var box := AABB()
	var first := true
	var model: Node3D = marker_model_of(unit)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	if first: box = AABB(unit.body.global_position, Vector3(0.6, 1.6, 0.6))
	var length := absf(forward.x) * box.size.x + absf(forward.z) * box.size.z
	var target := box.get_center() + forward * length * 0.3
	target.y = box.end.y - box.size.y * 0.2
	var away := maxf(box.size.y, length * 0.5) * 0.75
	lens.global_position = target + forward * away + Vector3.UP * away * 0.15
	lens.look_at(target)

func marker_model_of(unit: Unit) -> Node3D:
	return unit.visual.get_node("Model") if unit.enemy else unit.visual
