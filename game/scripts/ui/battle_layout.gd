class_name BattleLayout
extends Control
## Presentation layout only. All interaction and displayed state are supplied by Main.

const PAPER := Color("ecdfbf")
const MUTED := Color("aaa58f")
const GOLD := Color("e0bb74")
const JADE := Color("a6cbb3")
var labels: Dictionary = {}
var buttons: Dictionary = {}
var board: InventoryBoard
var road: RoadView
var stash_grid: GridContainer
var preparation: Control
var details: PanelContainer
var detail_scroll: ScrollContainer
var log_scroll: ScrollContainer
var enemy_bar: ProgressBar
var hero_bar: ProgressBar
var intent_icon: IntentGlyph
var rewards: RewardPanel
var routes: RoutePanel
var guide: GuidePanel
var story: StoryPanel
var encounter_event: EventPanel
var turn_preview: PanelContainer
var turn_preview_scroll: ScrollContainer
var background_texture: Texture2D = PresentationArt.BACKGROUND
var reaction_panel: PanelContainer
var reaction_scroll: ScrollContainer
var synergy_breakdown: SynergyBreakdown

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1280, 720)
	_build()
	get_parent().resized.connect(_fit)
	_fit()

func _fit() -> void:
	var available: Vector2 = get_parent().size
	var factor := minf(available.x / 1280, available.y / 720)
	scale = Vector2.ONE * factor
	position = (available - size * factor) / 2

func _label(parent: Node, key: String, value: String, rect: Rect2, font_size := 16, color := PAPER) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	# All body glyphs resolve to at least 8 native pixels in the 360p viewport.
	label.add_theme_font_size_override("font_size", maxi(16, ceili(font_size / 2.0) * 2))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	if not key.is_empty(): labels[key] = label
	return label

func _button(parent: Node, key: String, text: String, rect: Rect2) -> Button:
	var button := WoodenButton.new() if key == "primary" else Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	buttons[key] = button
	return button

