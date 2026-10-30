extends Control
## Experiment-specific presentation reads only the session's display snapshot.

const Rules = preload("res://tests/yagwang_rules.gd")

var main: Control
var settings: Dictionary
var status: Label
var panel: PanelContainer
var banner: Label
var thread: Line2D
var thread_animating := false
var thread_alpha := 1.0

func setup(target: Control, data: Dictionary) -> void:
	main = target
	settings = data.duplicate(true)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = Label.new()
	banner.text = ""
	banner.hide()
	banner.add_theme_color_override("font_color", Color("e9997b"))
	add_child(banner)
	panel = PanelContainer.new()
	panel.name = "YagwangPanel"
	panel.position = Vector2(320, 408)
	panel.size = Vector2(425, 54)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b2328")
	style.border_color = Color("b98164")
	style.set_border_width_all(1)
	style.set_content_margin_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	status = Label.new()
	status.name = "YagwangStatus"
	status.custom_minimum_size.x = 405
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color("ffe0c5"))
	scroll.add_child(status)
	thread = Line2D.new()
	thread.name = "TargetThread"
	thread.width = 2.0
	thread.default_color = Color("c7493d")
	thread.antialiased = false
	main.layout.add_child(thread)
	main.layout.move_child(thread, main.road.get_index() + 1)
	main.session.presented.connect(refresh)
	main.board.hovered.connect(item_details)
	main.board.picked.connect(item_details)
	main.board.synergy_changed.connect(_on_layout_preview)
	refresh()

func refresh() -> void:
	var view: Dictionary = main.session.display_snapshot()
	if view.is_empty(): return
	main.labels.chapter.text = "New Year's Eve · Stage 2 Preview" + (" · Turn %d" % view.turn if view.phase == "battle" else "")
	main.labels.edition.text = "Preview · Unsaved"
	main.layout.buttons.story.disabled = true
	main.layout.buttons.story_teaser.hide()
	panel.visible = view.phase in ["packing", "battle"]
	if panel.visible:
		main.labels.notice.position.y = 464
		main.labels.notice.size.y = 44
	var telegraph := _telegraph(view)
	_update_thread(view)
	if view.phase == "packing":
		var label := "Preview" if telegraph.preview else "Current"
		status.text = "%s target: %s\nBottom-row footwear is targeted first." % [label, telegraph.name]
		main.layout.guide.heading.text = "Prepare for Yagwanggwi"
		main.layout.guide.body.text = "Hide footwear above the bottom row. The lowest other item becomes the target. Try placing the 2×2 sieve."
		main.layout.guide.footer.text = "Sieve: once per battle · cancels one action and search\nDawn after %d turns" % settings.dawn_turn
		main.labels.help.text = "Bottom-row footwear is targeted first · ! marks the target"
	elif view.phase == "battle":
		var puzzle: Dictionary = view.get("puzzle", {})
		if puzzle.is_empty(): return
		var until_dawn := maxi(0, int(settings.dawn_turn) - int(view.turn) + 1)
		var uid: String = puzzle.target
		var name := str(view.packed_items[uid].name) if view.packed_items.has(uid) else ("none" if puzzle.stolen.is_empty() else "stolen")
		var theft := ("none" if uid.is_empty() else str(puzzle.remaining) + " actions") if puzzle.stolen.is_empty() else "done"
		status.text = "Target: %s · Theft: %s\nTurns until dawn: %d" % [name, theft, until_dawn]
		if int(puzzle.stun) > 0:
			main.labels.intent.text = "Next · Counting (cancelled)"
			main.layout.intent_icon.set_operation("counting")
		main.layout.guide.heading.text = "Protect Your Shoes"
		main.layout.guide.body.text = "The marked item is stolen after the shown number of enemy actions. Use the sieve to delay the next action and search."
		main.layout.guide.footer.text = "Theft: −%d energy this battle\nSurvive until dawn to win" % settings.energy_penalty
		main.labels.help.text = "Sieve: once per battle · Delay the enemy · Survive until dawn"
	elif view.phase == "victory":
		main.layout.guide.heading.text = "Yagwanggwi Flees"
		main.layout.guide.body.text = "The stolen item returns to its original place."
		main.layout.guide.footer.text = "Try another layout."
	item_details(main.inspected)

