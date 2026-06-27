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
	label.text = "Skill: %s\nUser: %s\nTarget: %s\nAP Cost: %d\n%s: %d\nHit Rate: %s\nArea: %d\nTargets: %s" % [skill.skill_name, user.unit_name, str(target_pos), skill.ap_cost, "Heal" if preview.is_heal else "Damage", preview.value, "Always" if preview.is_heal else "%d%%" % preview.hit_rate, skill.area_radius, ", ".join(names)]
	visible = true
	$VBox/Buttons/Confirm.grab_focus()

func close() -> void: visible = false
