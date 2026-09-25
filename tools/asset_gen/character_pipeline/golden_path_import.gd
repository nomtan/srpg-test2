@tool
extends EditorScenePostImport
## Keep the GLB's texture and UVs while applying the shared runtime toon look.
const CHARACTER_TOON = preload("res://assets/characters/_shared/materials/character_toon.gdshader")

func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				push_error("Golden Path requires an original Base Color texture: %s surface %d" % [mesh.name, surface])
				return null
			var toon := ShaderMaterial.new()
			toon.shader = CHARACTER_TOON
			toon.set_shader_parameter("base_color_texture", source.albedo_texture)
			mesh.set_surface_override_material(surface, toon)
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for clip in ["idle", "walk"]:
			if player.has_animation(clip):
				player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return scene