func _bar(rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.show_percentage = false
	bar.add_theme_font_size_override("font_size", 1)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	# Apply size after theme/percentage setup; the default minimum otherwise lingers.
	bar.size = rect.size
	return bar

func _build() -> void:
	_label(self, "", "Reaper's Bundle", Rect2(24, 10, 232, 30), 20, GOLD)
	_label(self, "chapter", "", Rect2(270, 14, 400, 26), 18)
	_label(self, "edition", "First Delivery", Rect2(740, 14, 185, 24), 16, MUTED)
	_button(self, "story", "Story", Rect2(934, 8, 100, 32)).add_theme_font_size_override("font_size", 16)
	_button(self, "guide", "Guide", Rect2(1042, 8, 84, 32)).add_theme_font_size_override("font_size", 16)
	_button(self, "restart", "Restart", Rect2(1134, 8, 122, 32)).add_theme_font_size_override("font_size", 16)
	_label(self, "bag", "", Rect2(330, 50, 260, 22), 16, GOLD)
	_label(self, "synergy_state", "", Rect2(590, 50, 338, 22), 12, JADE).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(self, "passive", "", Rect2(750, 432, 240, 18), 13, JADE)
	reaction_panel = PanelContainer.new()
	reaction_panel.position = Vector2(320, 408)
	reaction_panel.size = Vector2(425, 54)
	reaction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var reaction_style := StyleBoxFlat.new()
	reaction_style.bg_color = Color("1b2328")
	reaction_style.border_color = Color("b98164")
	reaction_style.set_border_width_all(1)
	reaction_style.set_content_margin_all(1)
	reaction_panel.add_theme_stylebox_override("panel", reaction_style)
	add_child(reaction_panel)
	reaction_scroll = ScrollContainer.new()
	reaction_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reaction_panel.add_child(reaction_scroll)
	var reaction_text := _label(reaction_scroll, "enemy_reactions", "", Rect2(0, 0, 405, 0), 20, Color("ffe0c5"))
	reaction_text.custom_minimum_size.x = 405
	reaction_panel.hide()
	board = InventoryBoard.new()
	board.position = Vector2(414, 84)
	board.size = Vector2(412, 324)
	add_child(board)
	preparation = Control.new()
	preparation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preparation)
	_label(preparation, "", "Storage", Rect2(32, 78, 230, 26), 18, GOLD)
	_label(preparation, "", "Drag items into your bag", Rect2(32, 109, 232, 24), 18, MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(32, 144)
	scroll.size = Vector2(232, 204)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preparation.add_child(scroll)
	stash_grid = GridContainer.new()
	stash_grid.columns = 3
	stash_grid.add_theme_constant_override("h_separation", 6)
	stash_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(stash_grid)
	_button(preparation, "rotate", "Rotate  R", Rect2(32, 360, 110, 34))
	_button(preparation, "stash", "Store", Rect2(150, 360, 110, 34))
	_button(preparation, "undo", "Undo  Ctrl+Z", Rect2(32, 402, 228, 34)).add_theme_font_size_override("font_size", 16)
	turn_preview = PanelContainer.new()
	turn_preview.position = Vector2(32, 78)
	turn_preview.size = Vector2(260, 328)
	turn_preview.add_theme_stylebox_override("panel", WoodcutSkin.box("preview"))
	add_child(turn_preview)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 6)
	turn_preview.add_child(preview_column)
	_label(preview_column, "preview_title", "If you end your turn", Rect2(0, 0, 0, 0), 20, GOLD)
	_label(preview_column, "preview_summary", "", Rect2(0, 0, 0, 0), 20, PAPER)
	var preview_scroll := ScrollContainer.new()
	turn_preview_scroll = preview_scroll
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_column.add_child(preview_scroll)
	var preview_body := _label(preview_scroll, "preview_body", "", Rect2(0, 0, 220, 0), 20, PAPER)
	preview_body.custom_minimum_size.x = 220
	turn_preview.hide()
	var primary_button := _button(self, "primary", "Start Battle", Rect2(974, 350, 272, 54))
	primary_button.add_theme_font_size_override("font_size", 20)
	primary_button.add_theme_stylebox_override("normal", WoodcutSkin.box("primary"))
	primary_button.add_theme_stylebox_override("hover", WoodcutSkin.box("primary_hover"))
	primary_button.add_theme_stylebox_override("pressed", WoodcutSkin.box("primary_pressed"))
	_button(self, "skip", "Skip Animation", Rect2(1058, 414, 188, 32)).add_theme_font_size_override("font_size", 16)
	var resolution := _button(self, "resolution", "", Rect2(974, 410, 272, 36))
	resolution.name = "ResolutionButton"
	resolution.add_theme_font_size_override("font_size", 16)
	resolution.hide()
	road = RoadView.new()
	road.position = Vector2(0, 446)
	road.size = Vector2(1280, 206)
	add_child(road)
	_label(self, "hero_name", "Rookie Reaper", Rect2(144, 475, 190, 30), 17, PAPER).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(self, "energy", "", Rect2(350, 511, 210, 42), 19, GOLD)
	_label(self, "enemy", "", Rect2(810, 487, 240, 30), 18, PAPER).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(self, "intent", "", Rect2(780, 455, 320, 30), 19, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_icon = IntentGlyph.new()
	intent_icon.position = Vector2(750, 455)
	intent_icon.size = Vector2(26, 26)
	add_child(intent_icon)
	hero_bar = _bar(Rect2(145, 649, 190, 12), Color("ac5c4e"))
	enemy_bar = _bar(Rect2(835, 649, 190, 12), Color("ac5c4e"))
	_label(self, "hero", "", Rect2(108, 668, 270, 24), 14).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(self, "enemy_hp", "", Rect2(797, 668, 270, 24), 14).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_scroll = ScrollContainer.new()
	log_scroll.position = Vector2(425, 550)
	log_scroll.size = Vector2(350, 92)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(log_scroll)
	var log_label := _label(log_scroll, "log", "", Rect2(0, 0, 330, 0), 20, PAPER)
	log_label.custom_minimum_size.x = 330
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(self, "notice", "", Rect2(360, 452, 385, 48), 13, JADE)
	_button(self, "sound", "Sound On", Rect2(24, 659, 84, 30)).add_theme_font_size_override("font_size", 16)
	_label(self, "help", "", Rect2(24, 696, 1232, 24), 12, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var teaser := _button(self, "story_teaser", "", Rect2(430, 552, 340, 78))
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	teaser.add_theme_font_size_override("font_size", 16)
	details = PanelContainer.new()
	details.position = Vector2(936, 76)
	details.size = Vector2(310, 250)
	details.mouse_filter = Control.MOUSE_FILTER_STOP
	details.add_theme_stylebox_override("panel", WoodcutSkin.box("detail"))
	add_child(details)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details.add_child(detail_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_scroll.add_child(column)
	for spec in [["item_name", 22, GOLD], ["item_meta", 20, PAPER], ["description", 22, PAPER], ["power", 20, JADE], ["connections", 20, PAPER], ["sources", 20, PAPER], ["item_hint", 20, GOLD]]:
		_label(column, spec[0], "", Rect2(0, 0, 236, 0), spec[1], spec[2])
	synergy_breakdown = SynergyBreakdown.new()
	column.add_child(synergy_breakdown)
	# Keep the resolved effect and its sources above the longer item description.
	column.move_child(labels.power, 1)
	column.move_child(synergy_breakdown, 2)
	synergy_breakdown.hide()
	details.hide()
	guide = GuidePanel.new()
	add_child(guide)
	story = StoryPanel.new()
	add_child(story)
	_button(self, "reward_skip", "Skip Reward", Rect2(974, 414, 272, 32)).hide()
	rewards = RewardPanel.new()
	add_child(rewards)
	routes = RoutePanel.new()
	add_child(routes)
	encounter_event = EventPanel.new()
	add_child(encounter_event)

func _draw() -> void:
	# One original retro-pixel landscape connects the inventory and encounter.
	draw_texture_rect(background_texture, Rect2(0, 0, 1280, 720), false)
	draw_rect(Rect2(0, 0, 1280, 48), Color("111820"))
	draw_line(Vector2(0, 47), Vector2(1280, 47), Color("5b5548"), 2)
	draw_rect(Rect2(0, 696, 1280, 24), Color("111820"))
	# Cloth-wrapped cabinet: ink outlines, muted lacquer, and light hanji inset.
	var cloth := PackedVector2Array([Vector2(321,58),Vector2(916,58),Vector2(949,91),Vector2(938,421),Vector2(910,447),Vector2(323,447),Vector2(290,413),Vector2(299,87)])
	draw_colored_polygon(cloth, Color("191c20"))
	draw_style_box(WoodcutSkin.box("bag"), Rect2(306, 72, 626, 359))
	draw_rect(Rect2(393, 84, 450, 332), Color("302724"))
	draw_rect(Rect2(398, 88, 442, 324), Color("6b5845"))
	for y in range(98, 408, 14):
		draw_rect(Rect2(315, y, 3, 7), Color("d4b18a"))
		draw_rect(Rect2(920, y, 3, 7), Color("d4b18a"))
	for x in [350, 868]:
		draw_rect(Rect2(x, 180, 16, 108), Color("5b3b36"))
		draw_rect(Rect2(x-12, 220, 40, 24), Color("a87f55"))
		draw_rect(Rect2(x-8, 224, 32, 16), Color("684a3b"))
		draw_rect(Rect2(x+4, 216, 8, 32), Color("be9568"))
