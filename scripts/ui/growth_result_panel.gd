class_name GrowthResultPanel
extends PanelContainer

@onready var label: Label = $VBox/Results

func show_results(units: Array[BattleUnit]) -> void:
	var lines: Array[String] = ["Stage Clear", ""]
	for unit in units:
		lines.append("%s  Lv %d  EXP %d/%d" % [unit.unit_name, unit.level, unit.exp, unit.exp_to_next_level])
		lines.append("%s Lv %d  JobEXP %d/%d" % [unit.job_name, unit.job_level, unit.job_exp, unit.job_exp_to_next_level])
		lines.append("Skills: %s" % ", ".join(unit.skill_ids))
		lines.append("")
	label.text = "\n".join(lines)
	visible = true
