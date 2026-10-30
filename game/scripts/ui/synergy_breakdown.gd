class_name SynergyBreakdown
extends VBoxContainer
## Displays the modifiers already returned by the pure effect planner.

class MiniIcon extends Control:
	var item: ItemData
	func _init(value: ItemData) -> void:
		item = value
		custom_minimum_size = Vector2(34, 34)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = item.display_name
		accessibility_name = item.display_name

	func _draw() -> void:
		var extent := ItemIcons.extent(item)
		var factor := minf(32.0 / extent.x, 32.0 / extent.y)
		ItemIcons.draw_icon(self, item, (size - extent * factor) / 2.0, factor)

var rows: Array[Dictionary] = []

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func refresh(plans: Array[Dictionary], items: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rows.clear()
	for entry: Dictionary in plans:
		if not str(entry.plan.error).is_empty():
			visible = false
			return
	for entry: Dictionary in plans:
		var plan: Dictionary = entry.plan
		if plan.bonuses.is_empty() and plan.multipliers.is_empty(): continue
		var row := {"trigger": entry.trigger, "kind":plan.kind, "base":plan.base, "amount":plan.amount, "bonuses":plan.bonuses.duplicate(true), "multipliers":plan.multipliers.duplicate(true)}
		rows.append(row)
		var timing: String = {"use":"Use", "turn_end":"End Turn", "damage_taken":"On damage"}[entry.trigger]
		add_child(_label("%s · %s" % [timing, EffectText.operation(plan.kind)], Color("a6cbb3")))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 2)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(flow)
		var grouped: bool = not plan.bonuses.is_empty() and not plan.multipliers.is_empty()
		flow.add_child(_label(("(" if grouped else "") + "Base %d" % plan.base))
		for i in plan.bonuses.size():
			var bonus: Dictionary = plan.bonuses[i]
			var suffix := ")" if grouped and i == plan.bonuses.size() - 1 else ""
			flow.add_child(_modifier("+", bonus, "amount", suffix, items, Color("e0bb74")))
		for multiplier: Dictionary in plan.multipliers:
			flow.add_child(_modifier("×", multiplier, "factor", "", items, Color("82d8e8")))
		flow.add_child(_label("= %d" % plan.amount, Color("ecdfbf")))
	visible = not rows.is_empty()

func _modifier(operator: String, value: Dictionary, amount_key: String, suffix: String, items: Dictionary, color: Color) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.add_child(_label(operator, color))
	var uid := str(value.source)
	if items.has(uid) and items[uid] is ItemData:
		group.add_child(MiniIcon.new(items[uid]))
	else:
		group.add_child(_label(str(value.name), color))
	group.add_child(_label(str(value[amount_key]) + suffix, color))
	group.tooltip_text = str(value.name)
	group.accessibility_name = "%s %s %s" % [operator, str(value.name), str(value[amount_key])]
	return group

func _label(value: String, color := Color("ecdfbf")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	return label
