class_name InventoryRules
extends RefCounted
## Value-only projections shared by hover/placement previews and simulation.

static func adjacent(first: Dictionary, second: Dictionary) -> bool:
	return GridRules.adjacent(first, second)

static func action_result(items: Dictionary, uid: String) -> Dictionary:
	var plans := EffectApplier.plan(items, uid, "use")
	var sources: Array[String] = []
	var bonuses: Array[Dictionary] = []
	for plan in plans:
		for bonus: Dictionary in plan.bonuses:
			sources.append("%s +%d" % [bonus.name, bonus.amount])
			bonuses.append(bonus)
	# power is retained for single-effect rule tests; UI renders every effect in effects.
	return {"effects": plans, "power": plans[0].amount if not plans.is_empty() else 0, "sources": sources, "bonuses": bonuses}

static func totals(items: Dictionary, trigger: String, target := "player") -> Dictionary:
	var totals := {"damage": 0, "guard": 0, "heal": 0, "set_guard": 0}
	for uid: String in items:
		for plan in EffectApplier.plan(items, uid, trigger):
			if plan.target == target: totals[plan.kind] += int(plan.amount)
	return totals

static func passive_guard(items: Dictionary) -> int:
	return totals(items, "turn_end").guard
