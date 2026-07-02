class_name SkillMenu
extends PanelContainer

signal skill_selected(skill: SkillData)
signal cancelled
@onready var list: VBoxContainer = $VBox/SkillList
@onready var description: Label = $VBox/Description

func _ready() -> void: $VBox/CancelButton.pressed.connect(func() -> void: cancelled.emit())

func open(unit: BattleUnit, skills: Array[SkillData]) -> void:
	for child in list.get_children(): child.queue_free()
	var first: Button = null
	for skill in skills:
		var button := Button.new()
		button.text = "%s  AP %d" % [skill.skill_name, skill.ap_cost]
		button.disabled = unit.ap < skill.ap_cost
		button.pressed.connect(func() -> void: skill_selected.emit(skill))
		button.mouse_entered.connect(func() -> void: description.text = "%s\n射程 %d-%d / 範囲 %d / AP %d" % [skill.skill_name, skill.min_range, skill.max_range, skill.area_radius, skill.ap_cost])
		list.add_child(button)
		if not first and not button.disabled: first = button
	visible = true
	if first: first.grab_focus()

func close() -> void: visible = false
