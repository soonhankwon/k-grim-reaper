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
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/retro-game-screen.png"))
	var state := CombatSimulator.initial_state(main.inventory.config)
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main._activate_item("sword")
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "reward", "first victory opens reward")
	main._reward_action("reward_skip")
	main.session.skip_playback()
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "event", "first reward opens event before route")
	main._event_action("event_leave")
	main.session.skip_playback()
	await process_frame
	verify(main.session.display_snapshot().phase == "route" and main.layout.routes.visible, "route panel follows reward")
	verify(main.primary.disabled and main.layout.routes.choices.size() == 2 and main.display_inventory.locked, "route choice locks other actions")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var panel: Rect2 = main.layout.routes.get_global_rect()
		verify(Rect2(Vector2.ZERO, main.size).encloses(panel), "route panel fits " + str(window_size))
		for choice: Button in main.layout.routes.choices:
			verify(panel.encloses(choice.get_global_rect()), "route choice fits panel at " + str(window_size))
			verify(not choice.get_global_rect().intersects(main.primary.get_global_rect()), "route choice does not cover main button")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/route-screen.png"))
	main.layout.routes.choices[1].pressed.emit()
	verify(main.session.state_snapshot().encounter == 2, "second path chooses the gatekeeper")
	main.layout.routes.choices[0].pressed.emit()
	main.session.skip_playback()
	verify(main.session.display_snapshot().encounter == 2 and main.session.display_snapshot().phase == "packing", "rapid second click cannot change the chosen path")
	main.queue_free()
	await process_frame
	print("ROUTE UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
