extends SceneTree
## godot --headless --path . --script tools/asset_gen/export_world_characters.gd
const Actor = preload("res://scripts/world_jrpg/pixel_actor.gd")
func _init() -> void:
	for kind: String in Actor.PALETTES:
		var path := "res://assets/world_jrpg/%s_atlas.png" % kind
		var error := Actor.atlas(kind).save_png(path)
		if error != OK:
			push_error("Could not export " + path)
			quit(1)
			return
		print("Exported ", path)
	quit()
