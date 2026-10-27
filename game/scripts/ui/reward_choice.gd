class_name RewardChoice
extends Button

var item: ItemData
var chosen := false

func _ready() -> void:
	custom_minimum_size = Vector2(380, 132)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = true
	var title := Label.new()
	title.position = Vector2(94, 12)
	title.size = Vector2(270, 28)
	title.text = item.display_name
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 19)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var summary := Label.new()
	summary.position = Vector2(94, 44)
	summary.size = Vector2(270, 72)
	summary.text = "%d칸 · 기력 %d · 턴당 %d회\n%s" % [item.footprint.size(), item.cost, item.uses_per_turn, item.description]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.max_lines_visible = 3
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.add_theme_font_size_override("font_size", 12)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)
	tooltip_text = item.display_name + "\n" + item.description
	accessibility_name = "보상 후보 " + item.display_name

func _draw() -> void:
	if item == null: return
	var bounds := ItemIcons.extent(item)
	var factor := minf(64.0 / bounds.x, 80.0 / bounds.y)
	ItemIcons.draw_icon(self, item, Vector2(14 + (64 - bounds.x * factor) / 2, 14), factor)
	if chosen:
		draw_rect(Rect2(Vector2(2,2), size - Vector2(4,4)), Color("e0bb74"), false, 3)
		draw_string(get_theme_default_font(), Vector2(14, 118), "선택 중", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("e0bb74"))
