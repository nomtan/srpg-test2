class_name ExperienceSystem
extends Node

var jobs: JobDatabase
var growth_events: Array[Dictionary] = []
func setup(job_database: JobDatabase) -> void: jobs = job_database
func calculate_action_exp(actor: BattleUnit, target: BattleUnit, valid: bool) -> int:
	if not valid: return 0
	return maxi(1, 10 + (5 if target.level > actor.level else (-5 if target.level < actor.level else 0)))
func grant_exp(actor: BattleUnit, amount: int) -> Dictionary:
	var level_ups := actor.add_exp(amount, jobs.get_growth(actor.job_id))
	var result := {"unit": actor, "amount": amount, "level_ups": level_ups}
	growth_events.append(result)
	return result
