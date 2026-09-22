@tool
extends EditorScenePostImport
## Eevee Shader to RGB is reconstructed with the shared Godot three-band shader.
const TOON = preload("res://assets/characters/tripo_roster/toon.gdshader")
const OUTLINE = preload("res://assets/characters/tripo_roster/outline.gdshader")

func _post_import(scene: Node) -> Object:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).ends_with("_Outline"):
			var ink := ShaderMaterial.new()
			ink.shader = OUTLINE
			mesh.material_override = ink
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				push_error("Tripo character requires the unchanged source Base Color texture")
				return null
			var toon := ShaderMaterial.new()
			toon.shader = TOON
			toon.set_shader_parameter("base_color_texture", source.albedo_texture)
			mesh.set_surface_override_material(surface, toon)
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in ["idle", "walk", "run"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	scene.set_meta("tripo_roster_version", 1)
	return scene
