class_name IntentGlyph
extends Control
## Presentation-only symbols; the adjacent text carries the full meaning.

var operation := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(26, 26)

func set_operation(value: String) -> void:
	operation = value
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(26, 26))
	match operation:
		"guard", "set_guard":
			draw_colored_polygon(PackedVector2Array([Vector2(4,4), Vector2(13,2), Vector2(22,4), Vector2(22,14), Vector2(18,20), Vector2(13,24), Vector2(8,20), Vector2(4,14)]), Color("1c2929"))
			draw_colored_polygon(PackedVector2Array([Vector2(7,6), Vector2(13,4), Vector2(19,6), Vector2(19,14), Vector2(16,18), Vector2(13,21), Vector2(10,18), Vector2(7,14)]), Color("8bcdbd"))
			draw_rect(Rect2(12, 6, 2, 11), Color("e8d8ad"))
		"damage":
			draw_line(Vector2(5,21), Vector2(20,5), Color("1d2020"), 6)
			draw_line(Vector2(7,19), Vector2(20,5), Color("e1d5b6"), 3)
			draw_line(Vector2(5,14), Vector2(12,21), Color("cb7158"), 3)
		"health", "heal":
			draw_colored_polygon(PackedVector2Array([Vector2(3,8), Vector2(5,4), Vector2(10,4), Vector2(13,7), Vector2(16,4), Vector2(21,4), Vector2(23,8), Vector2(22,13), Vector2(13,22), Vector2(4,13)]), Color("c96d5e"))
			draw_rect(Rect2(7, 6, 3, 3), Color("f0c3a7"))
		"counting":
			draw_rect(Rect2(5, 3, 16, 3), Color("d2b47b"))
			draw_rect(Rect2(5, 20, 16, 3), Color("d2b47b"))
			draw_line(Vector2(7, 6), Vector2(19, 20), Color("d2b47b"), 2)
			draw_line(Vector2(19, 6), Vector2(7, 20), Color("d2b47b"), 2)
		_:
			draw_rect(Rect2(3, 3, 20, 20), Color("414a47"))
			var font := get_theme_default_font()
			if font != null: draw_string(font, Vector2(5, 21), "?", HORIZONTAL_ALIGNMENT_CENTER, 16, 20, Color("ecdfbf"))
	draw_set_transform(Vector2.ZERO)
