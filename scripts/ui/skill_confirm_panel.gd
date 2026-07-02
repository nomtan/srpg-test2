class_name SkillConfirmPanel
extends PanelContainer

signal confirmed
signal cancelled
@onready var label: Label = $VBox/Preview

func _ready() -> void:
	$VBox/Buttons/Confirm.pressed.connect(func() -> void: confirmed.emit())
	$VBox/Buttons/Cancel.pressed.connect(func() -> void: cancelled.emit())

func open(user: BattleUnit, skill: SkillData, target_pos: Vector2i, preview: Dictionary) -> void:
	var names: Array[String] = []
	for target: BattleUnit in preview.targets: names.append(target.unit_name)
	var weapon_line := "\nWeapon: %s" % preview.weapon_name if not str(preview.get("weapon_name", "")).is_empty() else ""
	var critical_line := "\nCritical: %d%%" % int(preview.get("critical_rate", 0)) if int(preview.get("critical_rate", 0)) > 0 else ""
	label.text = "Skill: %s%s\nUser: %s\nTarget: %s\nAP Cost: %d\n%s: %d\nHit Rate: %s%s\nArea: %d\nTargets: %s" % [skill.skill_name, weapon_line, user.unit_name, str(target_pos), skill.ap_cost, "Heal" if preview.is_heal else "Damage", preview.value, "Always" if preview.is_heal else "%d%%" % preview.hit_rate, critical_line, skill.area_radius, ", ".join(names)]
	visible = true
	$VBox/Buttons/Confirm.grab_focus()

func close() -> void: visible = false
