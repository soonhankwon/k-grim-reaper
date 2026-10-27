class_name EffectText
extends RefCounted
## Generic vocabulary for effects. Content copy never owns computed numbers.

static func operation(kind: String) -> String:
	return {"damage": "공격", "guard": "방어", "heal": "회복", "set_guard": "방어 설정", "modify_power": "위력 보너스"}.get(kind, kind)

static func _tags(tags: Array, labels: Dictionary) -> String:
	var names: PackedStringArray = []
	for tag: String in tags: names.append(labels.get(tag, tag))
	return ", ".join(names)

static func lines(item: Dictionary, items: Dictionary, uid: String, tags: Dictionary = {}) -> PackedStringArray:
	var result: PackedStringArray = []
	for trigger in ["use", "turn_end", "damage_taken"]:
		for plan in EffectApplier.plan(items, uid, trigger):
			var timing: String = {"use": "사용", "turn_end": "턴 종료", "damage_taken": "피해 반응"}[trigger]
			var recipient := "자신" if plan.target == "player" else "적"
			result.append("%s: %s %s %d" % [timing, recipient, operation(plan.kind), plan.amount])
	for unit: Dictionary in item.effects:
		if unit.trigger == "modify":
			var recipient := "인접 물건" if unit.target == "adjacent_items" else "이 물건"
			var filter := " [%s]" % _tags(unit.required_tags, tags) if not unit.required_tags.is_empty() else ""
			result.append("%s%s %s +%d" % [recipient, filter, operation(unit.affects), unit.amount])
		if unit.scale == "per_adjacent":
			result.append("인접 [%s] ×%d · 최대 %d개" % [_tags(unit.condition_tags, tags), unit.amount, unit.max_matches])
	return result
