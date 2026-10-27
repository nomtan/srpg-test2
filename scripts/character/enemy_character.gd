extends Node3D
## Field enemy backed by one rigged GLB (assets/characters/enemy/<id>/model.glb, built by
## tools/asset_gen/character_pipeline/build_enemy.py) with the clips
## idle / walk / attack / guard / hit / death. The visual faces +Z like the roster.
## The weapon and shield are separate GLBs (assets/characters/enemy/equipment/{weapon,shield}/<id>)
## held at the sockets the body GLB records, and can be swapped with set_weapon / set_shield.
## Enemies whose GLB records no sockets (the wolf, the grimm) carry nothing; their ids stay "none".
## Defeated, it falls, crumbles into dust and comes back where it first stood.

signal defeated
signal respawned

const CLIPS := ["idle", "walk", "attack", "guard", "hit", "death"]
const LOOPING := ["idle", "walk"]
## Attack clips an enemy may have besides "attack" (the wolf: claw swipe = attack, leap and bite =
## attack_bite; the grimm: antler gore = attack, lunging bite = attack_bite); the demo's attack steps
## take turns through those present.
const EXTRA_ATTACKS := ["attack_bite"]
const EQUIPMENT_ROOT := "res://assets/characters/enemy/equipment"
const DISSOLVE_SHADER := preload("res://assets/characters/_shared/materials/enemy_dissolve.gdshader")
## Demo order: [clip, seconds]; 0 waits for the clip to end. "walk" paces forward and back,
## "death" runs the whole fall, dust and return.
const DEMO := [["idle", 2.0], ["walk", 3.0], ["attack", 0.0], ["idle", 0.6], ["attack", 0.0],
	["guard", 1.6], ["idle", 0.8], ["hit", 0.0], ["idle", 0.8], ["death", 0.0]]
const WALK_SPEED := 1.3
const WALK_REACH := 2.0
## Idle pause after reacting to a blow before the demo carries on.
const RECOVER := 1.5
## Defeat timing (seconds): lying still after the fall, crumbling, gone, then fading back in.
const LIE_STILL := 0.5
const CRUMBLE := 1.6
const GONE := 2.0
const REFORM := 0.8

@export var enemy_id := "goblin"
@export var display_name := "ゴブリン"
@export var model_scene: PackedScene
@export_enum("none", "scimitar", "hand_axe", "longsword", "staff") var weapon_id := "scimitar"
@export_enum("none", "round", "kite") var shield_id := "round"
@export var max_hp := 3
## Cycles through every clip on its own so the motions can be watched in the field.
@export var demo := false
## Shows the current clip under the name.
@export var show_clip_label := false

static var _materials: Dictionary = {}
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var hp := 0
## Returns the ground height at (x, z); set by the world so walking follows the terrain.
var ground_height: Callable
var _sockets: Dictionary = {}
var _demo_step := -1
var _timer := 0.0
var _await_clip := false
var _reacting := false
var _defeated := false
var _walk_origin := Vector3.ZERO
var _home: Transform3D
var _attack_turn := 0


func _ready() -> void:
	hp = max_hp
	_home = transform
	if model_scene and $Model.get_child_count() == 0:
		$Model.add_child(model_scene.instantiate())
	skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	_read_sockets()
	set_weapon(weapon_id)
	set_shield(shield_id)
	_apply_materials($Model)
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player:
		for clip in CLIPS + EXTRA_ATTACKS:
			if animation_player.has_animation(clip):
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		animation_player.animation_finished.connect(_on_clip_finished)
	$NameLabel.text = display_name
	play_animation("idle")
	if demo: _next_demo_step()


func set_weapon(id: String) -> void:
	weapon_id = id
	_equip("weapon", id)


func set_shield(id: String) -> void:
	shield_id = id
	_equip("shield", id)


func play_animation(clip: String, blend := 0.15) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, blend)
	# Restart so repeated blows and swings read as separate motions.
	animation_player.seek(0.0, true)
	_show_clip(clip)
	return true


## "attack" followed by whichever EXTRA_ATTACKS the model has.
func attack_clips() -> Array:
	var clips := ["attack"]
	for clip in EXTRA_ATTACKS:
		if animation_player and animation_player.has_animation(clip):
			clips.append(clip)
	return clips


func is_dead() -> bool:
	return hp <= 0


## A player blow: guards now and then, flinches otherwise, and falls on the last hit point.
func take_hit() -> void:
	if is_dead() or _defeated:
		return
	_reacting = true
	_timer = 0.0
	_await_clip = false
	if animation_player and animation_player.current_animation != "guard" and randf() < 0.25:
		play_animation("guard", 0.05)
		_timer = 0.8
		return
	hp -= 1
	if hp > 0:
		play_animation("hit", 0.05)
		_await_clip = true
		return
	_reacting = false
	defeated.emit()
	_defeat()


## Falls, lies still, crumbles to dust and comes back at its first spot.
func _defeat() -> void:
	_defeated = true
	_timer = 0.0
	_await_clip = false
	hp = 0
	play_animation("death", 0.05)
	await get_tree().create_timer(animation_player.get_animation("death").length + LIE_STILL).timeout
	$NameLabel.visible = false
	_spawn_dust()
	await _fade_dissolve(0.0, 1.0, CRUMBLE)
	$Model.visible = false
	await get_tree().create_timer(GONE).timeout
	transform = _home
	if ground_height.is_valid():
		position.y = ground_height.call(position.x, position.z) + 0.05
	hp = max_hp
	play_animation("idle", 0.0)
	$Model.visible = true
	$NameLabel.visible = true
	await _fade_dissolve(1.0, 0.0, REFORM)
	_defeated = false
	respawned.emit()
	if demo:
		_step_done()


