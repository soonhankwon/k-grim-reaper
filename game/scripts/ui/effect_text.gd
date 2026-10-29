class_name EffectText
extends RefCounted
## Generic vocabulary for effects. Content copy never owns computed numbers.

static func operation(kind: String) -> String:
	return {"damage": "공격", "guard": "방어", "heal": "회복", "set_guard": "방어 설정", "modify_power": "위력 보너스", "multiply_power": "위력 배율"}.get(kind, kind)

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
			var timing: String = {"use": "사용", "turn_end": "턴 종료", "damage_taken": "피해 반응"}[trigger]
			var recipient := "자신" if plan.target == "player" else "적"
			var text := "%s: %s %s %d" % [timing, recipient, operation(plan.kind), plan.amount]
			if not plan.multipliers.is_empty():
				var formula := str(plan.base)
				for bonus: Dictionary in plan.bonuses: formula += " + %d" % bonus.amount
				formula = "(" + formula + ")"
				for multiplier: Dictionary in plan.multipliers: formula += " × %d" % multiplier.factor
				text += "\n계산: " + formula
			result.append(text)
	for unit: Dictionary in item.effects:
		if unit.trigger == "modify":
			var recipient: String = {"adjacent_items":"상하좌우 물건", "diagonal_items":"대각선 물건", "neighbor_items":"상하좌우·대각선 물건"}.get(unit.target, "이 물건")
			var filter := " [%s]" % _tags(unit.required_tags, tags) if not unit.required_tags.is_empty() else ""
			var amount_text := "×%d" % unit.amount if unit.operation == "multiply_power" else "+%d" % unit.amount
			result.append("%s%s %s %s" % [recipient, filter, operation(unit.affects), amount_text])
		if unit.scale in ["per_adjacent", "per_diagonal", "per_neighbor"]:
			var range_name: String = {"per_adjacent":"상하좌우", "per_diagonal":"대각선", "per_neighbor":"상하좌우·대각선"}[unit.scale]
			var condition := _tags(unit.condition_tags, tags) if not unit.condition_tags.is_empty() else "모든 물건"
			result.append("%s [%s] ×%d · 최대 %d개" % [range_name, condition, unit.amount, unit.max_matches])
	return result
