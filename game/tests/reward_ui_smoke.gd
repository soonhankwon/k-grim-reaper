extends SceneTree

var failed := false

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = "res://tests/fixtures/baseline.json"
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	main.inventory.config.reward_offers = {"gate_1": {"id":"ui_offer", "item_ids":["coin", "mirror", "rope"]}}
	var state := CombatSimulator.initial_state(main.inventory.config)
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main._activate_item("sword")
	verify(not main.layout.rewards.visible, "reward UI stays hidden before victory playback")
	main.session.skip_playback()
	await process_frame
	verify(main.layout.rewards.visible and main.layout.rewards.choices.size() == 3 and main.primary.disabled, "victory displays three choices and gates confirmation")
	var uid: String = main.session.display_snapshot().reward.uid
	var card: RewardChoice = main.layout.rewards.choices[0]
	card.mouse_entered.emit()
	verify(main.layout.details.visible and main.labels.item_name.text == main.inventory.definitions.coin.display_name, "candidate can be inspected before selection")
	card.pressed.emit()
	verify(not main.board.model.items.has(uid) and main.primary.disabled, "candidate selection waits for display event")
	main.session.skip_playback()
	await process_frame
	verify(main.selected == uid and not main.inventory.is_packed(uid) and main.primary.disabled, "candidate becomes selected stash item")
	var slot: StashSlot = main.stash_grid.get_child(main.stash_grid.get_child_count() - 1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(20,20)
	slot.gui_input.emit(press)
	var motion := InputEventMouseMotion.new()
	motion.position = main.board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(4.5,1.5) * InventoryBoard.CELL)
	main.board._input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	main.board._input(release)
	verify(main.inventory.is_packed(uid) and not main.primary.disabled, "reward stash drag uses its instance ID and enables confirm")
	main._cancel()
	card.pressed.emit()
	verify(main.selected == uid and main.inventory.is_packed(uid) and not main.session.is_busy(), "same candidate reselects its placed instance after cancel without a new transaction")
	main._undo()
	verify(not main.inventory.is_packed(uid) and main.primary.disabled, "undo updates confirmation eligibility")
	main._place(uid, Vector2i(4,1), 0)
	main.layout.rewards.choices[1].pressed.emit()
	main.session.skip_playback()
	verify(main.inventory.items[uid].definition == "mirror" and not main.inventory.is_packed(uid) and main.primary.disabled, "second card replaces only tentative item")
	main.layout.rewards.choices[0].pressed.emit()
	main.session.skip_playback()
	main._place(uid, Vector2i(4,1), 0)
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var boundary := Rect2(Vector2.ZERO, main.size)
		verify(boundary.encloses(main.layout.rewards.get_global_rect()), "reward panel fits " + str(window_size))
		for choice: RewardChoice in main.layout.rewards.choices:
			verify(main.layout.rewards.get_global_rect().encloses(choice.get_global_rect()), "choice fits panel at " + str(window_size))
			verify(not choice.get_global_rect().intersects(main.primary.get_global_rect()), "reward choice does not cover confirm")
		verify(boundary.encloses(main.layout.buttons.reward_skip.get_global_rect()), "skip reward stays on screen")
		main._inspect_reward("rope")
		verify(not main.layout.details.get_global_rect().intersects(main.layout.rewards.get_global_rect()), "details leave reward candidates visible")
	main._primary_action()
	var count: int = main.inventory.items.size()
	main._primary_action()
	main.session.skip_playback()
	verify(main.inventory.items.size() == count and main.session.display_snapshot().phase == "victory" and not main.layout.rewards.visible, "double confirm grants once and closes reward panel")
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().encounter == 1 and main.inventory.is_packed(uid), "next encounter keeps confirmed reward placement")
	main._reset_run()
	verify(not main.layout.rewards.visible and not main.inventory.items.has(uid), "restart hides old offers and removes reward instance")
	main.queue_free()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args(): await _capture_shipping()
	print("REWARD UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _capture_shipping() -> void:
	# Optional rendered evidence from shipping content, never part of headless assertions.
	root.size = Vector2i(1280,720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	main._place("seal", Vector2i(2,1), 0)
	main._place("ring", Vector2i(0,0), 0)
	main._primary_action()
	main.session.skip_playback()
	for turn in 30:
		if main.session.display_snapshot().phase != "battle": break
		for uid in ["sword", "bell", "hat"]:
			if main.session.use_error(uid).is_empty():
				main._activate_item(uid)
				main.session.skip_playback()
		if main.session.display_snapshot().phase == "battle":
			main._primary_action()
			main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "reward", "shipping first battle reaches reward screen")
	if main.session.display_snapshot().phase == "reward":
		main.layout.rewards.choices[0].pressed.emit()
		main.session.skip_playback()
		var uid: String = main.session.display_snapshot().reward.uid
		main.inventory.move_to_stash("hat")
		main._place(uid, Vector2i(1,2), 1)
		main._inspect(uid)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/reward-screen.png"))
	main.queue_free()
	await process_frame
