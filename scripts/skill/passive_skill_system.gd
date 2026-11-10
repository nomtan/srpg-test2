class_name PassiveSkillSystem
extends RefCounted

var _skills: SkillDatabase
var _attacks: AttackSystem
var _units: UnitManager

func _init(skills: SkillDatabase, attacks: AttackSystem, units: UnitManager) -> void:
	_skills = skills
	_attacks = attacks
	_units = units

func on_attacked(context: AttackContext) -> void:
	var defender := context.target
	if not _is_present(defender):
		return
	var origin := "active" if context.origin == AttackContext.Origin.ACTIVE else "reaction"
	var result := "hit" if context.hit else "evade"
	for skill: SkillData in _skills.get_passives_for_unit(defender):
		if context.processed_skill_ids.has(skill.skill_id): continue
		for trigger: Dictionary in skill.passive_triggers:
			if origin not in trigger.attackOrigins or result not in trigger.hitResults: continue
			var effects := _eligible_effects(trigger.effects, context.origin)
			if effects.is_empty(): continue
			context.processed_skill_ids[skill.skill_id] = true
			if float(trigger.chance) >= 1.0 or (float(trigger.chance) > 0.0 and randf() < float(trigger.chance)):
				for effect: Dictionary in effects:
					_apply_effect(skill, effect, context)
			else:
				context.reaction_messages.append("%s: %s did not trigger" % [defender.unit_name, skill.skill_name])
			# A passive gets one roll per attack, using its first eligible trigger.
			break

func _eligible_effects(entries: Array, origin: AttackContext.Origin) -> Array[Dictionary]:
	var effects: Array[Dictionary] = []
	for effect: Dictionary in entries:
		if effect.type == "heal" or (effect.type == "counter_attack" and origin == AttackContext.Origin.ACTIVE):
			effects.append(effect)
	return effects

func _apply_effect(skill: SkillData, effect: Dictionary, context: AttackContext) -> void:
	var defender := context.target
	if not _is_present(defender): return
	var label := "%s: %s" % [defender.unit_name, skill.skill_name]
	var multiplier := float(effect.get("powerMultiplier", 1.0))
	if effect.type == "heal":
		var missing_hp := defender.max_hp - defender.hp
		var power := float(effect.get("power", 0)) + floorf(defender.mind * 1.5)
		var healed := roundi(clampf(power * multiplier, 0.0, missing_hp))
		defender.hp += healed
		defender.refresh_status_bars()
		context.reaction_messages.append("%s recovers %d HP" % [label, healed])
		return
	if not _is_present(context.attacker):
		context.reaction_messages.append(label + " could not counter (attacker unavailable)")
		return
	var result := _attacks.execute_reaction_attack(defender, context.attacker, multiplier)
	if not result.success:
		context.reaction_messages.append(label + " could not counter (out of range or blocked)")
		return
	var outcome := "%d damage" % result.damage if result.hit else "miss"
	context.reaction_messages.append("%s counters %s (%s)" % [label, context.attacker.unit_name, outcome])
	context.reaction_messages.append_array(result.reaction_messages)
	if result.defeated:
		_units.remove_unit(context.attacker)

func _is_present(unit: BattleUnit) -> bool:
	return is_instance_valid(unit) and unit.is_alive() and _units.unit_at(Vector2i(unit.grid_x, unit.grid_z)) == unit
