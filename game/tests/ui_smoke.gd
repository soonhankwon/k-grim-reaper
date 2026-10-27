extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func drain(session: BattleSession) -> void:
	for frame in 100:
		if not session.is_busy(): return
		await process_frame
	verify(false, "UI playback must finish within frame budget")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	main.content_path = "res://tests/fixtures/baseline.json"
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	await process_frame
	main.session.playback.seconds_per_step = 0.0
	verify(main.inventory.items.size() == 12, "UI loads catalog")
	# Feed engine events, not the OS pointer, to verify drag/drop deterministically.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = InventoryBoard.PAD + Vector2(1.5,0.5) * InventoryBoard.CELL
	main.board._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = main.board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(2.5,1.5) * InventoryBoard.CELL)
	main.board._input(motion)
	verify(main.board.dragging, "drag threshold uses event positions")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	main.board._input(release)
	verify(main.inventory.items.seal.origin == Vector2i(2,1), "drag release commits destination")
	main._reset_run()
	main._select("seal")
	main._preview(Vector2i(2,1))
	verify("6 → 8" in main.labels.notice.text, "moving a passive talisman previews affected sword")
	main._place("seal", Vector2i(2,1), 0)
	verify(main.inventory.action_result("sword").power == 8, "UI placement changes damage")
	main._select("ring")
	main._place("ring", Vector2i(0,0), 0)
	verify(main.inventory.passive_guard() == 4, "UI placement changes passive guard")
	main._select("rope")
	main._rotate()
	main._cancel()
	verify(main.inventory.items.rope.rotation == 0 and not main.inventory.is_packed("rope"), "cancelled rotation does not mutate resource or stash")
	main._primary_action()
	verify(main.primary.disabled, "primary action is locked immediately on submission")
	await drain(main.session)
	main._select("sword")
	verify(main.rotate_button.disabled and not main.layout.preparation.visible, "battle locks and hides rearrangement")
	press.position = InventoryBoard.PAD + Vector2(3.5,0.5) * InventoryBoard.CELL
	main.board._gui_input(press)
	verify(main.session.state_snapshot().enemy_health == 10 and main.primary.disabled, "simulation commits while actions are locked")
	verify(main.enemy_bar.value == 18, "health bar stays on presented snapshot until impact")
	main._activate_item("sword")
	verify(main.session.state_snapshot().enemy_health == 10, "rapid repeat click during playback cannot act twice")
	await drain(main.session)
	verify(main.enemy_bar.value == 10, "impact playback updates health bar")
	main._reset_run()
	main._select("yakgwa")
	main._place("yakgwa", Vector2i(4,1), 0)
	main._primary_action()
	await drain(main.session)
	main._activate_item("yakgwa")
	verify(not main.inventory.items.has("yakgwa") and main.board.model.items.has("yakgwa"), "consumed item stays visible until its playback step")
	await drain(main.session)
	verify(not main.board.model.items.has("yakgwa") and main.selected.is_empty(), "consumption step updates board and selection together")
	main._reset_run()
	# Stash to board is the same placement transaction, with viewport coordinates.
	var slot: Control = main.stash_grid.get_child(0)
	var stashed_uid: String = slot.item.id
	press.position = Vector2(20,20)
	main._stash_input(press, stashed_uid, slot)
	motion.position = main.board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(4.5,1.5) * InventoryBoard.CELL)
	main.board._input(motion)
	release.position = motion.position
	main.board._input(release)
	verify(main.inventory.is_packed(stashed_uid), "stash drag places an item directly")
	main._cancel()
	main._inspect("order")
	verify(main.layout.details.visible and main.labels.item_name.text == main.inventory.definition("order").display_name, "hover reveals item details")
	main._inspect("")
	verify(not main.layout.details.visible, "hover exit closes details")
	main._reset_run()
	for uid: String in main.inventory.items.keys():
		main.inventory.move_to_stash(uid)
	await process_frame
	await process_frame
	verify(main.stash_grid.get_child_count() == 12, "scrollable stash retains all twelve items")
	main._select("order")
	await process_frame
	await process_frame
	var boundary := Rect2(Vector2.ZERO, main.size)
	for key in main.labels:
		var label: Label = main.labels[key]
		verify(boundary.encloses(label.get_global_rect()), "label stays in viewport: " + str(key) + " " + str(label.get_global_rect()))
	verify(boundary.encloses(main.primary.get_global_rect()), "battle action stays on screen")
	verify(boundary.encloses(main.skip_button.get_global_rect()), "skip control stays on screen")
	verify(boundary.encloses(main.undo_button.get_global_rect()), "layout controls stay on screen")
	# Every card must leave the primary action accessible, including the longest text.
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		for uid: String in main.inventory.items:
			main._inspect(uid)
			await process_frame
			await process_frame
			boundary = Rect2(Vector2.ZERO, main.size)
			verify(boundary.encloses(main.layout.details.get_global_rect()), "details stay inside viewport at " + str(window_size))
			verify(not main.layout.details.get_global_rect().intersects(main.primary.get_global_rect()), "details never cover turn button: " + uid)
		verify(main.hero_bar.get_global_rect().end.y <= main.labels.hero.get_global_rect().position.y, "health label stays below bar")
		verify(boundary.encloses(main.labels.help.get_global_rect()), "footer fits after resize")
	root.size = Vector2i(1024,576)
	await process_frame
	await process_frame
	main._reset_run()
	press.position = InventoryBoard.PAD + Vector2(1.5,0.5) * InventoryBoard.CELL
	main.board._gui_input(press)
	motion.position = main.board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(2.5,1.5) * InventoryBoard.CELL)
	main.board._input(motion)
	release.position = motion.position
	main.board._input(release)
	verify(main.inventory.items.seal.origin == Vector2i(2,1), "drag coordinates survive minimum window scaling")
	main._select("seal")
	main.labels.power.text = "복합 효과 · 공격 3 · 방어 2 · 회복 1\n".repeat(20)
	await process_frame
	await process_frame
	verify(not main.layout.details.get_global_rect().intersects(main.primary.get_global_rect()), "long composed effects stay in a scroll card")
	verify(main.layout.detail_scroll.get_v_scroll_bar().max_value > main.layout.detail_scroll.size.y, "long effects remain accessible by scrolling")
	main._reset_run()
	print("UI SMOKE: ", "FAIL" if failed else "PASS")
	main.queue_free()
	await process_frame
	quit(1 if failed else 0)
