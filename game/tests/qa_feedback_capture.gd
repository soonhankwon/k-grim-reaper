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
	main.session.submit({"type":"start"})
	main.session.skip_playback()
	var before: Dictionary = main.session.display_snapshot()
	var args := OS.get_cmdline_user_args()
	var uid := "hat" if "--guard" in args else "sword"
	var kind := "guard" if "--guard" in args else "damage"
	var outcome := CombatSimulator.resolve(before, {"type":"use_item", "uid":uid})
	var events := outcome.events().filter(func(event): return event.kind == kind)
	if events.is_empty():
		push_error("Missing combat event")
		quit(1)
		return
	var event: Dictionary = events[0]
	main.session.playback.reset(before)
	main.session.playback.play(CombatResolution.new(before, event.after, [event]))
	main.session.playback.queue._process(0)
	var command: CombatEventCommand = main.session.playback.queue._current
	if command._tween != null: command._tween.pause()
	command._impact()
	main.session.playback._update_feedback_progress(0.62)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/qa-" + kind + ".png"))
	main.session.skip_playback()
	main.queue_free()
	await process_frame
	print("QA FEEDBACK CAPTURE: ", kind)
	quit()