func _fade_dissolve(from: float, to: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_dissolve, from, to, seconds)
	await tween.finished


func _set_dissolve(amount: float) -> void:
	for mesh: MeshInstance3D in $Model.find_children("*", "MeshInstance3D", true, false):
		mesh.set_instance_shader_parameter("dissolve", amount)


## Ash and embers rising from along the bones, wherever the body lies.
func _spawn_dust() -> void:
	var points := PackedVector3Array()
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		if parent < 0: continue
		var a := to_local(skeleton.to_global(skeleton.get_bone_global_pose(parent).origin))
		var b := to_local(skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))
		for k in 12:
			points.append(a.lerp(b, randf()) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.12)
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 220
	dust.lifetime = 1.4
	dust.one_shot = true
	dust.explosiveness = 0.0
	dust.randomness = 0.6
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	dust.emission_points = points
	dust.direction = Vector3.UP
	dust.spread = 40.0
	dust.initial_velocity_min = 0.3
	dust.initial_velocity_max = 1.1
	dust.gravity = Vector3(0, 0.9, 0)
	dust.damping_min = 0.6
	dust.damping_max = 1.2
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0.15))
	dust.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.62, 0.3, 1.0))
	ramp.set_color(1, Color(0.25, 0.22, 0.24, 0.0))
	ramp.add_point(0.25, Color(0.55, 0.48, 0.46, 0.9))
	dust.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	dust.mesh = quad
	add_child(dust)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)


func _read_sockets() -> void:
	if skeleton == null: return
	for node: Node in [skeleton, skeleton.get_parent()]:
		var extras = node.get_meta("extras", {}) if node else {}
		if not extras is Dictionary: continue
		for key in ["weapon_socket", "shield_socket"]:
			var socket = extras.get(key)
			if socket is Dictionary and skeleton.find_bone(socket.bone) >= 0:
				var o: Array = socket.origin
				var b: Array = socket.basis
				var rest := Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), Vector3(o[0], o[1], o[2]))
				_sockets[key.trim_suffix("_socket")] = {"bone": socket.bone, "rest": rest}


## Replaces what the hand holds; the equipment GLB is posed in the socket's frame.
func _equip(kind: String, id: String) -> void:
	if skeleton == null or not _sockets.has(kind): return
	var holder_name := kind.capitalize() + "Socket"
	var attachment := skeleton.get_node_or_null(holder_name) as BoneAttachment3D
	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = holder_name
		attachment.bone_name = _sockets[kind].bone
		skeleton.add_child(attachment)
		var socket_frame := Node3D.new()
		socket_frame.name = "Frame"
		var bone := skeleton.find_bone(_sockets[kind].bone)
		socket_frame.transform = skeleton.get_bone_global_rest(bone).affine_inverse() * (_sockets[kind].rest as Transform3D)
		attachment.add_child(socket_frame)
	var frame := attachment.get_node("Frame") as Node3D
	for child in frame.get_children():
		child.queue_free()
	if id == "none" or id.is_empty(): return
	var scene := load("%s/%s/%s/model.glb" % [EQUIPMENT_ROOT, kind, id]) as PackedScene
	if scene == null:
		push_error("Missing enemy %s: %s" % [kind, id])
		return
	var part := scene.instantiate()
	frame.add_child(part)
	_apply_materials(part)


## The painted Tripo textures already carry their shading, so everything renders flat with the
## dissolve shader; one material per texture, shared by every enemy.
func _apply_materials(root: Node) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null: continue
			var key := source.albedo_texture.get_instance_id()
			if not _materials.has(key):
				var material := ShaderMaterial.new()
				material.shader = DISSOLVE_SHADER
				material.set_shader_parameter("base_color_texture", source.albedo_texture)
				_materials[key] = material
			mesh.set_surface_override_material(surface, _materials[key])


func _process(delta: float) -> void:
	if animation_player and animation_player.current_animation == "walk":
		var step := Vector3(sin(rotation.y), 0, cos(rotation.y)) * WALK_SPEED * delta
		position += step
		if ground_height.is_valid():
			position.y = ground_height.call(position.x, position.z) + 0.05
		# Turn back at the end of the beat.
		if position.distance_to(_walk_origin) > WALK_REACH and (position - _walk_origin).dot(step) > 0.0:
			rotation.y += PI
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_step_done()


func _on_clip_finished(_clip: StringName) -> void:
	if _await_clip:
		_step_done()


func _step_done() -> void:
	_await_clip = false
	_timer = 0.0
	if _defeated:
		return
	if _reacting:
		_reacting = false
		play_animation("idle", 0.2)
		if demo: _timer = RECOVER
		return
	if demo: _next_demo_step()


func _next_demo_step() -> void:
	_demo_step = (_demo_step + 1) % DEMO.size()
	var clip: String = DEMO[_demo_step][0]
	_timer = DEMO[_demo_step][1]
	if clip == "death":
		_defeat()
		return
	if clip == "walk":
		_walk_origin = position
	if clip == "attack":
		var attacks := attack_clips()
		clip = attacks[_attack_turn % attacks.size()]
		_attack_turn += 1
	_await_clip = _timer <= 0.0
	play_animation(clip)


func _show_clip(clip: String) -> void:
	if show_clip_label:
		$NameLabel.text = "%s\n[%s]" % [display_name, clip]
