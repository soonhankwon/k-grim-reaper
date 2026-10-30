extends SceneTree
var main: Control
func _initialize() -> void:
	call_deferred("_run")
func _snapshot(name: String) -> void:
	await process_frame
	await process_frame
	var keys := ["chapter", "bag", "synergy_state", "passive", "notice", "hero_name", "enemy", "energy", "intent", "hero", "enemy_hp", "help"]
	for key in keys:
		var label: Label = main.labels[key]
		if label.is_visible_in_tree() and label.get_combined_minimum_size().y > label.size.y + 0.5:
			print("OVERFLOW ", name, " ", key, " ", label.size, " needs ", label.get_combined_minimum_size())
	for pair in [["notice", "intent"], ["notice", "enemy"], ["notice", "hero_name"], ["chapter", "bag"], ["bag", "synergy_state"], ["intent", "enemy"], ["energy", "notice"], ["energy", "hero_name"]]:
		var a: Label = main.labels[pair[0]]
		var b: Label = main.labels[pair[1]]
		if a.is_visible_in_tree() and b.is_visible_in_tree() and a.get_global_rect().intersects(b.get_global_rect()): print("OVERLAP ", name, " ", pair)
	if main.layout.guide.visible and main.layout.guide.get_combined_minimum_size().y > main.layout.guide.size.y + 0.5:
		print("OVERFLOW ", name, " guide ", main.layout.guide.get_combined_minimum_size(), " size ", main.layout.guide.size)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/layout-" + name + ".png"))
func _run() -> void:
	root.size = Vector2i(1280, 720)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	main.sounds.set_enabled(false)
	await _snapshot("packing")
	main._toggle_story()
	await _snapshot("story")
	main._toggle_story()
	main._select("sword")
	await _snapshot("details")
	main._cancel()
	main.session.submit({"type":"start"})
	main.session.skip_playback()
	await _snapshot("battle")
	var state: Dictionary = main.session.display_snapshot()
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main.session.submit({"type":"use_item", "uid":"sword"})
	main.session.skip_playback()
	await _snapshot("reward")
	main._reward_action("reward_skip")
	main.session.skip_playback()
	main._primary_action()
	main.session.skip_playback()
	await _snapshot("event")
	main._event_action("event_take")
	main.session.skip_playback()
	await _snapshot("event-take")
	main._primary_action()
	main.session.skip_playback()
	await _snapshot("route")
	var ev: Dictionary = main.session.display_snapshot().event
	main._choose_route(main.session.display_snapshot().config.routes[1].id)
	main.session.skip_playback()
	await _snapshot("frost")
	main.session.stash("hat")
	main.session.place(ev.uid, Vector2i(1,2), 0)
	main.session.submit({"type":"start"})
	main.session.skip_playback()
	await _snapshot("arang")
	main.session.submit({"type":"resolve_encounter"})
	main.session.skip_playback()
	await _snapshot("ending")
	main._event_action("event_continue")
	main.session.skip_playback()
	await _snapshot("complete")
	main.queue_free()
	await process_frame
	print("LAYOUT CAPTURE: DONE")
	quit()
