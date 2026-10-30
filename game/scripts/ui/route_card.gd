class_name RouteCard
extends WoodenButton
## Compact route information. Selection still goes through RoutePanel's signal.

var route: Dictionary = {}
var enemy: Dictionary = {}
var later: Dictionary = {}
var motif := ""
var title_label: Label
var enemy_label: Label
var hp_label: Label
var intent_label: Label
var reaction_label: Label
var later_label: Label
var details_scroll: ScrollContainer
var _portrait := Rect2(14, 38, 76, 82)

func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(0, 150)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title_label = _label(str(route.name), 20, Color("e0bb74"))
	title_label.position = Vector2(14, 8)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
	details_scroll = ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(details_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	details_scroll.add_child(column)
	enemy_label = _label(str(enemy.name), 20, Color("ecdfbf"))
	enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(enemy_label)
	var stats := HFlowContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 2)
	column.add_child(stats)
	var health_group := HBoxContainer.new()
	health_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_group.add_theme_constant_override("separation", 4)
	stats.add_child(health_group)
	var heart := IntentGlyph.new()
	heart.set_operation("health")
	health_group.add_child(heart)
	hp_label = _label("HP %d" % int(enemy.hp), 20, Color("f0cbb2"))
	health_group.add_child(hp_label)
	var intent_group := HBoxContainer.new()
	intent_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent_group.add_theme_constant_override("separation", 4)
	stats.add_child(intent_group)
	var glyph := IntentGlyph.new()
	glyph.set_operation(str(enemy.intents[0].operation))
	intent_group.add_child(glyph)
	intent_label = _label(_intent_text(enemy.intents[0]), 20, Color("e7d6a6"))
	intent_group.add_child(intent_label)
	var reactions := EffectText.enemy_reactions(enemy.reactions)
	reaction_label = _label("", 18, Color("f2bba5"))
	for reaction: String in reactions:
		if not reaction_label.text.is_empty(): reaction_label.text += "\n"
		reaction_label.text += reaction.replace("\n", " · ")
	reaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reaction_label.visible = not reactions.is_empty()
	column.add_child(reaction_label)
	later_label = _label("Later: " + str(later.get("name", "")), 18, Color("d0d4c3"))
	later_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	later_label.visible = not later.is_empty()
	column.add_child(later_label)
	var summary := "%s\n%s\n%s · HP %d · First move: %s" % [route.name, route.description, enemy.name, enemy.hp, _intent_text(enemy.intents[0])]
	if not reactions.is_empty(): summary += "\n" + "\n".join(reactions)
	if not later.is_empty(): summary += "\nLater: " + str(later.name)
	tooltip_text = summary
	accessibility_name = summary
	resized.connect(_fit_contents)
	_fit_contents()

func _fit_contents() -> void:
	if title_label == null: return
	title_label.size = Vector2(maxf(0, size.x - 28), 26)
	details_scroll.position = Vector2(104, 36)
	details_scroll.size = Vector2(maxf(0, size.x - 118), maxf(0, size.y - 42))
	queue_redraw()

func _intent_text(intent: Dictionary) -> String:
	return EffectText.intent(intent)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _draw() -> void:
	_draw_location()
	var visual: Dictionary = enemy.get("visual", {})
	var custom := PresentationArt.visual_texture(str(visual.get("texture_path", "")))
	var texture := custom if custom != null else PresentationArt.actor_texture(str(visual.get("presentation_id", "")))
	if texture == null: return
	var region := Rect2(Vector2.ZERO, texture.get_size()) if custom != null else PresentationArt.actor_region(str(visual.get("presentation_id", "")))
	if not region.has_area(): return
	var factor := minf(_portrait.size.x / region.size.x, _portrait.size.y / region.size.y)
	var sprite_size := region.size * factor
	draw_texture_rect_region(texture, Rect2(_portrait.position + (_portrait.size - sprite_size) / 2, sprite_size), region)

func _draw_location() -> void:
	var ink := Color(0.11, 0.13, 0.13, 0.34)
	var x := size.x - 104
	if motif == "bamboo":
		for offset in [0, 30, 64]:
			draw_rect(Rect2(x + offset, 35, 8, maxf(0, size.y - 44)), ink)
			for y in [52, 76, 100]:
				draw_line(Vector2(x + offset - 2, y), Vector2(x + offset + 10, y), Color(0.64, 0.66, 0.52, 0.18), 2)
				draw_line(Vector2(x + offset + 4, y), Vector2(x + offset + 18, y - 10), ink, 4)
	elif motif == "pond":
		draw_circle(Vector2(size.x - 44, 58), 21, Color(0.52, 0.66, 0.70, 0.13))
		for y in [88, 102, 116]:
			draw_line(Vector2(size.x - 118, y), Vector2(size.x - 12, y), Color(0.38, 0.59, 0.63, 0.23), 4)
			draw_line(Vector2(size.x - 96, y + 5), Vector2(size.x - 40, y + 5), ink, 2)
