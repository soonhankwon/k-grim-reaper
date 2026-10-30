extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	main.sounds.set_enabled(false)
	var state: Dictionary = main.session.display_snapshot()
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main.session.submit({"type":"use_item", "uid":"sword"})
	main.session.skip_playback()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/qa-rewards.png"))
	main.queue_free()
	await process_frame
	print("QA REWARD CAPTURE: PASS")
	quit()
