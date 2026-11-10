class_name SkillData
extends Resource

enum SkillType { ATTACK, HEAL, BUFF, DEBUFF, PASSIVE }
enum TargetType { ENEMY, ALLY, SELF, EMPTY_CELL }
enum RangeType { MELEE, RANGED, MAGIC }
enum ScalingType { PHYSICAL, MAGICAL, HEALING, FIXED, TERRAIN }

const PASSIVE_BUILD_STATS := ["attack_power", "magic_attack_power", "defense", "magic_defense", "speed",
	"move_range", "jump_height", "accuracy", "critical_rate", "evasion", "status_resistance"]
const DEFAULT_ICON := "res://assets/ui/skill_placeholder.svg"

static var _default_icon: Texture2D

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
var passive_effects: Array[Dictionary] = []
var passive_triggers: Array[Dictionary] = []
var icon_path := ""
var _icon: Texture2D

func get_icon() -> Texture2D:
	if _icon == null and not icon_path.is_empty():
		_icon = _read_icon(icon_path)
	if _icon:
		return _icon
	if _default_icon == null:
		_default_icon = _read_icon(DEFAULT_ICON)
	return _default_icon

static func _read_icon(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported: return imported
	if not FileAccess.file_exists(path): return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image and not image.is_empty() else null

static func create(id: String, display_name: String, type: SkillType, target: TargetType, range_kind: RangeType, affinity: BattleUnit.ElementType, cost: int, skill_power: int, accuracy: int, min_r: int, max_r: int, area: int = 0, los: bool = true) -> SkillData:
	var skill := SkillData.new()
	skill.skill_id = id; skill.skill_name = display_name; skill.skill_type = type; skill.target_type = target; skill.range_type = range_kind
	skill.element = affinity; skill.ap_cost = cost; skill.power = skill_power; skill.accuracy_modifier = accuracy
	skill.min_range = min_r; skill.max_range = max_r; skill.area_radius = area; skill.requires_line_of_sight = los
	return skill
