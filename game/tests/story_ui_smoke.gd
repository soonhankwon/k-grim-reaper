extends SceneTree

var failed := false

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func beat(main: Control) -> void:
	var state: Dictionary = main.session.display_snapshot()
	state.phase = "battle"
	state.enemy_health = 1
	state.used.clear()
	state.energy = state.config.energy_per_turn
	main.session.reset(main.inventory, state)
	main._activate_item("sword")

func _run() -> void:
	var entries := StoryBook.load_entries("res://tests/fixtures/story-v0.13.json")
	verify(entries.size() == 4, "shipping story loads")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/story-v0.13.json"))
	var bad := raw.duplicate(true)
	bad.entries[1].id = bad.entries[0].id
	verify(StoryBook.validate(bad).is_empty(), "duplicate story ID is rejected")
	bad = raw.duplicate(true)
	bad.entries[1].min_completed = -1
	verify(StoryBook.validate(bad).is_empty(), "negative milestone is rejected")
	bad = raw.duplicate(true)
	bad.entries[0].text = ""
	verify(StoryBook.validate(bad).is_empty(), "empty story text is rejected")
	verify(StoryBook.load_entries("res://missing-story.json").is_empty(), "missing presentation story fails safely")
	root.size = Vector2i(1280,720)
	var folder := ProjectSettings.globalize_path("res://../build/story-ui/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var slot := folder.path_join("run.json")
	var model := ItemCatalog.create_inventory("res://tests/fixtures/catalog-v0.13.json")
	for route: Dictionary in model.config.routes:
		for step in range(3):
			var sample := CombatSimulator.initial_state(model.config)
			sample.route = {"choice": "" if step == 0 else route.id, "step": step}
			sample.encounter = route.encounters[step]
			sample.phase = "packing"
			verify(StoryBook.unlocked(sample, entries).size() == step + 1, "each route unlocks entries by completed step")
			sample.phase = "defeat"
			verify(StoryBook.unlocked(sample, entries).size() == step + 1, "defeat cannot reveal an uncompleted entry")
	var store := SaveService.new(slot)
	verify(store.load_slot(model).status == "missing", "isolated 0.8 slot starts empty")
	verify(store.write_slot(CombatResolver.new(model).snapshot(), model, []).is_empty(), "write previous-format save")
	var saved := FileAccess.get_sha256(slot)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = "res://tests/fixtures/catalog-v0.13.json"
	main.story_path = "res://tests/fixtures/story-v0.13.json"
	main.save_path = slot
	root.add_child(main)
	await process_frame
	await process_frame
	verify(FileAccess.get_sha256(slot) == saved and main.layout.buttons.story_teaser.visible, "opening existing save keeps its bytes and shows intro")
	verify(main.layout.buttons.story.text == "Story 1" and "첫 인도" in main.layout.buttons.story_teaser.text, "only first entry is visible initially")
	var before: Dictionary = main.session.state_snapshot()
	main.layout.buttons.story_teaser.pressed.emit()
	verify(main.layout.story.visible and not main.layout.guide.visible and main.layout.story.column.get_child_count() == 2, "teaser opens first entry in notebook")
	verify(main.session.state_snapshot() == before and FileAccess.get_sha256(slot) == saved, "reading story never changes progress or save")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var boundary := Rect2(Vector2.ZERO, main.size)
		verify(boundary.encloses(main.layout.story.get_global_rect()), "story panel fits window")
		verify(not main.layout.story.get_global_rect().intersects(main.board.get_global_rect()), "story panel leaves board accessible")
		verify(not main.layout.story.get_global_rect().intersects(main.primary.get_global_rect()), "story panel leaves primary action accessible")
		verify(boundary.encloses(main.layout.buttons.story_teaser.get_global_rect()), "story teaser fits window")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/story-screen.png"))
	beat(main)
	verify(main.session.state_snapshot().phase == "reward" and main.layout.buttons.story.text == "Story 1", "unplayed victory does not reveal a new entry")
	main.session.skip_playback()
	verify(main.layout.buttons.story.text == "Story 2" and main.layout.story.column.get_child_count() == 4, "first victory reveals first trace")
	main._reward_action("reward_skip")
	main.session.skip_playback()
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "event", "event opens after first reward")
	main._event_action("event_leave")
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "route" and main.layout.buttons.story.text == "Story 2", "route choice keeps the same unlocked entries")
	main.layout.routes.choices[1].pressed.emit()
	main.session.skip_playback()
	verify(main.session.display_snapshot().encounter == 2 and main.layout.buttons.story.text == "Story 2", "alternate enemy order preserves progress")
	beat(main)
	main.session.skip_playback()
	verify(main.layout.buttons.story.text == "Story 3", "second victory reveals second trace")
	verify(main.session.display_snapshot().phase == "event_result", "second victory opens follow-up")
	main._event_action("event_continue")
	main.session.skip_playback()
	main._reward_action("reward_skip")
	main.session.skip_playback()
	main._primary_action()
	main.session.skip_playback()
	beat(main)
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "victory" and main.layout.buttons.story.text == "Story 3", "ending waits for final handover")
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().phase == "complete" and main.layout.buttons.story.text == "Story 4", "completion reveals ending")
	await process_frame
	await process_frame
	verify(main.layout.story.scroll.get_v_scroll_bar().max_value > main.layout.story.scroll.size.y, "long notebook remains scrollable")
	before = main.session.display_snapshot()
	saved = FileAccess.get_sha256(slot)
	main.queue_free()
	await process_frame
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = "res://tests/fixtures/catalog-v0.13.json"
	main.story_path = "res://tests/fixtures/story-v0.13.json"
	main.save_path = slot
	root.add_child(main)
	await process_frame
	verify(main.session.display_snapshot() == before and main.layout.buttons.story.text == "Story 4" and FileAccess.get_sha256(slot) == saved, "reopen restores ending without new story state or rewriting save")
	main.queue_free()
	await process_frame
	print("STORY UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
