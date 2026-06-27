class_name GrowthResultPanel
extends PanelContainer

@onready var label: Label = $VBox/Results

func show_results(units: Array[BattleUnit]) -> void:
	var lines: Array[String] = ["Stage Clear", ""]
	for unit in units:
		lines.append("%s  Lv %d  EXP %d/%d" % [unit.unit_name, unit.level, unit.exp, unit.exp_to_next_level])
		lines.append("Main Job: %s Lv %d  JobEXP %d/%d" % [unit.main_job_name, unit.get_job_level_for(unit.main_job_id), unit.get_job_exp_for(unit.main_job_id), unit.job_exp_to_next_level])
		lines.append("Sub Job: %s Lv %d (No JobEXP gained)" % [unit.sub_job_name, unit.get_job_level_for(unit.sub_job_id)])
		lines.append("Equipped: %s" % ", ".join(unit.equipped_skill_ids))
		lines.append("")
	label.text = "\n".join(lines)
	visible = true
