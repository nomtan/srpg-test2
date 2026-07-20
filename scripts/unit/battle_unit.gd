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
@warning_ignore("shadowed_global_identifier")
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
var equipped_weapon_id := ""
var equipped_armor_id := ""
var equipped_accessory_id := ""
var temporary_defense_bonus := 0

var body_material: StandardMaterial3D
var base_color: Color
var direction_marker: MeshInstance3D
var status_bars: Sprite3D


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


const FACING_MODEL_ANGLES := [180.0, 90.0, 0.0, -90.0]

var model_instance: Node3D
var animation_player: AnimationPlayer
var weapon_attachment: BoneAttachment3D
var weapon_instance: Node3D
var attack_animation_name: StringName
var model_facing_offset_degrees := 0.0
var animation_profile := "onehand_sword"

const IDLE_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_idle",
	&"animation.onehand_sword_idle",
	&"onehand_sword_idle",
	&"idle",
]
const RUN_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_run",
	&"animation.onehand_sword_run",
	&"animation_run",
	&"animation.run",
	&"onehand_sword_run",
	&"run",
	&"walk",
]
const ATTACK_ANIMATION_NAMES: Array[StringName] = [
	&"animation_onehand_sword_attack",
	&"animation.onehand_sword_attack",
	&"onehand_sword_attack",
	&"attack",
]
const BOW_IDLE_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_idle",
	&"animation.bow_idle",
	&"bow_idle",
]
const BOW_RUN_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_run",
	&"animation.bow_run",
	&"bow_run",
	&"run",
]
const BOW_ATTACK_ANIMATION_NAMES: Array[StringName] = [
	&"animation_bow_attack",
	&"animation.bow_attack",
	&"bow_attack",
]
const CHARACTER_CEL_SHADER := preload("res://assets/shaders/character_cel.gdshader")
const CHARACTER_OUTLINE_SHADER := preload("res://assets/shaders/character_outline.gdshader")
const UNIT_STATUS_BAR_SCRIPT := preload("res://scripts/ui/unit_status_bar_3d.gd")


func setup_visual(
	model_path: String = "",
	model_scale: float = 1.0,
	model_y_offset: float = 0.0,
	facing_offset_degrees: float = 0.0,
	use_cel_shading: bool = false,
	requested_animation_profile: String = "onehand_sword",
	tunic_color: Color = Color.TRANSPARENT,
	accent_color: Color = Color.TRANSPARENT
) -> void:
	model_facing_offset_degrees = facing_offset_degrees
	animation_profile = requested_animation_profile
	body_material = StandardMaterial3D.new()
	if attack_type == AttackType.RANGED:
		base_color = Color("#65c8a0") if team == "player" else Color("#d47a42")
	else:
		base_color = Color("#4ba3ff") if team == "player" else Color("#dc4c4c")
	body_material.albedo_color = base_color
	body_material.metallic = 0.15

	if not model_path.is_empty():
		var packed: PackedScene = load(model_path)
		model_instance = packed.instantiate()
		model_instance.scale = Vector3.ONE * model_scale
		model_instance.position = Vector3(0.0, model_y_offset, 0.0)
		add_child(model_instance)
		if use_cel_shading:
			_apply_cel_shading(model_instance, tunic_color, accent_color)
		var players := model_instance.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animation_player = players[0] as AnimationPlayer
			animation_player.animation_finished.connect(_on_animation_finished)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.28
		capsule.height = 0.9
		body.mesh = capsule
		body.position.y = 0.45
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
	status_bars = UNIT_STATUS_BAR_SCRIPT.new()
	status_bars.configure(team)
	status_bars.position.y = 2.05 if model_instance else 1.45
	add_child(status_bars)
	update_visual_state()
	update_facing_visual()
	refresh_status_bars()
	play_idle_animation()


