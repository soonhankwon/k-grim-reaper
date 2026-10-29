extends SceneTree
## Local-only experiment, excluded from release packs.

const Experiment = preload("res://tests/multiplier_experiment_setup.gd")

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var main := Experiment.create(root)
	if main.inventory == null or main.session.save_service != null:
		push_error("배율 실험을 저장 없이 열지 못했습니다.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if "--capture" in args or "--preview-capture" in args:
		main._select("seal" if "--preview-capture" in args else "sword")
		if "--preview-capture" in args:
			main.board.hover_cell = Vector2i(2,0)
			main.board.synergy_changed.emit()
			main.board.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var filename := "synergy-preview-screen.png" if "--preview-capture" in args else "multiplier-experiment-screen.png"
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/" + filename))
		print("MULTIPLIER EXPERIMENT CAPTURE: PASS")
		quit(0)
