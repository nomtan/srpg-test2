class_name BattleUnit
extends Node3D

enum AttackType { MELEE, RANGED }
enum FacingDirection { NORTH, EAST, SOUTH, WEST }
enum EnemyType { AGGRESSIVE, DEFENSIVE, SNIPER, GUARD, BOSS }
enum ElementType { NONE, EARTH, WATER, WIND, FIRE, THUNDER, ICE, LIGHT, DARK }

var unit_id: String
var unit_name: String
var grid_x: int
var grid_z: int
var move_range: int = 4
var jump_height: int = 1
var team: String
var has_acted: bool = false
var has_moved: bool = false
var has_used_action: bool = false
var max_hp: int = 100
var hp: int = 100
var attack_power: int = 30
var defense: int = 5
var attack_type: AttackType = AttackType.MELEE
var accuracy: int = 90
var evasion: int = 10
var min_attack_range: int = 1
var max_attack_range: int = 1
var is_dead: bool = false
var facing: FacingDirection = FacingDirection.SOUTH
var enemy_type: EnemyType = EnemyType.AGGRESSIVE
var job_id := ""
var job_name := ""
var element: ElementType = ElementType.NONE
var max_ap := 30
var ap := 30
var skill_ids: Array[String] = []
const MAX_EQUIPPED_SKILLS := 6
var learned_skill_ids: Array[String] = []
var equipped_skill_ids: Array[String] = []
var main_job_id := ""
var main_job_name := ""
var sub_job_id := ""
var sub_job_name := ""
var unlocked_job_ids: Array[String] = []
var job_levels: Dictionary = {}
var job_exps: Dictionary = {}
var level := 1
var exp := 0
var exp_to_next_level := 100
var job_level := 1
var job_exp := 0
var job_exp_to_next_level := 50
var strength := 10
var dexterity := 10
var vitality := 10
var mind := 10
var intelligence := 10
var agility := 10
var base_str := 10
var base_dex := 10
var base_vit := 10
var base_mnd := 10
var base_int := 10
var base_agi := 10
var build_stats: BuildStats
var ct := 0
var is_current_actor := false
var temporary_defense_bonus := 0

var body_material: StandardMaterial3D
var base_color: Color
var direction_marker: MeshInstance3D


func configure(
	id: String,
	display_name: String,
	grid_pos: Vector2i,
	unit_team: String,
	movement: int = 4,
	jump: int = 1
) -> void:
	unit_id = id
	unit_name = display_name
	grid_x = grid_pos.x
	grid_z = grid_pos.y
	team = unit_team
	move_range = movement
	jump_height = jump
	name = unit_id


func setup_visual() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 0.9
	body.mesh = capsule
	body.position.y = 0.45
	body_material = StandardMaterial3D.new()
	if attack_type == AttackType.RANGED:
		base_color = Color("#65c8a0") if team == "player" else Color("#d47a42")
	else:
		base_color = Color("#4ba3ff") if team == "player" else Color("#dc4c4c")
	body_material.albedo_color = base_color
	body_material.metallic = 0.15
	body.material_override = body_material
	add_child(body)

	var marker := MeshInstance3D.new()
	direction_marker = marker
	var cone := PrismMesh.new()
	cone.size = Vector3(0.22, 0.25, 0.22)
	marker.mesh = cone
	marker.position = Vector3(0, 1.05, -0.05)
	marker.material_override = body_material
	add_child(marker)
	update_visual_state()
	update_facing_visual()


func face_toward(target_pos: Vector2i) -> void:
	var delta := target_pos - Vector2i(grid_x, grid_z)
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		facing = FacingDirection.EAST if delta.x > 0 else FacingDirection.WEST
	elif delta.y != 0:
		facing = FacingDirection.SOUTH if delta.y > 0 else FacingDirection.NORTH
	update_facing_visual()


func set_facing(direction: FacingDirection) -> void:
	facing = direction
	update_facing_visual()


func update_facing_visual() -> void:
	if not direction_marker: return
	var offsets := [Vector3(0, 1.05, -0.28), Vector3(0.28, 1.05, 0), Vector3(0, 1.05, 0.28), Vector3(-0.28, 1.05, 0)]
	direction_marker.position = offsets[int(facing)]


func set_selected(selected: bool) -> void:
	if body_material:
		body_material.emission_enabled = selected
		body_material.emission = Color("#66d9ff") if team == "player" else Color("#ff7777")
		body_material.emission_energy_multiplier = 0.7


func mark_acted(moved: bool = true) -> void:
	has_moved = moved
	has_acted = true
	update_visual_state()


func set_combat_stats(
	new_max_hp: int, power: int, armor: int, hit: int, dodge: int,
	type: AttackType = AttackType.MELEE, min_range: int = 1, max_range: int = 1
) -> void:
	max_hp = new_max_hp
	hp = max_hp
	attack_power = power
	defense = armor
	accuracy = hit
	evasion = dodge
	attack_type = type
	min_attack_range = min_range
	max_attack_range = max_range


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp == 0:
		die()
	update_visual_state()


