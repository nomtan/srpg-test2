extends SceneTree
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
func _initialize() -> void:
	call_deferred("run")
func dump(actor, clip):
	var player: AnimationPlayer = actor.animation_player
	var sk := actor.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var l := sk.find_bone("mixamorig_LeftFoot"); var r := sk.find_bone("mixamorig_RightFoot")
	var lt := sk.find_bone("mixamorig_LeftToeBase")
	player.play(clip, 0.0); player.speed_scale = 1.0
	var length := player.get_animation(clip).length
	print("== ", clip, " ", length)
	for i in 21:
		player.seek(i * length / 20.0, true)
		var a: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(l).origin))
		var b: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(r).origin))
		var c: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(lt).origin))
		var h: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin))
		print("%.2f  L z=%.3f y=%.3f  toe z=%.3f y=%.3f | R z=%.3f y=%.3f | hips y=%.3f" % [i/20.0, a.z, a.y, c.z, c.y, b.z, b.y, h.y])
func run() -> void:
	var actor = Explorer.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.world_facing = Vector3(1,0,0)
	actor._update_model()
	dump(actor, "walk")
	dump(actor, actor.run_clip)
	quit()
