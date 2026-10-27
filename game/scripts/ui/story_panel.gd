class_name StoryPanel
extends PanelContainer
## Read-only notebook. The scroll list contains only already presented entries.

var scroll: ScrollContainer
var column: VBoxContainer
var _key := ""

func _ready() -> void:
	position = Vector2(974, 76)
	size = Vector2(272, 250)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242a2b")
	style.border_color = Color("8b7955")
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(column)
	hide()

func refresh(entries: Array[Dictionary]) -> void:
	var key := JSON.stringify(entries)
	if key == _key: return
	_key = key
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		var title := Label.new()
		title.text = entry.title
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", Color("e0bb74"))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(title)
		var text := Label.new()
		text.text = entry.text
		text.add_theme_font_size_override("font_size", 14)
		text.add_theme_color_override("font_color", Color("ecdfbf"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(text)
	scroll.scroll_vertical = 0
