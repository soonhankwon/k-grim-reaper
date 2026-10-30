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

func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, false)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event, false)

func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	root.push_input(press, false)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, false)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	root.push_input(release, false)

func _wheel(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, false)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event, false)

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	main.content_path = "res://tests/fixtures/baseline.json"
	root.add_child(main)
	for spec in [[Vector2i(1024, 576), 1, Vector2(192, 108)], [Vector2i(1280, 720), 2, Vector2.ZERO], [Vector2i(1366, 768), 2, Vector2(43, 24)], [Vector2i(1920, 1080), 3, Vector2.ZERO]]:
		root.size = spec[0]
		await process_frame
		await process_frame
		var transform := root.get_screen_transform()
		check(root.get_visible_rect().size == Vector2(640, 360), "logical viewport remains 640x360")
		check(is_equal_approx(transform.x.x, spec[1]) and is_equal_approx(transform.y.y, spec[1]) and transform.origin.is_equal_approx(spec[2]), "integer scale and centered margins at " + str(spec[0]))
		check(main.layout.scale.is_equal_approx(Vector2(0.5, 0.5)), "layout matches the logical viewport")
		var board_transform: Transform2D = transform * main.board.get_global_transform_with_canvas()
		var from: Vector2 = board_transform * (InventoryBoard.PAD + Vector2(1.5, 0.5) * InventoryBoard.CELL)
		var to: Vector2 = board_transform * (InventoryBoard.PAD + Vector2(2.5, 1.5) * InventoryBoard.CELL)
		_drag(from, to)
		await process_frame
		check(main.inventory.items.seal.origin == Vector2i(2, 1), "scaled drag places the item at " + str(spec[0]))
		main._inspect("seal")
		main.labels.description.text = "This long item description must remain scrollable. ".repeat(20)
		await process_frame
		await process_frame
		var scroll: ScrollContainer = main.layout.detail_scroll
		check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "long details have a scroll range")
		_wheel(transform * scroll.get_global_rect().get_center())
		await process_frame
		check(scroll.scroll_vertical > 0, "scaled mouse wheel scrolls details at " + str(spec[0]))
		main._inspect("")
		var center: Vector2 = main.primary.get_global_rect().get_center()
		var screen_position: Vector2 = transform * center
		_click(screen_position)
		await process_frame
		check(main.session.state_snapshot().phase == "battle", "scaled primary button receives a click at " + str(spec[0]))
		main.session.skip_playback()
		main._reset_run()
		await process_frame
	main.queue_free()
	await process_frame
	print("PIXEL VIEWPORT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
