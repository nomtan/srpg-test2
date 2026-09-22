@tool
extends EditorScenePostImport
## Shader-to-RGB cannot travel through glTF; restore its three bands on import.
const TOON = preload("res://assets/characters/meshy_hero2/hero2_toon.gdshader")
const OUTLINE = preload("res://assets/characters/meshy_hero2/hero2_outline.gdshader")

func _post_import(scene: Node) -> Object:
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.name == "Toon_Outline":
			var outline := ShaderMaterial.new()
			outline.resource_name = "Hero2_Outline"
			outline.shader = OUTLINE
			mesh.material_override = outline
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null or source.albedo_texture == null:
				push_error("Hero2 toon import needs the original Base Color texture")
				return null
			var material := ShaderMaterial.new()
			material.resource_name = "Hero2_Toon"
			material.shader = TOON
			material.set_shader_parameter("base_color_texture", source.albedo_texture)
			mesh.set_surface_override_material(surface, material)
	scene.set_meta("hero2_toon_version", 1)
	return scene
