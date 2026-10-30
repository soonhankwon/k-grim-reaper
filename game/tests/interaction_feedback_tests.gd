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
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	var board: InventoryBoard = main.board
	var before: Dictionary = main.session.display_snapshot()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = InventoryBoard.PAD + Vector2(1.5, 0.5) * board.cell_size
	board._gui_input(press)
	check(board.pressed_uid == "seal" and not board.dragging, "press picks up without prematurely moving")
	var motion := InputEventMouseMotion.new()
	motion.position = board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(2.5, 1.5) * board.cell_size)
	board._input(motion)
	check(board.dragging and board.drag_pointer.is_equal_approx(InventoryBoard.PAD + Vector2(2.5, 1.5) * board.cell_size), "lifted item tracks the pointer in board coordinates")
	check(board.synergy_view().mode == "preview" and main.session.display_snapshot() == before, "drag preview leaves displayed state unchanged")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	board._input(release)
	check(not board.dragging and main.session.display_snapshot().inventory_items.seal.origin == Vector2i(2,1), "drop commits existing layout transaction")
	check(board.placement_uid == "seal" and board.placement_queue.is_busy() and board.placement_new_link, "new synergy starts queued snap and pulse")
	check(main.sounds.player.stream == PresentationSound.CUES.snap, "successful changed placement plays snap cue")
	var committed: Dictionary = main.session.display_snapshot()
	board.placement_queue._process(0)
	check(board.placement_queue._current is LayoutFeedbackCommand, "command owns the snap tween")
	board.set_placement_feedback_progress(0.5)
	check(board.placement_progress == 0.5 and board.placement_new_link and main.session.display_snapshot() == committed, "pulse progress is visual only")
	var old_command: LayoutFeedbackCommand = board.placement_queue._current
	main._cancel()
	check(not board.placement_queue.is_busy() and board.placement_uid.is_empty(), "cancel clears an active command")
	old_command._complete()
	check(board.placement_uid.is_empty() and main.session.display_snapshot() == committed, "late completion cannot change state")
	main._select("seal")
	main.sounds.stop()
	main.sounds.player.stream = null
	main._place("seal", Vector2i(2,1), 0)
	check(not board.placement_queue.is_busy() and main.sounds.player.stream == null, "unchanged placement has no snap or sound")
	main._place("seal", Vector2i(3,0), 0)
	check(not board.placement_queue.is_busy() and main.sounds.player.stream == null and main.session.display_snapshot() == committed, "invalid placement has no snap and preserves state")
	main._place("seal", Vector2i(1,0), 0)
	check(board.placement_uid == "seal" and not board.placement_new_link, "removing an existing connection does not pulse")
	board.placement_queue._process(0)
	await create_timer(0.45).timeout
	check(not board.placement_queue.is_busy() and board.placement_uid.is_empty(), "natural completion clears the snap")
	main._place("seal", Vector2i(2,1), 0)
	board.placement_queue._process(0)
	board.placement_queue._process(board.placement_queue.timeout_seconds)
	check(not board.placement_queue.is_busy() and board.placement_uid.is_empty() and main.session.display_snapshot().inventory_items.seal.origin == Vector2i(2,1), "watchdog clears feedback without changing committed layout")
	main._place("seal", Vector2i(1,0), 0)
	board.stop_placement_feedback()
	main._place("seal", Vector2i(2,1), 0)
	board.placement_queue._process(0)
	main._reset_run()
	await create_timer(0.4).timeout
	check(not board.placement_queue.is_busy() and board.placement_uid.is_empty() and main.session.display_snapshot().inventory_items.seal.origin == Vector2i(1,0), "restart cancels stale animation")
	main._select("seal")
	main.sounds.stop()
	main.sounds.player.stream = null
	main.session.save_service = SaveService.new("res://../build/interaction-tests/uninitialized.json")
	before = main.session.display_snapshot()
	main._place("seal", Vector2i(2,1), 0)
	check(main.session.display_snapshot() == before and board.placement_uid.is_empty() and main.sounds.player.stream == null, "save failure shows neither snap nor sound and preserves layout")
	main.session.save_service = null
	main._place("seal", Vector2i(2,1), 0)
	board.placement_queue._process(0)
	main._primary_action()
	check(board.placement_uid.is_empty() and not board.placement_queue.is_busy(), "battle playback cancels layout feedback")
	main.session.skip_playback()
	check(main.session.display_snapshot().phase == "battle", "battle proceeds after cancellation")
	var battle: Dictionary = main.session.display_snapshot()
	battle.guard = 3
	main.session.reset(main.inventory, battle)
	check(main.labels.preview_summary.text.contains("Expected damage 2") and main.labels.preview_summary.text.contains("Blocked 3") and main.labels.preview_summary.text.contains("Remaining HP 26"), "turn preview separates absorbed damage and health loss")
	main._reset_run()
	main.sounds.set_enabled(false)
	main._select("seal")
	main._place("seal", Vector2i(2,1), 0)
	check(board.placement_queue.is_busy() and not main.sounds.player.playing, "sound toggle silences the cue without suppressing visual feedback")
	press.position = InventoryBoard.PAD + Vector2(2.5,1.5) * board.cell_size
	motion.position = board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(1.5,0.5) * board.cell_size)
	board._gui_input(press)
	board._input(motion)
	check(board.dragging, "drag can start after a muted placement")
	main._primary_action()
	check(not board.dragging and board.pressed_uid.is_empty(), "battle start cancels a drag")
	main.session.skip_playback()
	main.queue_free()
	await process_frame
	print("INTERACTION FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
