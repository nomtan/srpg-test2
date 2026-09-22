extends SceneTree
## Isolated asset verification fixture, not a Phase 2 runtime builder.
const PATHS := {
	"adventure":"res://assets/characters/tripo_adventure/prepared/phase1_5/",
	"knight":"res://assets/characters/tripo_knight2/prepared/phase1_5/",
	"black_mage":"res://assets/characters/tripo_black_mage/prepared/phase1_5/"
}
const OUT := "res://artifacts/character_phase1_5/"
var world: Node3D
var camera: Camera3D
var failed := false
var results := {}
var screenshots := true
var references := {}

func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failed=true

func glb(path: String) -> Node3D:
	var doc:=GLTFDocument.new()
	var state:=GLTFState.new()
	var error:=doc.append_from_file(ProjectSettings.globalize_path(path),state)
	check(error==OK,"load "+path)
	return doc.generate_scene(state) as Node3D

func descendants(node: Node,type: String) -> Array[Node]:
	var found: Array[Node]=[]
	if node.is_class(type): found.append(node)
	for child in node.get_children(): found.append_array(descendants(child,type))
	return found

func texture(path: String) -> ImageTexture:
	var image:=Image.load_from_file(ProjectSettings.globalize_path(path))
	check(not image.is_empty(),"texture "+path)
	return ImageTexture.create_from_image(image)

