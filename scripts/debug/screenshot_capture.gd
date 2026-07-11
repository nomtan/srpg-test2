class_name ScreenshotCapture
extends Node

## Debug-only helper: press the configured key to save the current viewport
## framebuffer to user://screenshots/. Attach as a child of any scene that
## should be comparable across lighting/palette iterations (Phase16-Step4).

@export var capture_key: Key = KEY_F12

const SAVE_DIR := "user://screenshots/"


func _ready() -> void:
	# CLI-driven capture for scripted iteration (e.g. `--auto-capture`),
	# as an alternative to pressing capture_key interactively. Optional
	# `--auto-capture-delay=<seconds>` controls how long to wait before
	# capturing (useful for comparing shader animation at different TIME
	# values across two runs).
	if not (OS.is_debug_build() and "--auto-capture" in OS.get_cmdline_args()):
		return
	var delay := 0.5
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--auto-capture-delay="):
			delay = arg.get_slice("=", 1).to_float()
	await get_tree().create_timer(delay).timeout
	_capture()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey and event.pressed and not event.is_echo()):
		return
	if event.keycode != capture_key:
		return
	_capture()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var image := get_viewport().get_texture().get_image()
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s%s.png" % [SAVE_DIR, timestamp]
	image.save_png(path)
	image.save_png(SAVE_DIR + "latest.png")
	print("[ScreenshotCapture] saved ", ProjectSettings.globalize_path(path))
