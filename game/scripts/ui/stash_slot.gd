class_name StashSlot
extends Button

var item: ItemData

func _ready() -> void:
	custom_minimum_size = Vector2(68, 66)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	if item == null: return
	var bounds := ItemIcons.extent(item)
	var pixel_scale := minf(44.0 / bounds.x, 42.0 / bounds.y)
	ItemIcons.draw_icon(self, item, Vector2((size.x - bounds.x * pixel_scale) / 2, 5), pixel_scale)
	draw_string(get_theme_default_font(), Vector2(2, size.y - 6), item.display_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 11, Color("e4d3ac"))
