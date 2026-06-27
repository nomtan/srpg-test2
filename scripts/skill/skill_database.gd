class_name SkillDatabase
extends Node

var skills: Dictionary = {}

func _ready() -> void:
	_register(SkillData.create("power_slash", "強斬り", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.MELEE, BattleUnit.ElementType.NONE, 5, 12, -5, 1, 1, 0, false))
	_register(SkillData.create("earth_break", "アースブレイク", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.MAGIC, BattleUnit.ElementType.EARTH, 10, 18, -10, 1, 2, 1, false))
	_register(SkillData.create("aqua_edge", "アクアエッジ", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.MAGIC, BattleUnit.ElementType.WATER, 8, 14, 0, 1, 2, 0, false))
	_register(SkillData.create("healing_water", "癒しの水", SkillData.SkillType.HEAL, SkillData.TargetType.ALLY, SkillData.RangeType.MAGIC, BattleUnit.ElementType.WATER, 8, 25, 0, 1, 3, 0, false))
	_register(SkillData.create("aimed_shot", "狙い撃ち", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.RANGED, BattleUnit.ElementType.NONE, 5, 8, 15, 2, 4))
	_register(SkillData.create("piercing_arrow", "貫通矢", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.RANGED, BattleUnit.ElementType.WIND, 9, 10, -5, 2, 4))
	_register(SkillData.create("heavy_attack", "強打", SkillData.SkillType.ATTACK, SkillData.TargetType.ENEMY, SkillData.RangeType.MELEE, BattleUnit.ElementType.NONE, 4, 10, -5, 1, 1, 0, false))
	_register(SkillData.create("guard_stance", "ガードスタンス", SkillData.SkillType.BUFF, SkillData.TargetType.SELF, SkillData.RangeType.MAGIC, BattleUnit.ElementType.NONE, 6, 0, 0, 0, 0, 0, false))

func _register(skill: SkillData) -> void: skills[skill.skill_id] = skill
func get_skill(id: String) -> SkillData: return skills.get(id)
func get_skills_for_unit(unit: BattleUnit) -> Array[SkillData]:
	var result: Array[SkillData] = []
	for id in unit.equipped_skill_ids:
		var skill := get_skill(id)
		if skill: result.append(skill)
	return result
