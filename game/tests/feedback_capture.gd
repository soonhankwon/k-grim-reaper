extends SceneTree
## Optional real-renderer evidence; all gameplay uses an isolated in-memory run.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	main.session.playback.seconds_per_step = 0.6
	main._primary_action()
	main.session.skip_playback()
	main._activate_item("sword")
	var found := false
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if main.road.feedback_kind == "damage" and main.road.feedback_impact:
			found = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/combat-feedback-screen.png"))
			break
	if not found or main.session.display_snapshot().enemy_health != 12:
		push_error("Damage impact could not be captured with matching displayed health")
		quit(1)
		return
	main.queue_free()
	await process_frame
	print("FEEDBACK CAPTURE: PASS")
	quit(0)
