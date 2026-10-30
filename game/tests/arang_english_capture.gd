extends SceneTree
const Experiment = preload("res://tests/arang_experiment_setup.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	var folder := ProjectSettings.globalize_path("res://../build/arang-english-capture/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var main := Experiment.create(root, folder.path_join("run.json"))
	main.sounds.set_enabled(false)
	main.story_forced = true
	main._refresh_details()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-english-saved.png"))
	main.queue_free()
	await process_frame
	print("ARANG ENGLISH CAPTURE: PASS")
	quit()
