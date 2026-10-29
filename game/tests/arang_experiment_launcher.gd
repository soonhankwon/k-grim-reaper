extends SceneTree

const Experiment = preload("res://tests/arang_experiment_setup.gd")

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var slot := "user://saves/arang-experiment.json" if "--save" in OS.get_cmdline_user_args() else ""
	var main := Experiment.create(root, slot)
	if main == null:
		push_error("아랑전설 시연 데이터를 열지 못했습니다.")
		quit(1)
		return
	main.story_forced = true
	main._refresh_details()
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-experiment-screen.png"))
		print("ARANG EXPERIMENT CAPTURE: PASS")
		quit(0)
