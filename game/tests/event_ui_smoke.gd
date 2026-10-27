extends SceneTree
var failed := false
var slot: String

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func make_main() -> Control:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path = slot
	root.add_child(main)
	return main

func _run() -> void:
	root.size = Vector2i(1280,720)
	var folder := ProjectSettings.globalize_path("res://../build/event-ui/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	slot = folder.path_join("run.json")
	var main := make_main()
	await process_frame
	var state := CombatSimulator.initial_state(main.inventory.config)
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main._activate_item("sword")
	main.session.skip_playback()
	main._reward_action("reward_skip")
	main.session.skip_playback()
	main._primary_action()
	main.session.skip_playback()
	await process_frame
	verify(main.session.display_snapshot().phase == "event" and main.layout.encounter_event.visible and main.primary.disabled, "event offers both choices")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var panel: Rect2 = main.layout.encounter_event.get_global_rect()
		verify(Rect2(Vector2.ZERO, main.size).encloses(panel), "event fits window")
		verify(panel.encloses(main.layout.encounter_event.take.get_global_rect()) and panel.encloses(main.layout.encounter_event.leave.get_global_rect()), "event choices fit panel")
		verify(not panel.intersects(main.primary.get_global_rect()) and not panel.intersects(main.board.get_global_rect()), "event leaves inventory and confirm accessible")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/event-screen.png"))
	main.layout.encounter_event.take.pressed.emit()
	var uid: String = main.session.state_snapshot().event.uid
	verify(not main.session.display_snapshot().inventory_items.has(uid), "relic remains hidden until selection playback")
	main.layout.encounter_event.leave.pressed.emit()
	main.session.skip_playback()
	verify(main.selected == uid and not main.inventory.is_packed(uid) and main.primary.disabled, "relic arrives selected in stash")
	main._primary_action()
	verify(main.session.display_snapshot().phase == "event", "unpacked relic cannot confirm")
	main._select("hat")
	main._stash_selected()
	main._select(uid)
	main._place(uid, Vector2i(1,2), 0)
	verify(main.inventory.is_packed(uid) and not main.primary.disabled, "packed relic enables confirmation")
	var expected: Dictionary = main.session.state_snapshot()
	main.queue_free()
	await process_frame
	main = make_main()
	await process_frame
	verify(main.session.display_snapshot() == expected and main.selected == uid and not main.primary.disabled, "event placement and selected relic resume")
	main._primary_action()
	expected = main.session.state_snapshot()
	verify(expected.phase == "route" and main.session.display_snapshot().phase == "event", "event choice saves before playback")
	main.queue_free()
	await process_frame
	main = make_main()
	await process_frame
	verify(main.session.display_snapshot() == expected and main.layout.routes.visible, "restart during choice playback resumes route once")
	main.layout.routes.choices[1].pressed.emit()
	main.session.skip_playback()
	state = main.session.display_snapshot()
	state.phase = "battle"
	state.enemy_health = 1
	state.health = 10
	state.used.clear()
	state.energy = state.config.energy_per_turn
	main.session.reset(main.inventory, state)
	main._activate_item("sword")
	expected = main.session.state_snapshot()
	verify(expected.phase == "event_result" and expected.health == 18 and main.session.display_snapshot().phase == "battle", "follow-up waits for playback")
	main.queue_free()
	await process_frame
	main = make_main()
	await process_frame
	verify(main.session.display_snapshot() == expected and main.layout.encounter_event.visible, "follow-up resumes without repeating heal")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/event-result-screen.png"))
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "reward" and main.session.display_snapshot().health == 18, "continuing reveals reward without repeated heal")
	main.queue_free()
	await process_frame
	print("EVENT UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
