class_name InventoryRules
extends RefCounted
## Value-only projections shared by hover/placement previews and simulation.

static func adjacent(first: Dictionary, second: Dictionary) -> bool:
	return GridRules.adjacent(first, second)

static func action_result(items: Dictionary, uid: String) -> Dictionary:
	var plans := EffectApplier.plan(items, uid, "use")
	var sources: Array[String] = []
	var bonuses: Array[Dictionary] = []
	var error := ""
	for plan in plans:
		if not plan.error.is_empty(): error = plan.error
		for bonus: Dictionary in plan.bonuses:
			sources.append("%s +%d" % [bonus.name, bonus.amount])
			bonuses.append(bonus)
		for multiplier: Dictionary in plan.multipliers:
			sources.append("%s ×%d" % [multiplier.name, multiplier.factor])
	if not error.is_empty():
		sources.clear()
		bonuses.clear()
	# power is retained for single-effect rule tests; UI renders every effect in effects.
	return {"effects": plans, "power": plans[0].amount if not plans.is_empty() else 0, "sources": sources, "bonuses": bonuses, "error": error}

static func totals(items: Dictionary, trigger: String, target := "player") -> Dictionary:
	var totals := {"damage": 0, "guard": 0, "heal": 0, "set_guard": 0, "error": ""}
	for uid: String in items:
		for plan in EffectApplier.plan(items, uid, trigger):
			if plan.target != target: continue
			if not plan.error.is_empty() or totals[plan.kind] > EffectApplier.MAX_EXACT - int(plan.amount):
				totals.error = plan.error if not plan.error.is_empty() else EffectApplier.POWER_ERROR
				return totals
			totals[plan.kind] += int(plan.amount)
	return totals

static func passive_guard(items: Dictionary) -> int:
	return totals(items, "turn_end").guard

static func synergy_links(items: Dictionary, focus: String) -> Dictionary:
	# Only actual resolved plans supply links; never reimplement range/group rules here.
	if not items.has(focus): return {"links": [], "error": ""}
	if not EffectApplier.within_budget(items): return {"links": [], "error": "효과 계획의 처리 한도를 초과했습니다."}
	var links: Array[Dictionary] = []
	var ids: Array = items.keys()
	ids.sort()
	for uid: String in ids:
		for trigger in ["use", "turn_end", "damage_taken"]:
			for plan: Dictionary in EffectApplier.plan(items, uid, trigger):
				if not plan.error.is_empty():
					return {"links": [], "error": plan.error}
				for match_uid: String in plan.matches:
					_add_link(links, focus, match_uid, uid, "condition", plan.kind, trigger, 0, int(plan.max_matches), str(plan.effect_id), str(plan.match_range))
				for bonus: Dictionary in plan.bonuses:
					_add_link(links, focus, str(bonus.source), uid, "add", plan.kind, trigger, int(bonus.amount), 0, str(bonus.effect_id), str(bonus.range))
					for match_uid: String in bonus.matches:
						_add_link(links, focus, match_uid, str(bonus.source), "condition", plan.kind, trigger, 0, int(bonus.max_matches), str(bonus.effect_id), str(bonus.match_range))
				for multiplier: Dictionary in plan.multipliers:
					_add_link(links, focus, str(multiplier.source), uid, "multiply", plan.kind, trigger, int(multiplier.factor), 0, str(multiplier.effect_id), str(multiplier.range))
	return {"links": links, "error": ""}

static func _add_link(links: Array[Dictionary], focus: String, source: String, target: String, kind: String, operation: String, trigger: String, amount: int, limit: int, effect_id: String, range_mode: String) -> void:
	if source != focus and target != focus: return
	var link := {"source": source, "target": target, "kind": kind, "operation": operation, "trigger": trigger, "amount": amount, "limit": limit, "effect_id": effect_id, "range":range_mode}
	if not links.has(link): links.append(link)
