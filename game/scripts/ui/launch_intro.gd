class_name LaunchIntro
extends Control
## Read-only front-end. Starting or continuing a run is owned by the caller.

signal accepted
signal cancelled

const FONT = preload("res://assets/fonts/NotoSansKR.ttf")
var heading := "REAPER'S BUNDLE"
var chapter := "FIRST DELIVERY · MIRYANG"
var description := "Three magistrates died on their first night in Miryang.\nBefore dawn, find the spirit haunting the fourth."
var instructions := "Arrange your bag before battle.\nClick an item to use it; read the enemy's next move.\nFollow the clues and decide how to face the spirit."
var note := "Your journey begins with a bag of belongings."
var action_text := "Begin Delivery"
var cancel_text := ""
var action_button: WoodenButton
var cancel_button: Button
var note_label: Label
var _canvas: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var readable_font := FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {0x77676874: 600} # OpenType wght axis
	theme = Theme.new()
	theme.default_font = readable_font
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("ecdfbf"))
	theme.set_color("font_color", "Button", Color("ecdfbf"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var kind: String = {"normal":"button", "hover":"hover", "pressed":"pressed", "disabled":"disabled"}[state]
		theme.set_stylebox(state, "Button", WoodcutSkin.box(kind))
	_canvas = Control.new()
	_canvas.size = Vector2(1280, 720)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var background := TextureRect.new()
	background.texture = PresentationArt.background_for_actor("spirit_1")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.size = _canvas.size
	background.modulate = Color("59616a")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(background)
	var panel := PanelContainer.new()
	panel.position = Vector2(184, 54)
	panel.size = Vector2(912, 612)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", WoodcutSkin.box("panel"))
	_canvas.add_child(panel)
	_label(chapter, Rect2(240, 92, 800, 30), 18, Color("a6cbb3"), true)
	_label(heading, Rect2(240, 132, 800, 64), 40, Color("e0bb74"), true)
	_label(description, Rect2(250, 216, 780, 122), 24, Color("ecdfbf"), true)
	_label(instructions, Rect2(250, 350, 780, 120), 22, Color("e0d9c8"), true)
	note_label = _label(note, Rect2(250, 484, 780, 42), 20, Color("b9dfca"), true)
	action_button = WoodenButton.new()
	action_button.text = action_text
	action_button.position = Vector2(430, 542)
	action_button.size = Vector2(420, 50)
	action_button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed"]:
		var kind: String = {"normal":"primary", "hover":"primary_hover", "pressed":"primary_pressed"}[state]
		action_button.add_theme_stylebox_override(state, WoodcutSkin.box(kind))
	_canvas.add_child(action_button)
	action_button.pressed.connect(func(): accepted.emit())
	if not cancel_text.is_empty():
		cancel_button = Button.new()
		cancel_button.text = cancel_text
		cancel_button.position = Vector2(500, 604)
		cancel_button.size = Vector2(280, 36)
		cancel_button.add_theme_font_size_override("font_size", 16)
		_canvas.add_child(cancel_button)
		cancel_button.pressed.connect(func(): cancelled.emit())
	resized.connect(_fit)
	_fit()
	action_button.grab_focus()

func _fit() -> void:
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - _canvas.size * factor) / 2

func _label(text: String, rect: Rect2, font_size: int, color: Color, centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if centered: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(label)
	return label
