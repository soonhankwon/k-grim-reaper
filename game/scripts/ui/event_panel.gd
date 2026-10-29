class_name EventPanel
extends PanelContainer
## Story choice buttons submit requests; the panel never changes gameplay data.

signal action_requested(kind: String)
var heading: Label
var description: Label
var take: Button
var leave: Button

func _ready() -> void:
	position = Vector2(24, 486)
	size = Vector2(1232, 200)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202b2c")
	style.border_color = Color("8b7955")
	style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color("e0bb74"))
	column.add_child(heading)
	description = Label.new()
	description.add_theme_font_size_override("font_size", 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	take = Button.new()
	leave = Button.new()
	for button in [take, leave]:
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
	heading.text = entry.title if view.phase == "event" else "기억의 응답"
	if view.phase == "event":
		description.text = entry.description
		if EventRules.resolution(view).get("allow_stash", false):
			take.text = entry.take_label + (" · 보관대에 있음" if view.event.selected == "take" else " · 보관대에 놓기")
		else:
			take.text = entry.take_label + (" · 보관대에서 보따리에 넣어 확정" if view.event.selected == "take" else " · 보따리 공간 필요")
		leave.text = entry.leave_label
		take.visible = true
		leave.visible = true
		take.disabled = busy or view.event.selected == "take"
		leave.disabled = busy
	else:
		if view.event.get("method", "") == "resolution":
			description.text = str(EventRules.resolution(view).result)
		else:
			description.text = entry.take_result + "  ·  체력 %d / %d (최대 %d 회복)" % [view.health, view.config.max_health, entry.heal_amount] if view.event.outcome == "take" else entry.leave_result
		take.hide()
		leave.hide()
