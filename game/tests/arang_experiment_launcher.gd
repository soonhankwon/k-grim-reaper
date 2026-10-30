extends SceneTree

const DemoFlow = preload("res://tests/arang_demo_flow.gd")

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var slot := "user://saves/arang-experiment.json" if "--save" in OS.get_cmdline_user_args() else ""
	var flow := DemoFlow.new()
	flow.save_slot = slot
	flow.skip_intro = "--capture" in OS.get_cmdline_user_args()
	root.add_child(flow)
	if "--capture" in OS.get_cmdline_user_args():
		if flow.arang == null:
			push_error("Could not load the Arang demo data.")
			quit(1)
			return
		flow.arang.story_forced = true
		flow.arang._refresh_details()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-experiment-screen.png"))
		print("ARANG EXPERIMENT CAPTURE: PASS")
		quit(0)