func crest(variant: int) -> ImageTexture:
	var image:=Image.create(128,128,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(128):
		for x in range(128):
			var shape: bool = absi(x-64)+absi(y-64)<36 if variant==1 else ((x-64)*(x-64)+(y-64)*(y-64)<30*30 and (x-64)*(x-64)+(y-64)*(y-64)>20*20)
			if shape: image.set_pixel(x,y,Color(1.0,.8,.2) if variant==1 else Color(.1,1.0,.65))
	return ImageTexture.create_from_image(image)

func neutral_materials(node: Node) -> void:
	for obj in descendants(node,"MeshInstance3D"):
		var mesh:=obj as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			var material:=mesh.get_active_material(index).duplicate() as StandardMaterial3D
			material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.set_surface_override_material(index,material)

func actor(key: String,head_key: String="") -> Dictionary:
	if head_key.is_empty(): head_key=key
	var model:=glb(PATHS[key]+"body.glb")
	world.add_child(model)
	var skeletons:=descendants(model,"Skeleton3D")
	check(skeletons.size()==1,key+" one skeleton")
	var skeleton:=skeletons[0] as Skeleton3D
	var head:=glb(PATHS[head_key]+"head_default.glb")
	check(descendants(head,"Skeleton3D").is_empty(),head_key+" rigid head")
	var socket:=model.find_child("HeadSocket",true,false) as Node3D
	socket.add_child(head)
	neutral_materials(head)
	var body:=model.find_child("Body",true,false) as MeshInstance3D
	var base:=body.get_active_material(0) as StandardMaterial3D
	var material:=ShaderMaterial.new()
	material.shader=load("res://tools/character_phase1_5_palette.gdshader")
	material.set_shader_parameter("base_color_texture",base.albedo_texture)
	material.set_shader_parameter("palette_mask",texture(PATHS[key]+"palette_mask.png"))
	if key=="knight": material.set_shader_parameter("cape_mask",texture(PATHS[key]+"cape_mask.png"))
	body.material_override=material
	var animated:=glb(PATHS[key]+"animations/common_combat.glb")
	var source_player:=descendants(animated,"AnimationPlayer")[0] as AnimationPlayer
	var library:=source_player.get_animation_library("")
	for clip: StringName in library.get_animation_list():
		var animation:=library.get_animation(clip)
		for track in animation.get_track_count():
			check(animation.track_get_type(track)==Animation.TYPE_ROTATION_3D,key+" rotation-only "+str(clip)+"/"+str(track))
			var old:=animation.track_get_path(track)
			animation.track_set_path(track,NodePath(str(model.get_path_to(skeleton))+":"+str(old.get_subname(0))))
		if clip in ["idle","walk"]: animation.loop_mode=Animation.LOOP_LINEAR
	var player:=AnimationPlayer.new()
	model.add_child(player)
	player.root_node=NodePath("..")
	player.add_animation_library("",library)
	animated.free()
	return {"model":model,"skeleton":skeleton,"player":player,"material":material,"head":head}

func pose(item: Dictionary,clip: String,fraction: float) -> void:
	var player: AnimationPlayer=item.player
	player.play(clip)
	player.seek(player.current_animation_length*fraction,true)
	player.advance(0)
	player.pause()
	(item.skeleton as Skeleton3D).force_update_all_bone_transforms()
	await process_frame
	await process_frame

func capture(name: String) -> void:
	if not screenshots: return
	# Allow uniform and visibility changes through both scene and render updates.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(OUT+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"capture "+name)

func _initialize() -> void:
	screenshots=not "--verify-only" in OS.get_cmdline_user_args()
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(600,680)
	world=Node3D.new()
	root.add_child(world)
	camera=Camera3D.new()
	world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.23
	camera.position=Vector3(0,.54,-3)
	camera.look_at(Vector3(0,.54,0))
	camera.current=true
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.15,.16,.18)
	world.add_child(env)
	for key: String in PATHS:
		var item:=actor(key)
		var skeleton: Skeleton3D=item.skeleton
		var hierarchy:={}
		for index in skeleton.get_bone_count():
			var name:=skeleton.get_bone_name(index)
			var parent:=skeleton.get_bone_parent(index)
			hierarchy[name]=str(skeleton.get_bone_name(parent)) if parent>=0 else ""
		if references.is_empty(): references=hierarchy
		else: check(hierarchy==references,key+" semantic hierarchy matches")
		var clips:={}
		for clip in ["idle","walk","attack_melee","cast_magic","hit"]:
			await pose(item,clip,0.0)
			var initial: Array[Transform3D]=[]
			for index in skeleton.get_bone_count(): initial.append(skeleton.get_bone_global_pose(index))
			await pose(item,clip,.25 if clip in ["idle","walk"] else .5)
			var moved:=0
			for index in skeleton.get_bone_count():
				if not initial[index].is_equal_approx(skeleton.get_bone_global_pose(index)): moved+=1
			check(moved>0,key+" moves "+clip)
			check(skeleton.get_bone_pose_position(skeleton.find_bone("Root")).length()<1e-6,key+" no root translation "+clip)
			clips[clip]={"moving_bones":moved}
			await capture(key+"_"+clip)
			for label: String in {"HeadSocket":"Head","WeaponSocket_R":"Hand_R","WeaponSocket_L":"Hand_L","BackSocket":"Chest"}:
				var bone: String={"HeadSocket":"Head","WeaponSocket_R":"Hand_R","WeaponSocket_L":"Hand_L","BackSocket":"Chest"}[label]
				var socket:=item.model.find_child(label,true,false) as Node3D
				var expected:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(bone))
				check(socket.global_transform.is_equal_approx(expected),key+" "+clip+" "+label+" follows "+bone)
		await pose(item,"idle",0.0)
		item.head.visible=false
		await capture(key+"_body_only")
		item.head.visible=true
		for variant in range(4):
			item.material.set_shader_parameter("change_primary",variant in [1,3])
			item.material.set_shader_parameter("change_secondary",variant in [2,3])
			await capture(key+"_palette_"+str(variant))
		item.material.set_shader_parameter("change_primary",false)
		item.material.set_shader_parameter("change_secondary",false)
		item.model.rotation.y=PI
		await capture(key+"_back")
		if key=="knight":
			for variant in range(3):
				item.material.set_shader_parameter("emblem_enabled",variant>0)
				item.material.set_shader_parameter("emblem_texture",crest(variant))
				await capture(key+"_emblem_"+str(variant))
		results[key]={"hierarchy":hierarchy,"clips":clips,"sockets_checked":20}
		item.model.free()
	for body: String in PATHS:
		for head: String in PATHS:
			if body==head: continue
			var item:=actor(body,head)
			await pose(item,"idle",.25)
			await capture(body+"_with_"+head)
			item.model.free()
	var file:=FileAccess.open(OUT+"godot_validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":not failed,"characters":results,"rendered":screenshots},"  "))
	print("PHASE1_5_GODOT_COMPLETE ",not failed)
	quit(1 if failed else 0)
