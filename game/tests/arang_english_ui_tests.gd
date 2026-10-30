extends SceneTree
const Experiment = preload("res://tests/arang_experiment_setup.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func _no_hangul(node: Node) -> bool:
	if node is CanvasItem and not node.is_visible_in_tree(): return true
	if node is Label or node is Button:
		if PresentationLocale.contains_hangul(str(node.text)): return false
	for child in node.get_children():
		if not _no_hangul(child): return false
	return true
func _submit(main: Control, request: Dictionary) -> bool:
	var error: String = main.session.submit(request)
	if error.is_empty(): main.session.skip_playback()
	return error.is_empty()
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var directory := ProjectSettings.globalize_path("res://../build/arang-english/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var slot := directory.path_join("legacy.json")
	var old_model := ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	var old_hash := old_model.content_hash
	var old_state := CombatResolver.new(old_model).snapshot()
	old_state.messages = [String.chr(0xc800) + String.chr(0xc2b9)]
	var service := SaveService.new(slot)
	check(service.load_slot(old_model).status == "missing", "isolated legacy save starts empty")
	check(service.write_slot(old_state, old_model, []).is_empty(), "legacy catalog save is created")
	var original := FileAccess.get_file_as_string(slot)
	var main := Experiment.create(root, slot)
	await process_frame
	check(main != null and not main._save_blocked, "existing scenario save loads without archival")
	check(main.inventory.content_hash == old_hash and FileAccess.get_file_as_string(slot) == original, "loading English presentation leaves the legacy hash and save bytes untouched")
	check(main.session.state_snapshot().messages == old_state.messages, "old saved messages remain unchanged in authoritative state")
	check(main.labels.log.text.contains("Previous message unavailable in English") and not PresentationLocale.contains_hangul(main.labels.log.text), "old message is hidden behind an English placeholder")
	check(main.labels.enemy.text == "Terrified Guard" and main.inventory.definition("sword").display_name == "Sain Sword", "legacy character and item names display in English")
	check(main.inventory.definition("ring").description.contains("promise") and main.inventory.definition("ring").effects.is_empty(), "legacy ring description matches its unchanged rules")
	check(not PresentationLocale.contains_hangul(main.story_entries[0].text), "scenario dialogue is English")
	var edition_font: Font = main.labels.edition.get_theme_default_font()
	check(edition_font.get_string_size(main.labels.edition.text, HORIZONTAL_ALIGNMENT_LEFT, -1, main.labels.edition.get_theme_font_size("font_size")).x <= main.labels.edition.size.x, "saved-demo header text fits its own region")
	main.story_forced = true
	main._refresh_details()
	await process_frame
	check(main.layout.story.visible and not main.layout.buttons.story_teaser.visible, "open story does not duplicate the teaser")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var chapter: Rect2 = main.labels.chapter.get_global_rect()
		var edition: Rect2 = main.labels.edition.get_global_rect()
		check(not chapter.intersects(edition) and not edition.intersects(main.layout.buttons.story.get_global_rect()), "scenario edition label avoids header text and buttons at " + str(window_size))
		check(Rect2(Vector2.ZERO, main.size).encloses(main.layout.story.get_global_rect()) and not main.layout.story.get_global_rect().intersects(main.primary.get_global_rect()), "story avoids the action button at " + str(window_size))
		check(_no_hangul(main.layout), "visible labels and buttons are English at " + str(window_size))
	root.size = Vector2i(1280,720)
	main.story_forced = false
	main._refresh_details()
	check(main.layout.buttons.story_teaser.visible, "teaser returns when story closes")
	check(_submit(main, {"type":"start"}), "legacy saved run remains playable")
	check(_submit(main, {"type":"use_item", "uid":"sword"}), "localized item can be used")
	check(not PresentationLocale.contains_hangul(main.labels.notice.text) and not PresentationLocale.contains_hangul(main.labels.log.text), "new combat messages are English")
	var restored := SaveService.new(slot).load_slot(ItemCatalog.create_inventory(Experiment.CONTENT_PATH))
	check(restored.status == "ok" and restored.state.phase == "battle", "updated save remains compatible with the original catalog")
	var long_state: Dictionary = main.session.display_snapshot()
	long_state.messages = ["An unusually long combat log entry remains readable through scrolling. ".repeat(4), "Another long entry describes the enemy action and its outcome. ".repeat(4)]
	main.session.reset(main.inventory, long_state)
	await process_frame
	await process_frame
	check(main.layout.log_scroll.visible and main.layout.log_scroll.get_v_scroll_bar().max_value > main.layout.log_scroll.get_v_scroll_bar().page, "long combat messages scroll within their dedicated panel")
	check(main.layout.log_scroll.get_global_rect().end.y <= main.hero_bar.get_global_rect().position.y, "combat log stays above the health bars")
	for turn in 8:
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty(): _submit(main, {"type":"use_item", "uid":uid})
		if main.session.display_snapshot().phase != "battle": break
		_submit(main, {"type":"end_turn"})
	check(main.session.display_snapshot().phase == "reward" and _no_hangul(main.layout), "reward and item choices are English")
	var offer: String = main.session.display_snapshot().reward.offer_id
	check(_submit(main, {"type":"reward_skip", "offer_id":offer}) and _submit(main, {"type":"advance"}), "legacy scenario proceeds to evidence")
	check(main.session.display_snapshot().phase == "event" and _no_hangul(main.layout), "evidence dialogue and choices are English")
	var event: Dictionary = main.session.display_snapshot().event
	check(_submit(main, {"type":"event_take", "event_id":event.id}) and _submit(main, {"type":"event_confirm", "event_id":event.id}), "evidence can be kept")
	check(main.session.display_snapshot().phase == "route" and _no_hangul(main.layout), "route names and descriptions are English")
	var route: String = main.inventory.config.routes[0].id
	check(_submit(main, {"type":"choose_route", "route_id":route}), "legacy scenario reaches Arang")
	check(main.labels.enemy.text == "Arang, Restless Spirit" and _no_hangul(main.layout), "Arang name and preparation are English")
	check(main.session.stash("hat").is_empty() and main.session.place(event.uid, Vector2i(1,2), 0).is_empty(), "evidence fits in the bag")
	check(_submit(main, {"type":"start"}) and _no_hangul(main.layout), "boss battle and resolution button are English")
	check(_submit(main, {"type":"resolve_encounter"}), "peaceful resolution succeeds")
	check(main.session.display_snapshot().phase == "event_result" and _no_hangul(main.layout), "Arang resolution dialogue is English")
	check(_submit(main, {"type":"event_continue", "event_id":event.id}) and _no_hangul(main.layout), "ending is English")
	main.queue_free()
	await process_frame
	# A malformed pack must fail before changing even one display field.
	var model := ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	var before: String = model.definition("sword").display_name
	var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Experiment.TEXT_PATH))
	invalid.items.seal.erase("description")
	var invalid_path := directory.path_join("bad-pack.json")
	var f := FileAccess.open(invalid_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(invalid))
	f.close()
	check(not PresentationLocale.apply(model, invalid_path).is_empty() and model.definition("sword").display_name == before, "invalid text pack cannot partially mutate the catalog")
	print("ARANG ENGLISH UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
