@tool
extends EditorScenePostImport
## Eevee's Shader to RGB is not portable through glTF. Restore the same look here.
const TOON = preload("res://assets/characters/tripo_hiro/hero_toon.gdshader")
const OUTLINE = preload("res://assets/characters/tripo_hiro/hero_outline.gdshader")

func _post_import(scene: Node) -> Object:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "Toon_Outline":
			var ink := ShaderMaterial.new()
			ink.shader = OUTLINE
			mesh.material_override = ink
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				push_error("Tripo hero requires its original Base Color texture")
				return null
			var toon := ShaderMaterial.new()
			toon.shader = TOON
			toon.set_shader_parameter("base_color_texture", source.albedo_texture)
			mesh.set_surface_override_material(surface, toon)
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for clip in ["idle", "walk", "run"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	scene.set_meta("hero_toon_version", 1)
	return scene
