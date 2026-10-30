extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _icons(node: Node) -> Array[ItemData]:
	var result: Array[ItemData] = []
	if node is SynergyBreakdown.MiniIcon:
		result.append(node.item)
		check(node.tooltip_text == node.item.display_name and node.accessibility_name == node.item.display_name, "source icon retains its name for tooltip and accessibility")
	for child in node.get_children(): result.append_array(_icons(child))
	return result

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	check(main.session.stash("hat").is_empty() and main.session.place("seal", Vector2i(2, 1), 0).is_empty(), "test layout places two different sources")
	main._select("sword")
	await process_frame
	await process_frame
	var panel: SynergyBreakdown = main.layout.synergy_breakdown
	check(panel.visible and panel.rows.size() == 1, "modified attack has one visible breakdown")
	if panel.rows.size() == 1:
		var row: Dictionary = panel.rows[0]
		check(row.base == 6 and row.amount == 16 and row.bonuses.size() == 1 and row.bonuses[0].source == "seal" and row.bonuses[0].amount == 2 and row.multipliers.size() == 1 and row.multipliers[0].source == "ring" and row.multipliers[0].factor == 2, "icon breakdown preserves the exact planned source order and result")
	var icons := _icons(panel)
	check(icons.size() == 2 and icons[0] == main.display_inventory.definition("seal") and icons[1] == main.display_inventory.definition("ring"), "mini icons identify the actual contributing items")
	check(not main.labels.power.text.contains("Calculation:") and main.labels.power.text.contains("Attack 16"), "effect summary remains readable without a raw formula")
	check(panel.get_global_rect().position.y >= main.labels.power.get_global_rect().end.y and panel.get_global_rect().end.y <= main.layout.detail_scroll.get_global_rect().end.y, "initial breakdown is visible below the result")
	var before: Dictionary = main.session.display_snapshot()
	main.board.hover_cell = Vector2i(1, 0)
	main.board.synergy_changed.emit()
	await process_frame
	check(main.board.synergy_view().mode == "preview" and main.session.display_snapshot() == before, "preview uses only a temporary layout")
	check(panel.rows.size() == 1 and panel.rows[0].amount == 8 and panel.rows[0].multipliers.is_empty() and panel.rows[0].bonuses[0].source == "seal", "preview removes the multiplier and updates the icon breakdown")
	check(_icons(panel).size() == 1 and main.labels.item_meta.text.contains("Placement Preview"), "preview shows only the applicable source")
	var planned: Dictionary = EffectApplier.plan(main.board.synergy_view().items, "sword", "use")[0]
	panel.refresh([{"trigger":"use", "plan":planned}, {"trigger":"turn_end", "plan":{"error":"Calculation failed"}}], {})
	check(panel.rows.is_empty() and not panel.visible, "a failed effect suppresses partial source breakdowns")
	main._cancel()
	check(not main.layout.details.visible, "cancelling closes the selected item details")
	main.queue_free()
	await process_frame
	print("SYNERGY PRESENTATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
