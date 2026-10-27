class_name RoutePanel
extends PanelContainer
## Presents authored route choices; all mutations go through the session.

signal chosen(route_id: String)
var choices: Array[Button] = []
var _row: HBoxContainer
var _key := ""

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
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "갈림길 · 다음에 만날 적을 비교하고 길을 고르세요"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("e0bb74"))
	column.add_child(heading)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	column.add_child(_row)
	hide()

func refresh(view: Dictionary, busy: bool) -> void:
	visible = view.phase == "route"
	if not visible:
		_key = ""
		return
	var key := JSON.stringify(view.config.routes)
	if key != _key:
		_key = key
		for child in _row.get_children():
			_row.remove_child(child)
			child.queue_free()
		choices.clear()
		for route: Dictionary in view.config.routes:
			var next: Dictionary = view.config.encounters[route.encounters[1]]
			var later: Dictionary = view.config.encounters[route.encounters[2]] if route.encounters.size() > 2 else {}
			var intent: Dictionary = next.intents[0]
			var button := Button.new()
			button.text = "%s\n%s\n다음: %s · 체력 %d · 첫 행동 %s %d%s" % [route.name, route.description,
				next.name, next.hp, EffectText.operation(intent.operation), intent.amount,
				"\n그다음: " + str(later.name) if not later.is_empty() else ""]
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size = Vector2(0, 132)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 15)
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.pressed.connect(func(): chosen.emit(route.id))
			_row.add_child(button)
			choices.append(button)
	for choice in choices: choice.disabled = busy
