class_name EffectApplier
extends RefCounted
## Pure, item-agnostic interpretation of the effect vocabulary.

const MAX_ACTIVE_ITEMS := 64
const MAX_ACTIVE_UNITS := 256

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

static func _amount(items: Dictionary, source: String, unit: Dictionary) -> int:
	if unit.scale == "flat": return unit.amount
	var count := 0
	for other: String in items:
		if other != source and has_tags(items[other], unit.condition_tags) and GridRules.adjacent(items[source], items[other]): count += 1
	return int(unit.amount) * mini(count, int(unit.max_matches))

static func plan(items: Dictionary, uid: String, trigger: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not within_budget(items): return result
	if not items.has(uid): return result
	var item: Dictionary = items[uid]
	var units: Array = item.effects.duplicate(true)
	units.sort_custom(_precedes)
	for unit: Dictionary in units:
		if unit.trigger != trigger or unit.operation == "modify_power": continue
		var base := _amount(items, uid, unit)
		var amount := base
		var bonuses: Array[Dictionary] = []
		var candidates: Array[Dictionary] = []
		for source: String in items:
			for modifier: Dictionary in items[source].effects:
				if modifier.trigger != "modify" or modifier.affects != unit.operation: continue
				if modifier.target == "self" and source != uid: continue
				if modifier.target == "adjacent_items" and (source == uid or not GridRules.adjacent(item, items[source])): continue
				if not has_tags(item, modifier.required_tags): continue
				var candidate := modifier.duplicate(true)
				candidate.source = source
				candidates.append(candidate)
		candidates.sort_custom(_precedes)
		var seen: Dictionary = {}
		for modifier: Dictionary in candidates:
			var key := str(modifier.stack_group)
			if not key.is_empty() and seen.has(key): continue
			var bonus := _amount(items, modifier.source, modifier)
			if bonus == 0: continue
			if not key.is_empty(): seen[key] = true
			amount += bonus
			bonuses.append({"source": modifier.source, "effect_id": modifier.id, "name": items[modifier.source].name, "amount": bonus})
		result.append({"kind": unit.operation, "source": uid, "effect_id": unit.id, "label": item.name,
			"target": "player" if unit.target == "self" else "enemy", "amount": amount,
			"base": base, "bonuses": bonuses, "priority": unit.priority, "max_per_action": unit.max_per_action})
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
