extends SceneTree
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var actor = Explorer.new()
	root.add_child(actor)
	var sk := actor.model.find_child("Skeleton3D", true, false) as Skeleton3D
	for n in ["head", "mixamorig_Hips", "mixamorig_LeftFoot", "mixamorig_LeftToeBase"]:
		var i := sk.find_bone(n)
		if i >= 0: print(n, " ", actor.to_local(sk.to_global(sk.get_bone_global_rest(i).origin)))
	var p: Node = sk
	while p != actor:
		if p is Node3D: print(p.name, " ", p.transform)
		p = p.get_parent()
	var anim: Animation = actor.animation_player.get_animation("walk")
	for t in anim.get_track_count():
		print(anim.track_get_path(t), " ", anim.track_get_type(t), " keys=", anim.track_get_key_count(t))
	quit()
