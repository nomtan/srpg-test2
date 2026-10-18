extends SceneTree
## Sword skill: only the sword-and-shield loadout gets it, it counts as an attack, its effects spawn with the clip,
## finish cleanly, and fade out when the cast is cut short.
## godot --headless --path . --script scripts/world_jrpg/verify_sword_skill.gd
## Rendered frames: drop --headless and append -- --capture (saved to artifacts/sword_skill/).
const SwordCombat = preload("res://scripts/world_jrpg/sword_combat.gd")
const SkillFx = preload("res://scripts/world_jrpg/sword_skill_fx.gd")
const CAPTURE_TIMES := [0.1, 0.2, 0.45, 0.66, 0.8, 1.1, 1.2, 1.42, 1.74, 1.84, 1.9, 2.05, 2.3, 2.7, 2.85, 3.0, 3.06, 3.15, 3.3, 3.55]
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	await _loadouts()
	await _cast(capture)
	await _interrupt()
	print("SWORD SKILL: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _character(id: String) -> Array:
	var character := (load("res://scenes/characters/tripo_roster/%s.tscn" % id) as PackedScene).instantiate() as Node3D
	root.add_child(character)
	var combat := SwordCombat.new()
	combat.install(character, character.animation_player)
	return [character, combat]

func _loadouts() -> void:
	var made := _character("charcter004")
	var combat = made[1]
	check(combat.skill_clip == SwordCombat.SKILL and combat.is_attack_clip(SwordCombat.SKILL), "Sword and shield has the skill, and it counts as an attack")
	check(made[0].find_child("SwordSkillFx", false, false) is SkillFx, "Sword and shield plays the skill effects")
	check(absf(combat.impact_time(SwordCombat.SKILL) - SwordCombat.SKILL_IMPACT) < 1e-4, "The crescent cut is the skill's impact")
	made[0].queue_free()
	var other := _character("charcter001")
	check(other[1].skill_clip.is_empty() and other[0].find_child("SwordSkillFx", false, false) == null, "Other loadouts have no skill")
	other[0].queue_free()
	await process_frame

func _cast(capture: bool) -> void:
	var stage := _stage() if capture else null
	var made := _character("charcter004")
	var character: Node3D = made[0]
	var player: AnimationPlayer = character.animation_player
	var fx: SkillFx = character.find_child("SwordSkillFx", false, false)
	if stage: character.rotation.y = PI / 2
	# The first playback of a generated clip stalls a frame while it is set up.
	player.play(SwordCombat.SKILL, 0)
	await process_frame
	player.play("idle", 0)
	await process_frame
	player.play(SwordCombat.SKILL, 0)
	var most := 0
	var seen := {}
	var shots := CAPTURE_TIMES.duplicate()
	var length := player.get_animation(SwordCombat.SKILL).length
	var elapsed := 0.0
	while elapsed < length + 1.5:
		await process_frame
		elapsed += get_root().get_process_delta_time()
		most = maxi(most, fx._pieces.size())
		for piece in fx._pieces: seen[piece.material.get_shader_parameter("mode")] = true
		if capture and not shots.is_empty() and player.current_animation == SwordCombat.SKILL and player.current_animation_position >= shots[0]:
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/sword_skill"))
			image.save_png("res://artifacts/sword_skill/skill_%04d.png" % roundi(shots[0] * 1000))
			shots.pop_front()
	check(seen.size() == 12, "Every kind of piece appears during the cast (%d of 12)" % seen.size())
	check(most > 40, "The finisher fills the scene (%d pieces at once)" % most)
	check(fx._pieces.is_empty() and fx.get_child_count() == 0, "Every piece is gone after the cast")
	character.queue_free()
	if stage: stage.queue_free()
	await process_frame

func _interrupt() -> void:
	var made := _character("charcter004")
	var character: Node3D = made[0]
	var player: AnimationPlayer = character.animation_player
	var fx: SkillFx = character.find_child("SwordSkillFx", false, false)
	player.play(SwordCombat.SKILL, 0)
	var elapsed := 0.0
	while player.current_animation_position < 1.0 and elapsed < 3.0:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	check(not fx._pieces.is_empty(), "Pieces are live mid-cast")
	player.play("idle", 0.1)
	elapsed = 0.0
	while elapsed < 0.4:
		await process_frame
		elapsed += get_root().get_process_delta_time()
	check(fx._pieces.is_empty() and fx._events.is_empty(), "A cut-short cast fades its pieces and drops the rest")
	character.queue_free()
	await process_frame

## A dark floor, light and a three-quarter camera like the reference clip.
func _stage() -> Node3D:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.45, 0.62, 0.85)
	environment.environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	stage.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.13, 0.14, 0.18)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(-1.0, 2.8, 7.0), Vector3(0.6, 0.8, 0), Vector3.UP)
	camera.current = true
	return stage
