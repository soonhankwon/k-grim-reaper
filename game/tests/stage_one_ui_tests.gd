extends SceneTree
## Full shipping-catalog paths, using only isolated temporary slots.

var checks := 0
var failures := 0
var base := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func make_main(slot: String) -> Control:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path = slot
	root.add_child(main)
	return main

func submit(main: Control, request: Dictionary) -> bool:
	var error: String = main.session.submit(request)
	if error.is_empty(): main.session.skip_playback()
	else: push_error("request failed: " + error)
	return error.is_empty()

func fight(main: Control) -> bool:
	for turn in range(10):
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty() and not submit(main, {"type":"use_item", "uid":uid}): return false
		if main.session.display_snapshot().phase != "battle": break
		if not submit(main, {"type":"end_turn"}): return false
	return main.session.display_snapshot().phase in ["reward", "event_result"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	base = ProjectSettings.globalize_path("res://../build/stage-one-ui/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	await _test_old_save_preservation()
	for path_index in [0,1]:
		for choice in ["resolve", "stashed", "leave"]:
			await _play(path_index, choice)
	print("STAGE ONE UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_old_save_preservation() -> void:
	var slot := base.path_join("old-save.json")
	var old := ItemCatalog.create_inventory("res://tests/fixtures/catalog-v0.13.json")
	var state := CombatResolver.new(old).snapshot()
	var doc: Dictionary = JSON.parse_string(JSON.parse_string(SaveCodec.encode(state, old, [])).payload)
	doc.version = 3
	var original := SaveCodec._wrap(doc)
	var f := FileAccess.open(slot, FileAccess.WRITE)
	f.store_string(original)
	f.close()
	var main := make_main(slot)
	await process_frame
	check(main._save_blocked and FileAccess.get_file_as_string(slot) == original, "old incompatible save remains unchanged on open")
	check(main.recovery_dialog != null and main.recovery_dialog.visible, "recovery confirmation appears")
	main.recovery_dialog.hide()
	check(FileAccess.get_file_as_string(slot) == original, "cancel leaves old bytes untouched")
	main._archive_new_run()
	check(not main._save_blocked and main.session.display_snapshot().phase == "packing", "explicit archive starts new content")
	var archive := slot.get_base_dir().path_join("archive").path_join(slot.get_file() + "." + original.sha256_text() + ".json")
	check(FileAccess.get_file_as_string(archive) == original, "archive retains exact original bytes")
	main.queue_free()
	await process_frame

func _play(path_index: int, choice: String) -> void:
	var slot := base.path_join("path-%d-%s.json" % [path_index, choice])
	var main := make_main(slot)
	await process_frame
	check(not main._save_blocked and main.inventory.config.resolutions.size() == 1, "shipping stage loads")
	check(main.labels.enemy.text.contains("Guard") and main.layout.background_texture.resource_path.ends_with("arang-office-v1.png"), "intro uses constable and office")
	if "--capture" in OS.get_cmdline_user_args() and path_index == 0 and choice == "resolve":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-stage-office.png"))
	check(submit(main, {"type":"start"}) and fight(main), "first battle won with normal starting layout")
	check(submit(main, {"type":"reward_skip", "offer_id":main.session.display_snapshot().reward.offer_id}), "first reward handled")
	check(submit(main, {"type":"advance"}) and main.session.display_snapshot().phase == "event", "evidence event opens")
	var event: Dictionary = main.session.display_snapshot().event
	if choice == "leave":
		check(submit(main, {"type":"event_leave", "event_id":event.id}), "leave evidence")
	else:
		check(submit(main, {"type":"event_take", "event_id":event.id}) and submit(main, {"type":"event_confirm", "event_id":event.id}), "take evidence while stashed")
	check(main.layout.routes.visible and main.layout.routes.choices.size() == 2, "two routes visible")
	for button: Button in main.layout.routes.choices:
		check(not button.text.contains("Then:"), "route does not promise an extra encounter")
	var selected_route: Dictionary = main.inventory.config.routes[path_index]
	check(submit(main, {"type":"choose_route", "route_id":selected_route.id}), "select path")
	check(main.labels.enemy.text == "Arang, Restless Spirit" and main.layout.background_texture.resource_path.ends_with("arang-bamboo-v1.png"), "second encounter uses arang and grove")
	var intent: Dictionary = CombatSimulator.intent(main.session.display_snapshot())
	check(intent.operation == ("set_guard" if path_index == 0 else "damage"), "route displays different opening intention")
	if choice == "resolve": check(main.session.stash("hat").is_empty() and main.session.place(event.uid, Vector2i(1,2), 0).is_empty(), "evidence fits after meaningful rearrangement")
	check(submit(main, {"type":"start"}), "start arang encounter")
	check(main.layout.buttons.resolution.visible and main.layout.buttons.resolution.disabled == (choice != "resolve"), "resolution availability matches evidence")
	if "--capture" in OS.get_cmdline_user_args() and path_index == 0 and choice == "resolve":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-stage-boss.png"))
	if choice == "resolve":
		main.layout.buttons.resolution.pressed.emit()
		check(main.session.state_snapshot().phase == "event_result" and main.session.display_snapshot().phase == "battle", "resolution is saved before display")
		var final_state: Dictionary = main.session.state_snapshot()
		main.queue_free()
		await process_frame
		main = make_main(slot)
		await process_frame
		check(main.session.display_snapshot() == final_state and main.session.display_snapshot().event.get("method", "") == "resolution", "reopen during playback restores peaceful result")
	else:
		check(fight(main) and main.session.display_snapshot().phase == "event_result", "attack path works from real state")
		check(main.session.display_snapshot().event.get("method", "") != "resolution", "attack ending distinguished")
	check(submit(main, {"type":"event_continue", "event_id":event.id}) and main.session.display_snapshot().phase == "complete", "stage completes")
	var completed: Dictionary = main.session.display_snapshot()
	main.queue_free()
	await process_frame
	main = make_main(slot)
	await process_frame
	check(main.session.display_snapshot() == completed and main.layout.buttons.story.text == "Story 4", "ending and story restore")
	main.queue_free()
	await process_frame
