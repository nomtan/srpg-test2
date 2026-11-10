class_name AttackContext
extends RefCounted

enum Origin { ACTIVE, REACTION }

var origin: Origin
var attacker: BattleUnit
var target: BattleUnit
var hit: bool
var damage: int
var processed_skill_ids := {}
var reaction_messages: Array[String] = []

func _init(source: BattleUnit, defender: BattleUnit, did_hit: bool, amount: int, attack_origin: Origin) -> void:
	attacker = source
	target = defender
	hit = did_hit
	damage = amount
	origin = attack_origin
