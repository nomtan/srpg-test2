extends "res://tools/verify_character_phase1.gd"
## Render the actual palette/emblem shader and shared animations in Godot.
var shared_library: AnimationLibrary
var world: Node3D

func texture(path: String) -> ImageTexture:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(path)))

func emblem(variant: int) -> ImageTexture:
	var img := Image.create(128,128,false,Image.FORMAT_RGBA8)
	img.fill(Color(0.06,0.10,0.22,1) if variant == 1 else Color.TRANSPARENT)
	for y in range(128):
		for x in range(128):
			if absi(x-64)+absi(y-64)<42:
				img.set_pixel(x,y,Color(1,.85,.25,1) if variant==1 else Color(.2,1,.7,1))
	return ImageTexture.create_from_image(img)

func actor(key: String, variant: int, rear: bool) -> Node3D:
	var model := glb(SOURCES[key]+"body.glb")
	world.add_child(model)
	var skeleton := descendants(model,"Skeleton3D")[0] as Skeleton3D
	var attachment := model.find_child("HeadSocket",true,false) as Node3D
	var head := glb(SOURCES[key]+"head_default.glb")
	attachment.add_child(head)
	var body := model.find_child("Body",true,false) as MeshInstance3D
	var base := body.get_active_material(0) as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.shader=load("res://assets/characters/_shared/phase1_palette.gdshader")
	material.set_shader_parameter("base_color_texture",base.albedo_texture)
	material.set_shader_parameter("palette_mask",texture(SOURCES[key]+"palette_mask.png"))
	material.set_shader_parameter("palette_enabled",variant>0 and not rear)
	# A channel-specific zeroed mask demonstrates independence explicitly.
	if not rear and variant>0:
		var mask := Image.load_from_file(ProjectSettings.globalize_path(SOURCES[key]+"palette_mask.png"))
		for y in mask.get_height():
			for x in mask.get_width():
				var c:=mask.get_pixel(x,y)
				if variant==1: c.g=0
				else: c.r=0
				mask.set_pixel(x,y,c)
		material.set_shader_parameter("palette_mask",ImageTexture.create_from_image(mask))
	material.set_shader_parameter("primary_color",Color(.85,.1,.12))
	material.set_shader_parameter("secondary_color",Color(.1,.8,.9))
	if rear:
		material.set_shader_parameter("cape_mask",texture(SOURCES[key]+"cape_mask.png"))
		material.set_shader_parameter("emblem_texture",emblem(variant))
		material.set_shader_parameter("emblem_enabled",variant>0)
	body.material_override=material
	for node in descendants(head,"MeshInstance3D"):
		var mesh:=node as MeshInstance3D
		var mat: StandardMaterial3D=mesh.get_active_material(0).duplicate()
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override=mat
	var player:=AnimationPlayer.new()
	model.add_child(player)
	player.root_node=NodePath("..")
	player.add_animation_library("",shared_library)
	player.play("idle")
	player.seek(.25,true)
	player.advance(0)
	player.pause()
	if rear: model.rotation.y=PI
	return model

func run() -> void:
	root.size=Vector2i(1200,1050)
	var source:=glb("res://assets/characters/_shared/animations/common_combat.glb")
	root.add_child(source)
	shared_library=(descendants(source,"AnimationPlayer")[0] as AnimationPlayer).get_animation_library("")
	world=Node3D.new()
	root.add_child(world)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.6
	camera.position=Vector3(0,1.65,-6)
	camera.look_at(Vector3(0,1.65,0))
	camera.current=true
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.15,.16,.18)
	world.add_child(env)
	for rear in [false,true]:
		var actors: Array[Node3D]=[]
		var keys:= ["adventure","knight"] if rear else ["adventure","knight","black_mage"]
		for row in keys.size():
			for column in range(3):
				var model:=actor(keys[row],column,rear)
				model.position=Vector3((column-1)*1.1,2.3-row*1.1,0)
				actors.append(model)
		await process_frame
		await RenderingServer.frame_post_draw
		var output:="res://artifacts/character_phase1/godot_emblems.png" if rear else "res://artifacts/character_phase1/godot_palette.png"
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
		for model in actors: model.free()
	print("PHASE1_SHADER_CAPTURES_COMPLETE")
	quit()
