extends Node3D
## A guardian: the stand-like spirit one character can equip (scenes/characters/guardians/<id>.tscn).
## Hidden until summon(): it forms as ink from the tail up (guardian_shadow.gdshader `reveal`) with brush
## strokes swirling in (GuardianInkFx) and roars; dismiss() erases it from the head down as the strokes
## scatter. While out it hovers behind its owner's left shoulder (follow_offset) and faces the way the
## owner faces. Stats / skills granted by a guardian come later; this is the visual only.

const SHADER := preload("res://assets/characters/_shared/materials/guardian_shadow.gdshader")
const InkFx := preload("res://scripts/character/guardian_ink_fx.gd")
const LOOPING := ["idle"]
const ACTIONS := ["attack", "attack_bite", "roar"]

signal summoned
signal dismissed

@export var guardian_id := "shadow1"
@export var display_name := "影（シャドウ）"
@export var model_scene: PackedScene
## Hover point in the owner's facing frame: +X ahead, +Y up, +Z to the owner's right.
@export var follow_offset := Vector3(-2.0, 0.3, -0.8)
## Guardian height in metres at the Model's scale (for the ink strokes).
@export var height := 6.0
@export var summon_seconds := 1.1
@export var dismiss_seconds := 0.85
## Followed while summoned: a node whose `model` child (if any) gives the facing, +X forward
## (the explorer); otherwise its own -Z.
var follow_target: Node3D
## "hidden", "appearing", "present" or "leaving".
var state := "hidden"
var animation_player: AnimationPlayer
var ink_fx: Node3D
var _meshes: Array[MeshInstance3D] = []
var _materials := {}
var _tween: Tween


func _ready() -> void:
	if model_scene and $Model.get_child_count() == 0:
		$Model.add_child(model_scene.instantiate())
	_apply_materials($Model)
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player:
		for clip in animation_player.get_animation_list():
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
		animation_player.animation_finished.connect(_on_clip_finished)
	ink_fx = InkFx.new()
	ink_fx.name = "InkFx"
	ink_fx.height = height
	add_child(ink_fx)
	_set_reveal(0.0)
	visible = false


func is_summoned() -> bool:
	return state == "appearing" or state == "present"


## Brings the guardian out next to its owner. False if it is already out (or coming out).
func summon() -> bool:
	if is_summoned(): return false
	if state == "hidden": snap_to_target()
	state = "appearing"
	visible = true
	_play("roar")
	ink_fx.play_summon(summon_seconds)
	# The body starts forming once the first strokes have arrived.
	var from := _reveal()
	_restart_tween()
	_tween.tween_method(_set_reveal, from, 1.0, summon_seconds * 0.8 * (1.0 - from)).set_delay(summon_seconds * 0.2 * (1.0 - from)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		state = "present"
		summoned.emit())
	return true


## Returns the guardian. False if it is already gone (or going).
func dismiss() -> bool:
	if not is_summoned(): return false
	state = "leaving"
	ink_fx.play_dismiss(dismiss_seconds)
	var from := _reveal()
	_restart_tween()
	_tween.tween_method(_set_reveal, from, 0.0, dismiss_seconds * 0.8 * from).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_interval(dismiss_seconds * 0.25)
	_tween.tween_callback(func() -> void:
		state = "hidden"
		visible = false
		dismissed.emit())
	return true


func toggle() -> bool:
	return dismiss() if is_summoned() else summon()


## Plays a one-shot action (attack / attack_bite / roar) and returns to idle. Only while out.
func act(clip := "attack") -> bool:
	if state != "present" or not animation_player or not animation_player.has_animation(clip): return false
	_play(clip)
	return true


## Jumps straight to the hover point beside the follow target.
func snap_to_target() -> void:
	if not follow_target: return
	var frame := _target_frame()
	global_position = frame.origin
	global_basis = Basis(Vector3.UP, _yaw(frame.basis))


func _process(delta: float) -> void:
	if not follow_target or state == "hidden": return
	var frame := _target_frame()
	if global_position.distance_to(frame.origin) > 12.0:
		snap_to_target()
		return
	# Trails a little behind the owner, like a spirit dragged along.
	global_position = global_position.lerp(frame.origin, 1.0 - exp(-5.0 * delta))
	var yaw := lerp_angle(global_rotation.y, _yaw(frame.basis), 1.0 - exp(-6.0 * delta))
	global_basis = Basis(Vector3.UP, yaw)


## Hover point and facing basis (+X forward) of the follow target.
func _target_frame() -> Transform3D:
	var facing: Node3D = follow_target
	var model = follow_target.get("model")
	if model is Node3D:
		facing = model
	var forward := Vector3.FORWARD
	if facing != follow_target:
		forward = facing.global_basis.x
	else:
		forward = -facing.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.RIGHT
	var right := forward.cross(Vector3.UP)
	var basis := Basis(forward, Vector3.UP, right)
	return Transform3D(basis, follow_target.global_position + basis * follow_offset)


## Yaw that turns the guardian (which faces +Z) to the facing basis' +X.
func _yaw(basis: Basis) -> float:
	return atan2(basis.x.x, basis.x.z)


func _play(clip: String) -> void:
	if animation_player and animation_player.has_animation(clip):
		animation_player.play(clip, 0.15)


func _on_clip_finished(clip: StringName) -> void:
	if String(clip) in ACTIONS and is_summoned():
		_play("idle")


func _restart_tween() -> void:
	if _tween: _tween.kill()
	_tween = create_tween()


func _reveal() -> float:
	return float(_meshes[0].get_instance_shader_parameter("reveal")) if not _meshes.is_empty() else 0.0


func _set_reveal(amount: float) -> void:
	for mesh in _meshes:
		mesh.set_instance_shader_parameter("reveal", amount)


## The painted Tripo texture carries its own shading; render it flat with the reveal shader.
func _apply_materials(root: Node) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		_meshes.append(mesh)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null: continue
			var key := source.albedo_texture.get_instance_id()
			if not _materials.has(key):
				var material := ShaderMaterial.new()
				material.shader = SHADER
				material.set_shader_parameter("base_color_texture", source.albedo_texture)
				_materials[key] = material
			mesh.set_surface_override_material(surface, _materials[key])
