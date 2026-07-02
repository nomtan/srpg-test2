class_name SkillData
extends Resource

enum SkillType { ATTACK, HEAL, BUFF, DEBUFF }
enum TargetType { ENEMY, ALLY, SELF, EMPTY_CELL }
enum RangeType { MELEE, RANGED, MAGIC }
enum ScalingType { PHYSICAL, MAGICAL, HEALING, FIXED, TERRAIN }

var skill_id: String
var skill_name: String
var description: String
var skill_type: SkillType
var target_type: TargetType
var range_type: RangeType
var element: BattleUnit.ElementType = BattleUnit.ElementType.NONE
var ap_cost := 0
var power := 0
var accuracy_modifier := 0
var min_range := 1
var max_range := 1
var area_radius := 0
var requires_line_of_sight := true
var scaling_type: ScalingType = ScalingType.PHYSICAL
var critical_modifier := 0

static func create(id: String, display_name: String, type: SkillType, target: TargetType, range_kind: RangeType, affinity: BattleUnit.ElementType, cost: int, skill_power: int, accuracy: int, min_r: int, max_r: int, area: int = 0, los: bool = true) -> SkillData:
	var skill := SkillData.new()
	skill.skill_id = id; skill.skill_name = display_name; skill.skill_type = type; skill.target_type = target; skill.range_type = range_kind
	skill.element = affinity; skill.ap_cost = cost; skill.power = skill_power; skill.accuracy_modifier = accuracy
	skill.min_range = min_r; skill.max_range = max_r; skill.area_radius = area; skill.requires_line_of_sight = los
	return skill
