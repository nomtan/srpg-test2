extends SceneTree
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
var actor
var frame := 0
func _initialize() -> void:
	call_deferred("setup")
func setup() -> void:
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50, 30, 0); root.add_child(light)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.6,0.7,0.8); env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; root.add_child(env)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10,10); ground.mesh = pm; root.add_child(ground)
	actor = Explorer.new(); root.add_child(actor)
	actor.world_facing = Vector3(1,0,0)
	var cam := Camera3D.new(); root.add_child(cam)
	cam.position = Vector3(0.5, 1.2, 3.2); cam.look_at(Vector3(0,0.7,0))
	var mark := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(1.0,0.02,0.05); mark.mesh = bm; mark.position = Vector3(0.5,0.01,0); root.add_child(mark)
func _process(delta: float) -> bool:
	frame += 1
	if frame == 10:
		root.get_texture().get_image().save_png(OS.get_environment("TEMP") + "/shot_idle.png")
	if frame == 11:
		actor.walking = true
	if frame in [40, 47, 54]:
		root.get_texture().get_image().save_png(OS.get_environment("TEMP") + "/shot_walk_%d.png" % frame)
	if frame > 60: quit()
	return false
