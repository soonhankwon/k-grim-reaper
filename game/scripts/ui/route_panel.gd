class_name RoutePanel
extends PanelContainer
## Presents authored route choices; all mutations go through the session.

signal chosen(route_id: String)
var choices: Array[Button] = []
var _row: HBoxContainer
var _key := ""
var _motifs: Dictionary = {}
const ROUTE_ART := "res://data/presentation/route-art.json"

func _ready() -> void:
	position = Vector2(24, 466)
	size = Vector2(1232, 220)
	add_theme_stylebox_override("panel", WoodcutSkin.box("panel"))
	if FileAccess.file_exists(ROUTE_ART):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTE_ART))
		if data is Dictionary: _motifs = data
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var heading := Label.new()
	heading.text = "Crossroads · Compare the next enemies and choose a path"
	heading.add_theme_font_size_override("font_size", 20)
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
	var key := JSON.stringify([view.config.routes, view.config.encounters])
	if key != _key:
		_key = key
		for child in _row.get_children():
			_row.remove_child(child)
			child.queue_free()
		choices.clear()
		for route: Dictionary in view.config.routes:
			var next: Dictionary = view.config.encounters[route.encounters[1]]
			var has_later: bool = route.encounters.size() > 2 and view.config.get("resolutions", []).is_empty()
			var later: Dictionary = view.config.encounters[route.encounters[2]] if has_later else {}
			var button := RouteCard.new()
			button.route = route.duplicate(true)
			button.enemy = next.duplicate(true)
			button.later = later.duplicate(true)
			button.motif = str(_motifs.get(route.id, ""))
			button.pressed.connect(func(): chosen.emit(route.id))
			_row.add_child(button)
			choices.append(button)
	for choice in choices: choice.disabled = busy
