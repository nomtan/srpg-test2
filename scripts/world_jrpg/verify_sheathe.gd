extends SceneTree
## Sheathing: the draw / sheathe buttons show for the sword and shield, dual daggers, greatsword and greataxe (not the staff);
## sheathed, the shield hangs on the back and the sword at the left hip, the daggers cross at the small of the back and the
## greatsword / greataxe hang across it; the explorer walks and sits bare-handed and cannot attack, guard or use the skill;
## drawing brings them back to hand.
## godot --headless --path . --script scripts/world_jrpg/verify_sheathe.gd
## Rendered views: tools/asset_gen/character_pipeline/capture_sheathed.gd.
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
	world._on_weapon_selected("staff")
	check(not actor.can_sheathe() and not world.sheathe_row.visible, "Staff has no draw / sheathe buttons")
	actor.set_sheathed(true)
	check(not actor.sheathed and actor.model.find_child("EquippedStaff", true, false) != null, "Staff ignores sheathing")
	# Daggers cross at the small of the back, the greatsword and greataxe hang across it.
	for spec: Array in [["dual_daggers", ["SheathedDaggerR", "SheathedDaggerL"], "EquippedDaggerR"],
			["greatsword", ["SheathedGreatsword"], "EquippedGreatsword"], ["greataxe", ["SheathedGreataxe"], "EquippedGreataxe"]]:
		world._on_weapon_selected(spec[0])
		check(actor.can_sheathe() and world.sheathe_row.visible and not actor.is_sheathed(), "%s shows the draw / sheathe buttons, drawn" % spec[0])
		world._on_sheathe_selected(true)
		check(actor.is_sheathed() and (spec[1] as Array).all(func(part: String) -> bool: return actor.model.find_child(part, true, false) != null)
			and actor.model.find_child(spec[2], true, false) == null, "%s sheathed, nothing in hand" % spec[0])
		check(actor.walk_clip == GaitCycle.WALK and actor.can_sit and not actor.attack(), "%s sheathed walks and sits bare-handed, no attack" % spec[0])
		world._on_sheathe_selected(false)
		check(not actor.is_sheathed() and actor.model.find_child(spec[2], true, false) != null and actor.attack(), "%s drawn back into hand and attacks" % spec[0])
		actor.cancel_attack()
	world._on_weapon_selected("greatsword")
	world._on_sheathe_selected(true)
	world._on_weapon_selected("staff")
	check(not actor.sheathed and not actor.is_sheathed(), "Switching to a weapon that cannot be sheathed draws")
	world._on_weapon_selected("sword_shield")
	check(actor.can_sheathe() and world.sheathe_row.visible, "Sword and shield shows the draw / sheathe buttons")
	check(world.sheathe_buttons[false].button_pressed and not world.sheathe_buttons[true].button_pressed, "Drawn by default")
	world._on_sheathe_selected(true)
	var model: Node3D = actor.model
	check(actor.is_sheathed() and world.sheathe_buttons[true].button_pressed, "Sheathe button sheathes")
	check(model.find_child("SheathedSword", true, false) != null and model.find_child("SheathedShield", true, false) != null, "Shield on the back, sword at the left hip")
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