func begin_thread_feedback(event: Dictionary) -> bool:
	if event.get("kind", "") != "target_marked": return false
	thread_animating = true
	thread_alpha = 0.0
	_update_thread(main.session.display_snapshot())
	return true

func set_thread_progress(value: float) -> void:
	thread_alpha = clampf((value - 0.5) * 2.0, 0.0, 1.0)
	_update_thread(main.session.display_snapshot())

func clear_thread_feedback() -> void:
	thread_animating = false
	thread_alpha = 1.0
	if main.session != null: _update_thread(main.session.display_snapshot())

func _update_thread(view: Dictionary) -> void:
	if thread == null: return
	var puzzle: Dictionary = view.get("puzzle", {})
	if view.get("phase", "") != "battle" or puzzle.is_empty() or not puzzle.stolen.is_empty() or main.board.target_cells.is_empty():
		thread.hide()
		return
	var from := Vector2(925, 532)
	var cell: Vector2i = main.board.target_cells[0]
	var to: Vector2 = main.board.position + InventoryBoard.PAD + (Vector2(cell) + Vector2(0.5, 0.5)) * main.board.cell_size
	var control := (from + to) / 2 + Vector2(-95, -75)
	var points := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		points.append((1.0-t)*(1.0-t)*from + 2.0*(1.0-t)*t*control + t*t*to)
	thread.points = points
	thread.modulate = Color(1, 1, 1, thread_alpha)
	thread.show()

func _on_layout_preview() -> void:
	if main.session == null: return
	var view: Dictionary = main.session.display_snapshot()
	if view.get("phase", "") == "packing" and not main.session.is_busy():
		var info := _telegraph(view)
		status.text = "%s target: %s\nBottom-row footwear is targeted first." % ["Preview" if info.preview else "Current", info.name]
	item_details(main.inspected)

func _telegraph(view: Dictionary) -> Dictionary:
	var board: InventoryBoard = main.board
	board.threat_cells.clear()
	board.target_cells.clear()
	board.target_preview = false
	var shown_items: Dictionary = view.packed_items
	var uid := ""
	if view.phase in ["packing", "battle"]:
		var first_row: int = int(view.config.grid_height) - int(settings.exposed_rows)
		for y in range(first_row, int(view.config.grid_height)):
			for x in int(view.config.grid_width): board.threat_cells.append(Vector2i(x, y))
		if view.phase == "packing":
			var preview := board.synergy_view()
			if preview.mode == "preview":
				shown_items = preview.items
				board.target_preview = true
			var value := view.duplicate(true)
			value.packed_items = shown_items
			uid = Rules.new(settings).target(value)
		else:
			var puzzle: Dictionary = view.get("puzzle", {})
			if not puzzle.is_empty() and puzzle.stolen.is_empty(): uid = str(puzzle.target)
		if shown_items.has(uid):
			for cell: Vector2i in shown_items[uid].cells: board.target_cells.append(cell)
	board.queue_redraw()
	return {"preview":board.target_preview, "name":str(shown_items[uid].name) if shown_items.has(uid) else "none"}

func item_details(uid: String) -> void:
	if main.display_inventory == null or not main.display_inventory.items.has(uid): return
	var view: Dictionary = main.session.display_snapshot()
	var item: ItemData = main.display_inventory.definition(uid)
	if settings.lure_tag not in item.tags: return
	main.labels.power.text = "Use: cancel the next enemy action and search\nOnce per battle · Energy %d" % item.cost
	if view.phase == "battle":
		var error: String = main.session.use_error(uid)
		main.labels.item_hint.text = "Click to use" if error.is_empty() else error
