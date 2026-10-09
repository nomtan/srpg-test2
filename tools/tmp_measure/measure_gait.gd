extends SceneTree
const Explorer = preload("res://scripts/world_jrpg/explorer_actor.gd")
func _initialize() -> void:
	call_deferred("run")
func measure(actor, clip: String) -> void:
	var player: AnimationPlayer = actor.animation_player
	var sk := actor.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var feet := []
	for n in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
		feet.append(sk.find_bone(n))
	player.play(clip, 0.0)
	player.speed_scale = 1.0
	var length := player.get_animation(clip).length
	var steps := 120
	var dt := length / steps
	var prev := {}
	var samples := []
	for i in steps + 1:
		player.seek(i * dt, true)
		var lf: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(feet[2]).origin))
		var rf: Vector3 = actor.to_local(sk.to_global(sk.get_bone_global_pose(feet[3]).origin))
		samples.append([lf, rf])
	var miny := 1e9
	for s in samples: miny = minf(miny, minf(s[0].y, s[1].y))
	var maxy := -1e9
	for s in samples: maxy = maxf(maxy, maxf(s[0].y, s[1].y))
	var vs := []
	for i in steps:
		for f in 2:
			var a: Vector3 = samples[i][f]; var b: Vector3 = samples[i+1][f]
			if a.y < miny + 0.15 * (maxy - miny):
				vs.append((b - a) / dt)
	var avg := Vector3.ZERO
	for v in vs: avg += v
	avg /= max(vs.size(), 1)
	var xs := []
	for s in samples: xs.append(s[0].x)
	print(clip, " len=", length, " foot y range=", miny, "..", maxy, " stance samples=", vs.size(), " avg stance vel=", avg, " lf x range=", xs.min(), "..", xs.max())
	var lz := []
	for s in samples: lz.append(s[0].z)
	print("  lf z range=", lz.min(), "..", lz.max())
func run() -> void:
	var actor = Explorer.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.world_facing = Vector3(1,0,0)
	actor._update_model()
	print("model rot y ", actor.model.rotation.y, " scale ", actor.model.scale, " global scale ", actor.model.global_transform.basis.get_scale())
	measure(actor, "walk")
	measure(actor, actor.run_clip)
	quit()
