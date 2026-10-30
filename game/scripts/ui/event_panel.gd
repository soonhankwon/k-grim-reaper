class_name EventPanel
extends PanelContainer
## Story choice buttons submit requests; the panel never changes gameplay data.

signal action_requested(kind: String)
var heading: Label
var description: Label
var description_scroll: ScrollContainer
var scenes: Dictionary = {}
var _displayed_text := ""
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
	description_scroll = ScrollContainer.new()
	description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	description_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(description_scroll)
	description = Label.new()
	description.add_theme_font_size_override("font_size", 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_scroll.add_child(description)
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
	heading.text = entry.title if view.phase == "event" else "The First Delivery · Outcome"
	var scene: Dictionary = scenes.get(view.event.get("id", ""), {})
	if not scene.is_empty(): heading.text += " · Scroll to read"
	var next_text := ""
	if view.phase == "event":
		next_text = str(scene.get("discovery", entry.description))
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
			next_text = str(scene.get("listen", EventRules.resolution(view).result))
		else:
			next_text = entry.take_result + "  ·  HP %d / %d (heals up to %d)" % [view.health, view.config.max_health, entry.heal_amount] if view.event.outcome == "take" else entry.leave_result
			if not scene.is_empty():
				var ending := "fight_carried" if view.event.outcome == "take" else ("fight_stashed" if view.event.selected == "take" else "fight_left")
				next_text = str(scene[ending])
		take.hide()
		leave.hide()
	if next_text != _displayed_text:
		_displayed_text = next_text
		description.text = next_text
		description_scroll.scroll_vertical = 0
