class_name GuidePanel
extends PanelContainer
## Contextual instructions use only the currently presented snapshot.

var heading: Label
var body: Label
var footer: Label

func _ready() -> void:
	position = Vector2(936, 76)
	size = Vector2(310, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", WoodcutSkin.box("detail"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(column)
	heading = _label(20, Color("e0bb74"))
	body = _label(20, Color("ecdfbf"))
	footer = _label(18, Color("b9dfca"))
	column.add_child(heading)
	column.add_child(body)
	column.add_child(footer)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", maxi(16, ceili(font_size / 2.0) * 2))
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func refresh(view: Dictionary, busy: bool, blocked: bool) -> void:
	if blocked:
		heading.text = "Save Error"
		body.text = "Progress is locked. Review the save-file message."
		footer.text = "Existing saves are never overwritten automatically."
		return
	match view.phase:
		"packing":
			heading.text = "Prepare Your Bag"
			body.text = "Drag an item into your bag, or select it and click a cell.\n\nCheck each item's range."
			footer.text = "R: rotate · Ctrl+Z: undo\nHover to inspect effects"
			var hazards := InventoryRules.active_hazards(view)
			if not hazards.is_empty():
				var targets: PackedStringArray = []
				for tag: String in hazards[0].required_tags: targets.append(str(view.config.tag_labels.get(tag, tag)))
				body.text = "%s · %s costs +%d energy\n\n%s" % [hazards[0].label, "/".join(targets), hazards[0].cost_increase, hazards[0].description]
				footer.text = "Check blue cells · R: rotate · Ctrl+Z: undo"
		"battle":
			heading.text = "In Battle"
			body.text = "Click items to use them. Check energy and uses.\n\nReview the enemy's next move before ending your turn."
			footer.text = "You can rearrange your bag after battle."
			if not EventRules.resolution(view).is_empty() and view.get("event", {}).get("status", "") in ["carried", "left"]:
				footer.text = "If the evidence is in your bag, use the button on the right to listen."
		"reward":
			heading.text = "Reward and Preparation"
			if view.reward.selected.is_empty():
				body.text = "Choose a reward below; it goes to storage.\n\nPlace it in your bag, then confirm."
			else:
				body.text = "Place the chosen reward in your bag, then confirm.\n\nMove other items to storage if you need room."
			footer.text = "Switch rewards or skip before confirming."
		"victory":
			heading.text = "The Way Is Clear"
			body.text = "You can rearrange items before the next encounter.\n\nWhen ready, press the button on the right."
			footer.text = "Items in your bag can be used in the next battle."
		"event":
			heading.text = "A Choice on the Road"
			body.text = "You can keep the evidence in storage or leave it behind." if EventRules.resolution(view).get("allow_stash", false) else "Place the evidence in your bag to keep it, or leave it behind."
			footer.text = "The evidence must be in your bag to show it at the next encounter."
		"event_result":
			heading.text = "The Outcome"
			body.text = "Review your choice and finish the event."
			footer.text = "Finishing this event ends the delivery." if not EventRules.resolution(view).is_empty() else "Collect your reward and continue."
		"route":
			heading.text = "Crossroads"
			body.text = "Compare the next enemy and first action on each path.\n\nChoose a path to continue."
			footer.text = "Your choice is saved when confirmed."
		"defeat":
			heading.text = "Prepare Again"
			body.text = "This delivery ends here. Try a different layout and defense."
			footer.text = "Use the button on the right to start again."
		"complete":
			heading.text = "Chapter 1 Complete"
			body.text = "Your first delivery is complete. The next chapter is still in development."
			footer.text = "Restart to try another layout or path."
	if busy: footer.text = "Playing the result. You can skip the animation."
