extends SceneTree
## Sheathing: the draw / sheathe buttons show only for the sword and shield; sheathed, both hang on the back,
## the explorer walks and sits bare-handed and cannot attack, guard or use the skill; drawing brings them back to hand.
## godot --headless --path . --script scripts/world_jrpg/verify_sheathe.gd
## Rendered views of the back: tools/asset_gen/character_pipeline/capture_sheathed.gd.
const SAMPLE = preload("res://samples/JRPGWorldSample.tscn")
const GaitCycle = preload("res://scripts/world_jrpg/gait_cycle.gd")
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
	var world = SAMPLE.instantiate()
	root.add_child(world)
	world.set_process(false)
	world.player.set_process(false)
	var actor = world.player
	world._on_weapon_selected("greatsword")
	check(not actor.can_sheathe() and not world.sheathe_row.visible, "Greatsword has no draw / sheathe buttons")
	actor.set_sheathed(true)
	check(not actor.sheathed and actor.model.find_child("EquippedGreatsword", true, false) != null, "Greatsword ignores sheathing")
	world._on_weapon_selected("sword_shield")
	check(actor.can_sheathe() and world.sheathe_row.visible, "Sword and shield shows the draw / sheathe buttons")
	check(world.sheathe_buttons[false].button_pressed and not world.sheathe_buttons[true].button_pressed, "Drawn by default")
	world._on_sheathe_selected(true)
	var model: Node3D = actor.model
	check(actor.is_sheathed() and world.sheathe_buttons[true].button_pressed, "Sheathe button sheathes")
	check(model.find_child("SheathedSword", true, false) != null and model.find_child("SheathedShield", true, false) != null, "Sword and shield on the back")
	check(model.find_child("EquippedSword", true, false) == null and model.find_child("EquippedShield", true, false) == null, "Nothing in hand")
	check(actor.current_weapon() == "sword_shield", "Still equipped with the sword and shield")
	check(actor.walk_clip == GaitCycle.WALK and actor.can_sit, "Walks and sits as bare-handed")
	actor.set_guard(true)
	check(not actor.attack() and not actor.skill() and not actor.guarding, "No attack, skill or guard while sheathed")
	check(actor.toggle_sit(), "Can sit while sheathed")
	actor.stand_now()
	world._on_weapon_selected("sword_shield")
	check(actor.is_sheathed(), "Re-selecting the same weapon keeps it sheathed")
	world._on_sheathe_selected(false)
	check(not actor.is_sheathed() and actor.model.find_child("EquippedSword", true, false) != null and actor.model.find_child("EquippedShield", true, false) != null, "Draw button puts them back in hand")
	check(actor.attack(), "Drawn sword attacks")
	print("SHEATHE: ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
