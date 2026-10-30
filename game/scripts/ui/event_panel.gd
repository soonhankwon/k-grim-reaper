class_name EventPanel
extends PanelContainer
## Story choice buttons submit requests; the panel never changes gameplay data.

signal action_requested(kind: String)
var heading: Label
var description: Label
var take: Button
var leave: Button

func _ready() -> void:
	position = Vector2(24, 466)
	size = Vector2(1232, 220)
	add_theme_stylebox_override("panel", WoodcutSkin.box("panel"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color("e0bb74"))
	column.add_child(heading)
	description = Label.new()
	description.add_theme_font_size_override("font_size", 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	take = WoodenButton.new()
	leave = WoodenButton.new()
	for button in [take, leave]:
		button.add_theme_font_size_override("font_size", 20)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 60)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(button)
	take.pressed.connect(func(): action_requested.emit("event_take"))
	leave.pressed.connect(func(): action_requested.emit("event_leave"))
	hide()

func refresh(view: Dictionary, busy: bool) -> void:
	visible = view.phase in ["event", "event_result"]
	if not visible: return
	var entry := EventRules.definition(view)
	if entry.is_empty():
		hide()
		return
	heading.text = entry.title if view.phase == "event" else "A Memory Answers"
	if view.phase == "event":
		description.text = entry.description
		if EventRules.resolution(view).get("allow_stash", false):
			take.text = entry.take_label + (" · in storage" if view.event.selected == "take" else " · place in storage")
		else:
			take.text = entry.take_label + (" · move from storage to bag to confirm" if view.event.selected == "take" else " · requires bag space")
		leave.text = entry.leave_label
		take.visible = true
		leave.visible = true
		take.disabled = busy or view.event.selected == "take"
		leave.disabled = busy
	else:
		if view.event.get("method", "") == "resolution":
			description.text = str(EventRules.resolution(view).result)
		else:
			description.text = entry.take_result + "  ·  HP %d / %d (heals up to %d)" % [view.health, view.config.max_health, entry.heal_amount] if view.event.outcome == "take" else entry.leave_result
		take.hide()
		leave.hide()
