class_name BattleLog
extends PanelContainer

@onready var label: Label = $BattleLogLabel
var lines: Array[String] = []


func add_message(message: String) -> void:
	for line in message.split("\n"):
		lines.append(line)
	while lines.size() > 3: lines.pop_front()
	label.text = "\n".join(lines)


func show_attack_result(attacker: BattleUnit, target: BattleUnit, result: Dictionary) -> void:
	var message := "%s attacks %s\n" % [attacker.unit_name, target.unit_name]
	message += (("Critical! %d damage" if bool(result.get("critical", false)) else "Hit! %d damage") % result.damage) if result.hit else "Miss!"
	if result.defeated: message += "\n%s defeated" % target.unit_name
	add_message(message)
