extends SceneTree

const Experiment = preload("res://tests/multiplier_experiment_setup.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model := ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	var before := model.items.duplicate(true)
	var snapshot := model.combat_snapshot()
	var result := InventoryRules.synergy_links(snapshot, "sword")
	check(result.error.is_empty() and result.links.size() == 2, "selected weapon has two actual modifiers")
	check(result.links.any(func(link): return link.source == "seal" and link.target == "sword" and link.kind == "add" and link.amount == 2), "flat bonus identifies its source and recipient")
	check(result.links.any(func(link): return link.source == "ring" and link.target == "sword" and link.kind == "multiply" and link.amount == 2), "multiplier identifies its source and recipient")
	check(InventoryRules.synergy_links(snapshot, "ring").links.size() == 1, "selecting source shows its outgoing link")
	check(InventoryRules.synergy_links(snapshot, "not_packed").links.is_empty(), "unpacked or absent object has no links")
	check(model.items == before and model.history.is_empty(), "link projection leaves layout and history untouched")
	# Same nonempty stacking group: only the winning source appears, even when both touch.
	check(model.add_item("second_seal", model.definitions.seal, Vector2i(4,1), 0), "second modifier fits test grid")
	var stacked: Array = InventoryRules.synergy_links(model.combat_snapshot(), "sword").links
	check(stacked.filter(func(link): return link.kind == "add").size() == 1, "stacking group suppresses unused bonus links")
	check(stacked.any(func(link): return link.source == "seal" and link.kind == "add") and not stacked.any(func(link): return link.source == "second_seal"), "link points to deterministic winning source")
	var diagonal := ItemCatalog.create_inventory("res://tests/fixtures/diagonal-experiment.json")
	var corners: Array = InventoryRules.synergy_links(diagonal.combat_snapshot(), "sword").links
	check(corners.any(func(link): return link.source == "seal" and link.kind == "add"), "diagonal contact produces an actual bonus link")
	check(corners.any(func(link): return link.source == "seal" and link.range == "diagonal"), "link records the actual diagonal range")
	check(diagonal.place("seal", Vector2i(1,0), 0), "diagonal source can move away")
	check(not InventoryRules.synergy_links(diagonal.combat_snapshot(), "sword").links.any(func(link): return link.source == "seal"), "nonmatching diagonal does not produce a link")
	_test_conditions()
	await _test_ui()
	print("SYNERGY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_conditions() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	check(model.place("ring", Vector2i(0,0), 0) and model.place("coin", Vector2i(1,1), 0), "two matching items fit around scaled effect")
	var items := model.combat_snapshot()
	items.lantern.effects[0].max_matches = 1
	var plan := EffectApplier.plan(items, "lantern", "turn_end")[0]
	check(plan.matches == ["coin", "ring"] and plan.amount == 4, "same engine records all matches but caps actual count")
	var links: Array = InventoryRules.synergy_links(items, "lantern").links
	var conditions: Array = links.filter(func(link): return link.kind == "condition")
	check(conditions.size() == 2 and conditions.all(func(link): return link.target == "lantern" and link.limit == 1 and link.trigger == "turn_end"), "condition links disclose the shared cap without claiming extra bonus")
	check(conditions.all(func(link): return link.range == "orthogonal"), "condition links retain their authored range")
	check(InventoryRules.synergy_links(items, "ring").links.any(func(link): return link.source == "ring" and link.target == "lantern" and link.kind == "condition"), "condition owner can inspect outgoing dependency")
	var backup := items.duplicate(true)
	InventoryRules.synergy_links(items, "lantern")
	check(items == backup, "link computation is read-only")
	var self_model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	for uid: String in self_model.items.keys():
		if self_model.is_packed(uid): self_model.move_to_stash(uid)
	check(self_model.place("mirror", Vector2i(1,0), 0) and self_model.place("lantern", Vector2i(1,1), 0), "self modifier and condition fit")
	var self_links: Array = InventoryRules.synergy_links(self_model.combat_snapshot(), "mirror").links
	check(self_links.any(func(link): return link.source == "mirror" and link.target == "mirror" and link.kind == "add" and link.amount == 2), "self modifier remains visible")
	check(self_links.any(func(link): return link.source == "lantern" and link.target == "mirror" and link.kind == "condition"), "condition for self modifier remains visible")

func _test_ui() -> void:
	root.size = Vector2i(1280,720)
	var main := Experiment.create(root)
	await process_frame
	var selected_cells: Array = [Vector2i(3,0), Vector2i(3,1), Vector2i(3,2)]
	var source_cells: Array = [Vector2i(2,1)]
	var pair: Array[Vector2i] = main.board._closest_cells(source_cells, selected_cells, "diagonal")
	check(pair.size() == 2 and absi(pair[0].x - pair[1].x) == 1 and absi(pair[0].y - pair[1].y) == 1, "diagonal drawing uses a diagonal contact even when orthogonal contact is closer")
	main._select("sword")
	check(main.board.synergy_view().mode == "current" and main.labels.synergy_state.text.contains("현재 연결"), "selection shows current connections")
	check(main.labels.connections.text.contains("봉인부 → 낡은 사인검") and main.labels.connections.text.contains("×2") and main.labels.connections.text.contains("상하좌우"), "details identify sources, target, range and multiplier")
	main._select("ring")
	check(main.board.synergy_view().links.any(func(link): return link.kind == "multiply"), "modifier selection shows outgoing effect")
	var saved: Dictionary = main.session.display_snapshot()
	main.board.hover_cell = Vector2i(0,0)
	main.board.synergy_changed.emit()
	var candidate: Dictionary = main.board.synergy_view()
	check(candidate.mode == "preview" and not candidate.links.any(func(link): return link.kind == "multiply"), "valid preview removes the multiplier")
	check(candidate.links.any(func(link): return link.kind == "condition") and main.labels.connections.text.contains("배치 예상"), "preview shows the new conditional relationship")
	check(main.labels.synergy_state.text.contains("점선") and main.labels.item_meta.text.contains("배치 예상"), "preview is labelled in both board and details")
	check(main.session.display_snapshot() == saved, "hover preview leaves displayed state untouched")
	main._place("ring", Vector2i(0,0), 0)
	check(main.board.synergy_view().mode == "current" and main.inventory.items.ring.origin == Vector2i(0,0), "successful placement updates current links")
	main.board.dragging = true
	main.board.hover_cell = Vector2i(3,0)
	main.board.grab_offset = Vector2i.ZERO
	main.board.synergy_changed.emit()
	check(main.board.synergy_view().mode == "invalid" and main.board.synergy_view().links.is_empty() and main.labels.synergy_state.text.contains("배치 불가"), "invalid placement never shows predicted links")
	main.board.hover_cell = Vector2i(-1, 0)
	main.board.synergy_changed.emit()
	check(main.board.synergy_view().mode == "invalid" and main.board.synergy_view().links.is_empty(), "dragging outside the grid cannot show current links as a prediction")
	main._cancel()
	check(main.board.synergy_view().mode == "empty" and main.labels.synergy_state.text.is_empty(), "cancel clears links")
	main._select("sword")
	main._primary_action()
	check(main.session.is_busy() and main.board.synergy_view().mode == "busy" and main.labels.synergy_state.text.is_empty(), "playback hides projections")
	main.session.skip_playback()
	check(main.board.synergy_view().mode == "current", "skip restores links for displayed settled state")
	main._reset_run()
	check(main.board.synergy_view().mode == "empty", "restart clears previous selection and links")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		check(Rect2(Vector2.ZERO, main.size).encloses(main.labels.synergy_state.get_global_rect()), "legend fits resized window")
	main.queue_free()
	await process_frame
