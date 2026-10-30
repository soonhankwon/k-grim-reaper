class_name EffectText
extends RefCounted
## Generic vocabulary for effects. Content copy never owns computed numbers.

static func operation(kind: String) -> String:
	return {"damage": "Attack", "guard": "Block", "heal": "Heal", "set_guard": "Set Block", "modify_power": "Power Bonus", "multiply_power": "Power Multiplier"}.get(kind, kind)

static func intent(unit: Dictionary) -> String:
	var target := " (you)" if unit.get("target", "") != "self" else (" (self)" if unit.get("operation", "") == "damage" else "")
	return "%s %d%s" % [operation(str(unit.operation)), int(unit.amount), target]

static func enemy_reactions(units: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	for unit: Dictionary in units:
		var target := "self" if unit.target == "self" else "you"
		var lethal := "lethal: no" if unit.target == "self" else "lethal: yes"
		lines.append("HP hit → %s %d (%s)\n%d/action · %s" % [operation(unit.operation), unit.amount, target, unit.max_per_action, lethal])
	return lines

static func _tags(tags: Array, labels: Dictionary) -> String:
	var names: PackedStringArray = []
	for tag: String in tags: names.append(labels.get(tag, tag))
	return ", ".join(names)

static func lines(item: Dictionary, items: Dictionary, uid: String, tags: Dictionary = {}) -> PackedStringArray:
	var result: PackedStringArray = []
	for trigger in ["use", "turn_end", "damage_taken"]:
		for plan in EffectApplier.plan(items, uid, trigger):
			if not plan.error.is_empty():
				result.append(plan.error)
				continue
			var timing: String = {"use": "Use", "turn_end": "End Turn", "damage_taken": "On damage"}[trigger]
			var recipient := "Self" if plan.target == "player" else "Enemy"
			var text := "%s: %s %d → %s" % [timing, operation(plan.kind), plan.amount, recipient]
			result.append(text)
	for unit: Dictionary in item.effects:
		if unit.trigger == "modify":
			var recipient: String = {"adjacent_items":"Adjacent items", "diagonal_items":"Diagonal items", "neighbor_items":"Adjacent + diagonal items"}.get(unit.target, "This item")
			var filter := " [%s]" % _tags(unit.required_tags, tags) if not unit.required_tags.is_empty() else ""
			var amount_text := "×%d" % unit.amount if unit.operation == "multiply_power" else "+%d" % unit.amount
			result.append("%s%s %s %s" % [recipient, filter, operation(unit.affects), amount_text])
		if unit.scale in ["per_adjacent", "per_diagonal", "per_neighbor"]:
			var range_name: String = {"per_adjacent":"Adjacent", "per_diagonal":"Diagonal", "per_neighbor":"Adjacent + diagonal"}[unit.scale]
			var condition := _tags(unit.condition_tags, tags) if not unit.condition_tags.is_empty() else "All items"
			result.append("%s [%s] ×%d · max %d" % [range_name, condition, unit.amount, unit.max_matches])
	return result
