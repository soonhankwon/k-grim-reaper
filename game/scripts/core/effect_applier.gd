class_name EffectApplier
extends RefCounted
## Pure, item-agnostic interpretation of the effect vocabulary.

const MAX_ACTIVE_ITEMS := 64
const MAX_ACTIVE_UNITS := 256
# Largest exact integer preserved by JSON save/load, not a balance cap.
const MAX_EXACT := 9007199254740991
const POWER_ERROR := "효과 수치가 정확하게 처리할 수 있는 한도를 초과했습니다."

static func within_budget(items: Dictionary) -> bool:
	if items.size() > MAX_ACTIVE_ITEMS: return false
	var count := 0
	for item: Dictionary in items.values():
		count += item.effects.size()
		if count > MAX_ACTIVE_UNITS: return false
	return true

static func has_trigger(item: Dictionary, trigger: String) -> bool:
	for unit: Dictionary in item.effects:
		if unit.trigger == trigger: return true
	return false

static func has_tags(item: Dictionary, required: Array) -> bool:
	for tag: String in required:
		if tag not in item.tags: return false
	return true

static func _precedes(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority: return a.priority < b.priority
	if a.get("source", "") != b.get("source", ""): return str(a.get("source", "")) < str(b.get("source", ""))
	return str(a.id) < str(b.id)

static func _matches(items: Dictionary, source: String, unit: Dictionary) -> Array[String]:
	var matches: Array[String] = []
	if unit.scale == "flat": return matches
	var range_mode := _range_for_scale(unit.scale)
	for other: String in items:
		if other != source and has_tags(items[other], unit.condition_tags) and GridRules.in_range(items[source], items[other], range_mode): matches.append(other)
	matches.sort()
	return matches

static func _range_for_scale(scale: String) -> String:
	return {"per_adjacent":"orthogonal", "per_diagonal":"diagonal", "per_neighbor":"neighbor"}.get(scale, "")

static func _range_for_target(target: String) -> String:
	return {"adjacent_items":"orthogonal", "diagonal_items":"diagonal", "neighbor_items":"neighbor"}.get(target, "")

static func _amount(unit: Dictionary, matches: Array[String]) -> int:
	if unit.scale == "flat": return unit.amount
	return int(unit.amount) * mini(matches.size(), int(unit.max_matches))

static func plan(items: Dictionary, uid: String, trigger: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not within_budget(items): return result
	if not items.has(uid): return result
	var item: Dictionary = items[uid]
	var units: Array = item.effects.duplicate(true)
	units.sort_custom(_precedes)
	for unit: Dictionary in units:
		if unit.trigger != trigger or unit.operation in ["modify_power", "multiply_power"]: continue
		var matches := _matches(items, uid, unit)
		var base := _amount(unit, matches)
		var amount := base
		var bonuses: Array[Dictionary] = []
		var multipliers: Array[Dictionary] = []
		var error := ""
		var candidates: Array[Dictionary] = []
		for source: String in items:
			for modifier: Dictionary in items[source].effects:
				if modifier.trigger != "modify" or modifier.affects != unit.operation: continue
				if modifier.target == "self" and source != uid: continue
				var range_mode := _range_for_target(modifier.target)
				if not range_mode.is_empty() and (source == uid or not GridRules.in_range(item, items[source], range_mode)): continue
				if not has_tags(item, modifier.required_tags): continue
				var candidate := modifier.duplicate(true)
				candidate.source = source
				candidates.append(candidate)
		candidates.sort_custom(_precedes)
		var seen: Dictionary = {}
		for modifier: Dictionary in candidates:
			if modifier.operation != "modify_power": continue
			var key := str(modifier.stack_group)
			if not key.is_empty() and seen.has(key): continue
			var bonus_matches := _matches(items, modifier.source, modifier)
			var bonus := _amount(modifier, bonus_matches)
			if bonus == 0: continue
			if not key.is_empty(): seen[key] = true
			amount += bonus
			bonuses.append({"source": modifier.source, "effect_id": modifier.id, "name": items[modifier.source].name, "amount": bonus, "range": _range_for_target(modifier.target), "matches": bonus_matches, "match_range": _range_for_scale(modifier.scale), "max_matches": modifier.max_matches})
		# Groups are independent per operation. Multipliers apply after all additions.
		seen.clear()
		for modifier: Dictionary in candidates:
			if modifier.operation != "multiply_power": continue
			var key := str(modifier.stack_group)
			if not key.is_empty() and seen.has(key): continue
			var factor := int(modifier.amount)
			if factor < 1:
				error = "배율은 1 이상의 정수여야 합니다."
				amount = 0
				break
			if not key.is_empty(): seen[key] = true
			multipliers.append({"source": modifier.source, "effect_id": modifier.id, "name": items[modifier.source].name, "factor": factor, "range": _range_for_target(modifier.target)})
			@warning_ignore("integer_division")
			var limit: int = MAX_EXACT / factor
			if amount > limit:
				error = POWER_ERROR
				amount = 0
				break
			amount *= factor
		result.append({"kind": unit.operation, "source": uid, "effect_id": unit.id, "label": item.name,
			"target": "player" if unit.target == "self" else "enemy", "amount": amount,
			"base": base, "matches": matches, "match_range": _range_for_scale(unit.scale), "max_matches": unit.max_matches, "bonuses": bonuses, "multipliers": multipliers, "error": error, "priority": unit.priority, "max_per_action": unit.max_per_action})
	return result

static func actor_plan(unit: Dictionary, owner: String, label: String) -> Dictionary:
	return {"kind": unit.operation, "source": owner, "effect_id": unit.id, "label": label,
		"target": owner if unit.target == "self" else ("enemy" if owner == "player" else "player"),
		"amount": unit.amount, "base": unit.amount, "bonuses": [], "priority": unit.priority,
		"max_per_action": unit.max_per_action}

static func evaluate(state: Dictionary, effect: Dictionary) -> Dictionary:
	var target: String = effect.target
	var hp_key := "health" if target == "player" else "enemy_health"
	var guard_key := "guard" if target == "player" else "enemy_guard"
	var maximum: int = state.config.max_health if target == "player" else state.config.encounters[state.encounter].hp
	if state[hp_key] <= 0: return {"skip": true}
	var amount := maxi(0, int(effect.amount))
	var changes: Dictionary = {}
	var details: Dictionary = {}
	var damage := 0
	var message := ""
	match effect.kind:
		"damage":
			var absorbed := mini(int(state[guard_key]), amount)
			damage = mini(int(state[hp_key]), amount - absorbed)
			changes[guard_key] = int(state[guard_key]) - absorbed
			changes[hp_key] = int(state[hp_key]) - damage
			details = {"absorbed": absorbed, "health_damage": damage}
			message = "%s: 피해 %d (방어 %d)" % [effect.label, damage, absorbed]
		"guard":
			if amount > MAX_EXACT - int(state[guard_key]): return {"error": POWER_ERROR}
			changes[guard_key] = int(state[guard_key]) + amount
			message = "%s: 방어 +%d" % [effect.label, amount]
		"set_guard":
			changes[guard_key] = amount
			message = "%s: 방어 %d" % [effect.label, amount]
		"heal":
			var recovered := mini(amount, maxi(0, maximum - int(state[hp_key])))
			changes[hp_key] = int(state[hp_key]) + recovered
			message = "%s: 체력 +%d" % [effect.label, recovered]
		_: return {"error": "지원하지 않는 효과 연산입니다."}
	return {"changes": changes, "details": details, "damage": damage, "message": message}
