extends SceneTree
## Optional real-renderer capture using an isolated, unsaved run.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	main._primary_action()
	main.session.skip_playback()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/turn-preview-screen.png"))
	if not main.layout.turn_preview.visible:
		push_error("Turn preview is not visible in capture")
		quit(1)
		return
	main.queue_free()
	await process_frame
	print("TURN PREVIEW CAPTURE: PASS")
	quit(0)
