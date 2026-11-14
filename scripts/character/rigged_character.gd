extends Node3D
## A whole-character model with its own skeleton and clips (tools/asset_gen/character_pipeline/
## build_rigged_character.py), outside the Body + Face standard. It offers the roster actor's
## surface (character_id, display_name, dialogue, animation_player, play_animation) so the
## explorer and the roster can use it like a tripo_roster character. Its bones carry humanoid_v1
## names, so SwordCombat equips it (the loadout comes from SwordCombat.LOADOUTS, sword and shield by
## default) and the shared procedural stance, gait and attack clips drive it.
## Drawn flat like the other Tripo characters: the shared character toon shader with
## shade_strength 0 shows the texture's own painted shading, so the scene's lights and shadows do
## not shade it; night_amount 1 still darkens it with the night (field_weather.gd's night_tint). The
## scene's "night_shade" meta does the same for its weapons (SwordCombat).

const ForearmTwist := preload("res://scripts/character/forearm_twist.gd")
const CHARACTER_TOON := preload("res://assets/characters/_shared/materials/character_toon.gdshader")

## Albedo texture -> the flat toon material drawing it, shared by every instance.
static var _flat_materials := {}

@export var character_id := ""
@export var display_name := ""
@export var dialogue: PackedStringArray = ["……。"]

var animation_player: AnimationPlayer


func _ready() -> void:
	_apply_flat_toon()
	# Deferred: the explorer equips the model right after adding it, and the twist must come after the
	# equipment's own skeleton modifiers.
	_add_forearm_twist.call_deferred()
	animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null: return
	var rig := animation_player.get_parent()
	var looping: Array = rig.get_meta("extras", {}).get("looping_clips", ["idle", "walk", "run"]) if rig else []
	for clip: String in looping:
		if animation_player.has_animation(clip):
			animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	play_animation("idle")


func play_animation(clip: String) -> bool:
	if animation_player == null or not animation_player.has_animation(clip):
		return false
	animation_player.play(clip, 0.15)
	return true



func _add_forearm_twist() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.has_node("ForearmTwist"): return
	var twist: SkeletonModifier3D = ForearmTwist.new()
	twist.name = "ForearmTwist"
	skeleton.add_child(twist)
	if not twist.has_twist_bones(): twist.queue_free()


## Replaces the imported (lit) materials with the flat toon on every mesh of the model. Only
## instance overrides are set; the imported resources stay untouched. The equipment SwordCombat
## adds later gets its own toon there.
func _apply_flat_toon() -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null: continue
			if not _flat_materials.has(source.albedo_texture):
				var toon := ShaderMaterial.new()
				toon.shader = CHARACTER_TOON
				toon.set_shader_parameter("base_color_texture", source.albedo_texture)
				toon.set_shader_parameter("shade_strength", 0.0)
				toon.set_shader_parameter("night_amount", 1.0)
				_flat_materials[source.albedo_texture] = toon
			mesh.set_surface_override_material(surface, _flat_materials[source.albedo_texture])
