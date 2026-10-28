extends SceneTree

const Experiment = preload("res://tests/space_experiment_setup.gd")
const TEST_ID := "test_greatsword"
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
	_test_content_and_placement()
	await _test_alternative_builds()
	await _test_ui()
	print("SPACE EXPERIMENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_content_and_placement() -> void:
	var shipping := ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH)
	var fixture := ContentLoader.new().load_json(Experiment.CONTENT_PATH)
	check(shipping.error.is_empty() and fixture.error.is_empty(), "shipping and experimental data validate")
	if not fixture.error.is_empty() or not shipping.error.is_empty(): return
	var original: Dictionary = fixture.raw.duplicate(true)
	for table in ["items", "loadout"]:
		original[table] = original[table].filter(func(row): return row.id != TEST_ID)
	original.effects = original.effects.filter(func(row): return row.id != "test_greatsword_hit")
	check(original == shipping.raw, "experiment only adds its test item, effect and loadout instance")
	check(shipping.raw.items.size() == 12 and shipping.raw.encounters.size() == 3 and fixture.raw.items.size() == 13, "test item does not change release counts")
	var model := ItemCatalog.from_validated(fixture.raw)
	check(model.items.size() == 8 and not model.is_packed(TEST_ID), "experimental weapon starts separately in the stash")
	var definition := model.definition(TEST_ID)
	check(definition.footprint.size() == 4 and definition.cost == 2 and definition.effects[0].amount == 13, "fixture supplies the four-cell, two-energy, 13-power item")
	for rotation in 4:
		var cells := GridRules.cells(definition.footprint, rotation)
		var bounds := Vector2i.ZERO
		for cell in cells: bounds = bounds.max(cell + Vector2i.ONE)
		check(cells.size() == 4 and bounds in [Vector2i(1,4), Vector2i(4,1)], "four-cell shape rotates without loss")
	check(GridRules.cells(definition.footprint, 4) == GridRules.cells(definition.footprint, 0), "four turns restore original shape")
	var before := model.items.duplicate(true)
	var legal := 0
	for rotation in 4:
		for y in model.dimensions.y:
			for x in model.dimensions.x:
				if model.placement_error(TEST_ID, Vector2i(x,y), rotation).is_empty(): legal += 1
	check(legal == 0 and model.items == before, "initial layout has no legal greatsword placement in any direction")
	check(not model.place(TEST_ID, Vector2i(3,0), 0) and model.items == before, "overlap never moves the original weapon")

func _test_alternative_builds() -> void:
	# First approach: replace the short sword, preserving the bell.
	var session := BattleSession.new()
	root.add_child(session)
	var model := ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	session.reset(model)
	check(session.stash("sword").is_empty() and session.place(TEST_ID, Vector2i(3,0), 0).is_empty(), "long weapon fits after removing the original sword")
	check(not model.is_packed("sword") and model.is_packed("bell") and model.used_cells() == 13, "replacement trades the original weapon for four cells")
	var preview := model.action_result(TEST_ID)
	check(preview.power == 13 and preview.effects[0].kind == "damage", "first layout previews the authored damage")
	check(session.submit({"type":"start"}).is_empty(), "first layout starts a normal battle")
	session.skip_playback()
	var before := session.display_snapshot()
	check(session.submit({"type":"use_item", "uid":TEST_ID}).is_empty(), "test weapon uses the normal session command")
	check(session.display_snapshot().enemy_health == before.enemy_health and session.state_snapshot().enemy_health == 5, "damage does not leak before presentation")
	session.skip_playback()
	check(session.display_snapshot().enemy_health == 5 and session.display_snapshot().energy == 1, "13 previewed damage and two energy match the committed result")
	# Second approach: keep the short sword and ring by moving two objects.
	model = ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	session.reset(model)
	check(session.stash("bell").is_empty() and session.place("ring", Vector2i(2,1), 0).is_empty(), "second layout moves the bell and ring")
	check(session.place("seal", Vector2i(2,0), 0).is_empty() and session.place(TEST_ID, Vector2i(4,0), 0).is_empty(), "second layout fits both weapons and a repositioned modifier")
	check(model.is_packed("sword") and model.is_packed(TEST_ID) and not model.is_packed("bell"), "second layout trades a different existing item")
	check(model.action_result("sword").power == 8 and model.action_result(TEST_ID).power == 13, "preview shows the modifier belongs to the neighboring weapon")
	check(session.submit({"type":"start"}).is_empty(), "second layout starts")
	session.skip_playback()
	check(session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "short weapon fires")
	session.skip_playback()
	check(session.display_snapshot().enemy_health == 10 and session.display_snapshot().energy == 2, "first strike uses the displayed adjacency result")
	check(session.submit({"type":"use_item", "uid":TEST_ID}).is_empty(), "long weapon follows within the remaining energy")
	session.skip_playback()
	check(session.display_snapshot().enemy_health == 0 and session.display_snapshot().phase == "reward" and session.display_snapshot().energy == 0, "second layout wins using both weapons")
	session.queue_free()
	await process_frame

func _test_ui() -> void:
	root.size = Vector2i(1280,720)
	var main := Experiment.create(root)
	await process_frame
	check(not main.save_enabled and main.session.save_service == null, "experiment has no save service")
	check(main.inventory != null and main.inventory.items.has(TEST_ID), "launcher shows the isolated test fixture")
	var banner: Label = main.layout.get_node("ExperimentBanner")
	check(banner.text.contains("저장 안 함"), "window clearly identifies the no-save experiment")
	var initial: Dictionary = main.session.display_snapshot().inventory_items.duplicate(true)
	main._select("sword")
	main._stash_selected()
	var slot: StashSlot = null
	for child: Node in main.stash_grid.get_children():
		if child is StashSlot and child.item.id == TEST_ID: slot = child
	check(slot != null, "test weapon appears in the stash")
	if slot != null:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(20,20)
		slot.gui_input.emit(press)
		var motion := InputEventMouseMotion.new()
		motion.position = main.board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(3.5,0.5) * main.board.cell_size)
		main.board._input(motion)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = motion.position
		main.board._input(release)
		check(main.inventory.is_packed(TEST_ID) and main.inventory.items[TEST_ID].origin == Vector2i(3,0), "stash drag places the long weapon at the released grid cell")
		check(main.labels.power.text.contains("공격 13"), "item detail shows the actual test damage")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var boundary := Rect2(Vector2.ZERO, main.size)
		check(boundary.encloses(banner.get_global_rect()), "experiment banner fits the window")
		check(not banner.get_global_rect().intersects(main.labels.chapter.get_global_rect()), "banner does not cover the chapter")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/space-experiment-screen.png"))
	main._reset_run()
	check(main.session.display_snapshot().inventory_items == initial and not main.inventory.is_packed(TEST_ID), "restart returns to the same test layout")
	check(main.session.save_service == null, "restart never creates a user save")
	main.queue_free()
	await process_frame
