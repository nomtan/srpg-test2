extends SceneTree
## Captures the guardian in JRPGWorldSample2: the whole screen with the guardian panel, then frames of the
## summon (ink forming from the tail up, strokes swirling in) and of the return (erased from the head down,
## strokes scattering), from the game camera pulled in close.
## Needs a renderer (not --headless): godot --path . --script res://tools/asset_gen/character_pipeline/capture_guardian.gd -- [out_dir] [guardian_id]
## Images: <out_dir>/ui.png, summon_<ms>.png, attack.png, dismiss_<ms>.png (default artifacts/guardian).

const SAMPLE := "res://samples/JRPGWorldSample2.tscn"
const SUMMON_FRAMES := [0.12, 0.3, 0.5, 0.7, 0.95, 1.6]
const DISMISS_FRAMES := [0.12, 0.3, 0.5, 0.7]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "res://artifacts/guardian"
	var guardian_id: String = args[1] if args.size() > 1 else "shadow1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var world = (load(SAMPLE) as PackedScene).instantiate()
	root.add_child(world)
	await create_timer(4.0).timeout
	world._on_guardian_chosen(guardian_id)
	await _shot(out_dir + "/ui.png")
	# The help panel covers the upper screen; effect frames are taken without the HUD.
	world.hud.visible = false
	world.field_weather.controls.visible = false
	world.distance = 17.0
	world.pitch = 0.38
	world._focus_player()
	world._update_camera()
	world._on_guardian_selected(true)
	var start := Time.get_ticks_msec()
	for t: float in SUMMON_FRAMES:
		await _until(start, t)
		await _shot(out_dir + "/summon_%04d.png" % int(t * 1000))
	world.guardian.act("attack")
	await create_timer(0.45).timeout
	await _shot(out_dir + "/attack.png")
	await create_timer(1.0).timeout
	world._on_guardian_selected(false)
	start = Time.get_ticks_msec()
	for t: float in DISMISS_FRAMES:
		await _until(start, t)
		await _shot(out_dir + "/dismiss_%04d.png" % int(t * 1000))
	quit(0)


func _until(start: int, seconds: float) -> void:
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("CAPTURE ", path)