func _apply_cel_shading(root: Node, tunic_color: Color, accent_color: Color) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material := mesh_instance.get_active_material(surface_index)
			var surface_color := Color.WHITE
			if source_material is BaseMaterial3D:
				surface_color = (source_material as BaseMaterial3D).albedo_color
				if source_material.resource_name == "tunic" and tunic_color.a > 0.0:
					surface_color = tunic_color
				elif source_material.resource_name == "accent" and accent_color.a > 0.0:
					surface_color = accent_color

			var outline_material := ShaderMaterial.new()
			outline_material.shader = CHARACTER_OUTLINE_SHADER
			outline_material.set_shader_parameter("outline_color", Color("#050506"))
			outline_material.set_shader_parameter("outline_width", 0.012)

			var cel_material := ShaderMaterial.new()
			cel_material.shader = CHARACTER_CEL_SHADER
			cel_material.set_shader_parameter("base_color", surface_color)
			cel_material.set_shader_parameter("shadow_tone", 0.42)
			cel_material.set_shader_parameter("band_split", 0.5)
			cel_material.next_pass = outline_material
			mesh_instance.set_surface_override_material(surface_index, cel_material)


func play_walk_animation() -> void:
	_play_animation(BOW_RUN_ANIMATION_NAMES if animation_profile == "bow" else RUN_ANIMATION_NAMES, Animation.LOOP_LINEAR)


func stop_walk_animation() -> void:
	play_idle_animation()


func play_idle_animation() -> void:
	attack_animation_name = &""
	_play_animation(BOW_IDLE_ANIMATION_NAMES if animation_profile == "bow" else IDLE_ANIMATION_NAMES, Animation.LOOP_LINEAR)


func play_attack_animation() -> void:
	var candidates := BOW_ATTACK_ANIMATION_NAMES if animation_profile == "bow" else ATTACK_ANIMATION_NAMES
	attack_animation_name = _find_animation(candidates)
	if attack_animation_name.is_empty():
		return
	var animation := animation_player.get_animation(attack_animation_name)
	animation.loop_mode = Animation.LOOP_NONE
	animation_player.play(attack_animation_name)


func _play_animation(candidates: Array[StringName], loop_mode: Animation.LoopMode) -> void:
	var animation_name := _find_animation(candidates)
	if animation_name.is_empty():
		return
	var animation := animation_player.get_animation(animation_name)
	animation.loop_mode = loop_mode
	animation_player.play(animation_name)


func _find_animation(candidates: Array[StringName]) -> StringName:
	if not animation_player:
		return &""
	for candidate in candidates:
		if animation_player.has_animation(candidate):
			return candidate
	for available in animation_player.get_animation_list():
		for candidate in candidates:
			if String(available).ends_with("/" + String(candidate)):
				return available
	return &""


func _on_animation_finished(finished_animation: StringName) -> void:
	if not attack_animation_name.is_empty() and finished_animation == attack_animation_name:
		play_idle_animation()


func equip_weapon_visual(
	model_path: String,
	bone_name: String = "hand_R",
	local_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 180.0),
	local_scale: float = 0.78
) -> void:
	if weapon_attachment:
		weapon_attachment.queue_free()
		weapon_attachment = null
		weapon_instance = null
	if not model_instance or model_path.is_empty():
		return

	var skeletons := model_instance.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("Cannot equip weapon: character model has no Skeleton3D")
		return
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone(bone_name) < 0:
		push_warning("Cannot equip weapon: bone '%s' was not found" % bone_name)
		return

	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_name = bone_name
	skeleton.add_child(weapon_attachment)

	var packed: PackedScene = load(model_path)
	if not packed:
		push_warning("Cannot equip weapon: failed to load '%s'" % model_path)
		return
	weapon_instance = packed.instantiate()
	weapon_instance.name = "EquippedWeapon"
	weapon_instance.rotation_degrees = local_rotation_degrees
	weapon_instance.scale = Vector3.ONE * local_scale
	weapon_attachment.add_child(weapon_instance)


func face_toward(target_pos: Vector2i) -> void:
	var delta := target_pos - Vector2i(grid_x, grid_z)
	face_along_grid_delta(delta)


func face_along_grid_delta(delta: Vector2i) -> void:
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
	if model_instance:
		model_instance.rotation_degrees.y = FACING_MODEL_ANGLES[int(facing)] + model_facing_offset_degrees


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
	refresh_status_bars()


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
	refresh_status_bars()

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
	refresh_status_bars()
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
	refresh_status_bars()


func refresh_status_bars() -> void:
	if status_bars:
		status_bars.update_values(hp, max_hp, ap, max_ap)

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