func die() -> void:
	is_dead = true
	visible = false


func is_alive() -> bool:
	return not is_dead and hp > 0


func get_status_name() -> String:
	if is_dead: return "Defeated"
	return "Acted" if has_acted else "Ready"

func configure_role(id: String, display_name: String, affinity: ElementType, new_max_ap: int, skills: Array[String]) -> void:
	job_id = id
	job_name = display_name
	main_job_id = id
	main_job_name = display_name
	sub_job_id = id
	sub_job_name = display_name
	element = affinity
	max_ap = new_max_ap
	ap = max_ap
	skill_ids = skills.duplicate()
	equipped_skill_ids = skills.duplicate()
	job_levels[id] = job_level
	job_exps[id] = job_exp

func get_job_level_for(id: String) -> int: return int(job_levels.get(id, 1))
func get_job_exp_for(id: String) -> int: return int(job_exps.get(id, 0))
func set_job_level_for(id: String, value: int) -> void: job_levels[id] = value
func set_job_exp_for(id: String, value: int) -> void: job_exps[id] = value

func equip_skill(id: String) -> bool:
	if id in equipped_skill_ids: return true
	if equipped_skill_ids.size() >= MAX_EQUIPPED_SKILLS: return false
	equipped_skill_ids.append(id); return true
func unequip_skill(id: String) -> void: equipped_skill_ids.erase(id)
func clear_equipped_skills() -> void: equipped_skill_ids.clear()
func get_build_data() -> Dictionary: return {"unit_id": unit_id, "main_job_id": main_job_id, "sub_job_id": sub_job_id, "equipped_skill_ids": equipped_skill_ids.duplicate()}

func add_exp(amount: int, growth: Dictionary) -> Array[Dictionary]:
	exp += amount
	var results: Array[Dictionary] = []
	while exp >= exp_to_next_level:
		exp -= exp_to_next_level
		level += 1
		results.append({"unit": self, "new_level": level, "growth": apply_level_growth(growth)})
	return results

func apply_level_growth(growth: Dictionary) -> Dictionary:
	max_hp += int(growth.get("max_hp", 5)); max_ap += int(growth.get("max_ap", 1))
	attack_power += int(growth.get("attack_power", 1)); defense += int(growth.get("defense", 1))
	accuracy += int(growth.get("accuracy", 1)); evasion += int(growth.get("evasion", 1))
	base_str += int(growth.get("str", growth.get("attack_power", 1)))
	base_dex += int(growth.get("dex", growth.get("accuracy", 1)))
	base_vit += int(growth.get("vit", growth.get("defense", 1)))
	base_mnd += int(growth.get("mnd", 1))
	base_int += int(growth.get("int", 1))
	base_agi += int(growth.get("agi", growth.get("evasion", 1)))
	hp = max_hp; ap = max_ap
	return growth

func refresh_build_stats(status_calculator: Node) -> void:
	var hp_ratio := float(hp) / float(max_hp) if max_hp > 0 else 1.0
	build_stats = status_calculator.calculate_build_stats(self)
	var final_stats: Dictionary = status_calculator.calculate_final_base_stats(self)
	strength = int(final_stats.str); dexterity = int(final_stats.dex); vitality = int(final_stats.vit)
	mind = int(final_stats.mnd); intelligence = int(final_stats.int); agility = int(final_stats.agi)
	max_hp = status_calculator.calculate_max_hp(self, final_stats)
	attack_power = build_stats.attack_power; defense = build_stats.defense
	accuracy = build_stats.accuracy; evasion = build_stats.evasion
	move_range = build_stats.move_range; jump_height = build_stats.jump_height
	hp = clampi(roundi(max_hp * hp_ratio), 1, max_hp) if not is_dead else 0

func add_job_exp(amount: int) -> Array[Dictionary]:
	var target_job := main_job_id if not main_job_id.is_empty() else job_id
	job_exp = get_job_exp_for(target_job) + amount
	job_level = get_job_level_for(target_job)
	var results: Array[Dictionary] = []
	while job_exp >= job_exp_to_next_level:
		job_exp -= job_exp_to_next_level
		job_level += 1
		set_job_level_for(target_job, job_level)
		results.append({"unit": self, "job_level": job_level})
	set_job_exp_for(target_job, job_exp)
	return results


func reset_action_state() -> void:
	has_acted = false
	has_moved = false
	has_used_action = false
	temporary_defense_bonus = 0
	update_visual_state()

func add_ct(amount: int) -> void: ct += amount
func is_ready_to_act() -> bool: return ct >= 100 and is_alive()
func reset_ct_after_action() -> void: ct = 0
func reset_ct_after_wait() -> void: ct = 20


func update_visual_state() -> void:
	if not body_material:
		return
	visible = not is_dead
	body_material.albedo_color = base_color.darkened(0.55) if has_acted else base_color


func snap_to_grid(grid: GridSystem) -> void:
	position = grid.grid_to_world(Vector2i(grid_x, grid_z), 0.05)
