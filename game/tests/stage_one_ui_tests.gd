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
		for choice in ["resolve", "carried_fight", "stashed", "leave"]:
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
	var intent_font: Font = main.labels.intent.get_theme_font("font")
	check(intent_font.get_string_size(main.labels.intent.text, HORIZONTAL_ALIGNMENT_LEFT, -1, main.labels.intent.get_theme_font_size("font_size")).x <= main.labels.intent.size.x, "victory guidance fits its label")
	check(submit(main, {"type":"advance"}) and main.session.display_snapshot().phase == "event", "evidence event opens")
	check(main.primary.disabled and main.primary.text == "Choose below", "unselected event asks for a choice instead of requiring bag placement")
	var event: Dictionary = main.session.display_snapshot().event
	await process_frame
	await process_frame
	check(main.layout.encounter_event.description.text.contains("Someone has to remember"), "evidence scene introduces the voice without revealing the ending")
	check(main.layout.encounter_event.description_scroll.get_v_scroll_bar().max_value > main.layout.encounter_event.description_scroll.get_v_scroll_bar().page, "long evidence scene is scrollable")
	var before_read: Dictionary = main.session.state_snapshot()
	var saved_before_read := FileAccess.get_sha256(slot)
	main.layout.encounter_event.description_scroll.scroll_vertical = 30
	await process_frame
	check(main.session.state_snapshot() == before_read and FileAccess.get_sha256(slot) == saved_before_read, "reading evidence changes neither state nor save")
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
	check(main.layout.buttons.story_teaser.text.contains("left behind") if choice == "leave" else main.layout.buttons.story_teaser.text.contains("Carry the mirror"), "preparation hint reflects whether evidence was left or stored")
	var intent: Dictionary = CombatSimulator.intent(main.session.display_snapshot())
	check(intent.operation == ("set_guard" if path_index == 0 else "damage"), "route displays different opening intention")
	if choice in ["resolve", "carried_fight"]:
		check(main.session.stash("hat").is_empty() and main.session.place(event.uid, Vector2i(1,2), 0).is_empty(), "evidence fits after meaningful rearrangement")
		check(main.layout.buttons.story_teaser.text.contains("in your bag"), "preparation hint acknowledges packed evidence")
	check(submit(main, {"type":"start"}), "start arang encounter")
	check(main.layout.buttons.resolution.visible and main.layout.buttons.resolution.disabled == (choice not in ["resolve", "carried_fight"]), "resolution availability matches evidence")
	if choice == "leave": check(main.layout.buttons.resolution.text == "Evidence left behind" and main.layout.buttons.resolution.tooltip_text.contains("left"), "left evidence cannot be mistaken for retrievable evidence")
	if choice == "stashed": check(main.layout.buttons.resolution.text == "Place evidence in your bag", "stored evidence instructions remain distinct")
	if "--capture" in OS.get_cmdline_user_args() and path_index == 0 and choice == "resolve":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-stage-boss.png"))
	if choice == "resolve":
		main.layout.buttons.resolution.pressed.emit()
		check(main.session.state_snapshot().phase == "event_result" and main.session.display_snapshot().phase == "battle", "resolution is saved before display")
		main.session.playback.queue._process(0)
		check(main.cinematics.visible and main.cinematics.mode == "dialogue" and main.cinematics.data.speaker == "Arang", "mirror triggers Arang's recorded reaction")
		check(main.session.display_snapshot().phase == "battle", "mirror dialogue precedes the displayed outcome")
		var final_state: Dictionary = main.session.state_snapshot()
		main.queue_free()
		await process_frame
		main = make_main(slot)
		await process_frame
		check(main.session.display_snapshot() == final_state and main.session.display_snapshot().event.get("method", "") == "resolution", "reopen during playback restores peaceful result")
	else:
		check(fight(main) and main.session.display_snapshot().phase == "event_result", "attack path works from real state")
		check(main.session.display_snapshot().event.get("method", "") != "resolution", "attack ending distinguished")
	await process_frame
	await process_frame
	var outcome: String = main.layout.encounter_event.description.text
	check(outcome.contains("My name is Arang") if choice == "resolve" else (outcome.contains("In your bag") if choice == "carried_fight" else (outcome.contains("safe in storage") if choice == "stashed" else outcome.contains("mirror left"))), "the displayed outcome matches the committed choice")
	if choice == "resolve":
		check(main.layout.encounter_event.description_scroll.get_v_scroll_bar().max_value > main.layout.encounter_event.description_scroll.get_v_scroll_bar().page, "long ending is scrollable")
	if "--capture" in OS.get_cmdline_user_args() and path_index == 0 and choice == "resolve":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-narrative-ending.png"))
	check(submit(main, {"type":"event_continue", "event_id":event.id}) and main.session.display_snapshot().phase == "complete", "stage completes")
	var completed: Dictionary = main.session.display_snapshot()
	main.queue_free()
	await process_frame
	main = make_main(slot)
	await process_frame
	check(main.session.display_snapshot() == completed and main.layout.buttons.story.text == "Story 4", "ending and story restore")
	main.queue_free()
	await process_frame
