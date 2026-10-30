class_name RewardPanel
extends PanelContainer
## Choice rendering only. Requests go back through Main -> BattleSession.

signal chosen(item_id: String)
signal inspected(item_id: String)
var choices: Array[RewardChoice] = []
var _key := ""
var _row: HBoxContainer
var _heading: Label

func _ready() -> void:
	position = Vector2(24, 466)
	size = Vector2(1232, 220)
	add_theme_stylebox_override("panel", WoodcutSkin.box("panel"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 20)
	_heading.add_theme_color_override("font_color", Color("e0bb74"))
	column.add_child(_heading)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	column.add_child(_row)
	hide()

func refresh(view: Dictionary, definitions: Dictionary, busy: bool) -> void:
	visible = view.phase == "reward"
	if not visible:
		_key = ""
		return
	var reward: Dictionary = view.reward
	var key := str(reward.offer_id) + ":" + "|".join(reward.candidates)
	if key != _key:
		_key = key
		for child in _row.get_children():
			_row.remove_child(child)
			child.queue_free()
		choices.clear()
		for id: String in reward.candidates:
			var card := RewardChoice.new()
			card.item = definitions[id]
			card.pressed.connect(func(): chosen.emit(id))
			card.mouse_entered.connect(func(): inspected.emit(id))
			card.mouse_exited.connect(func(): inspected.emit(""))
			card.focus_entered.connect(func(): inspected.emit(id))
			_row.add_child(card)
			choices.append(card)
	_heading.text = "Reward · Choose one of %d · Place it in your bag, then confirm" % reward.candidates.size()
	for card in choices:
		card.disabled = busy
		card.chosen = str(card.item.id) == reward.selected
		card.queue_redraw()
