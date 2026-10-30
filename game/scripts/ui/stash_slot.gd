class_name StashSlot
extends Button

var item: ItemData

func _ready() -> void:
	custom_minimum_size = Vector2(68, 66)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if item != null: tooltip_text = item.display_name + "\n" + item.description

func _draw() -> void:
	if item == null: return
	var bounds := ItemIcons.extent(item)
	var pixel_scale := minf(44.0 / bounds.x, 42.0 / bounds.y)
	ItemIcons.draw_icon(self, item, Vector2((size.x - bounds.x * pixel_scale) / 2, 5), pixel_scale)
	var font := get_theme_default_font()
	var font_size := 16
	var title := item.display_name
	if font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 4:
		while title.length() > 1 and font.get_string_size(title + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - 4: title = title.left(-1)
		title += "…"
	draw_string(font, Vector2(2, size.y - 6), title, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, font_size, Color("e4d3ac"))
