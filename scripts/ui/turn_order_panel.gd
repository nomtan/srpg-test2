class_name TurnOrderPanel
extends PanelContainer

@onready var current_actor_label: Label = $VBox/CurrentActorLabel
@onready var upcoming_list: Label = $VBox/UpcomingList

func update_order(current_actor: BattleUnit, order: Array[BattleUnit]) -> void:
	current_actor_label.text = "Current: %s" % (current_actor.unit_name if current_actor else "---")
	var lines: Array[String] = ["Next:"]
	for index in order.size():
		var unit := order[index]
		lines.append("%d. %s  CT:%d  SPD:%d" % [index + 1, unit.unit_name, unit.ct, unit.build_stats.speed if unit.build_stats else unit.agility])
	upcoming_list.text = "\n".join(lines)
