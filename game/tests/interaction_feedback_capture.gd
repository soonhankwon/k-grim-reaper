extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	main.sounds.set_enabled(false)
	await process_frame
	var board: InventoryBoard = main.board
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = InventoryBoard.PAD + Vector2(1.5,0.5) * board.cell_size
	board._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = board.get_global_transform_with_canvas() * (InventoryBoard.PAD + Vector2(2.5,1.5) * board.cell_size)
	board._input(motion)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/interaction-drag.png"))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	board._input(release)
	board.placement_queue._process(0)
	var command: LayoutFeedbackCommand = board.placement_queue._current
	if command._tween != null: command._tween.pause()
	board.set_placement_feedback_progress(0.5)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/interaction-snap.png"))
	board.stop_placement_feedback()
	main.queue_free()
	await process_frame
	print("INTERACTION CAPTURE: PASS")
	quit()
