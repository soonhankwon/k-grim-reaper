extends SceneTree
const Experiment = preload("res://tests/yagwang_experiment_setup.gd")

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var main := Experiment.create(root)
	if main == null:
		push_error("야광귀 시제품 데이터를 열지 못했습니다.")
		quit(1)
		return
	if "--intro-capture" in OS.get_cmdline_user_args():
		if not main.session.submit({"type":"start"}).is_empty():
			push_error("야광귀 등장 화면 준비 실패")
			quit(1)
			return
		main.session.playback.queue._process(0)
		if main.session.playback.queue._current._tween != null: main.session.playback.queue._current._tween.pause()
		await process_frame
		main.cinematics.set_progress(0.86)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yagwang-intro-en.png"))
		print("YAGWANG INTRO CAPTURE: PASS")
		main.session.skip_playback()
		main.queue_free()
		await process_frame
		quit(0)
	elif "--preview-capture" in OS.get_cmdline_user_args():
		main._select("sandals")
		main.board.hover_cell = Vector2i(4, 1)
		main.board.synergy_changed.emit()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yagwang-placement-preview.png"))
		print("YAGWANG PREVIEW CAPTURE: PASS")
		quit(0)
	elif "--battle-capture" in OS.get_cmdline_user_args():
		if not main.session.stash("hat").is_empty() or not main.session.place("sieve", Vector2i(0, 0), 0).is_empty() or not main.session.submit({"type":"start"}).is_empty():
			push_error("시제품 전투 화면 준비 실패")
			quit(1)
			return
		main.session.skip_playback()
		main._activate_item("sieve")
		main.session.skip_playback()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yagwang-battle-screen.png"))
		print("YAGWANG BATTLE CAPTURE: PASS")
		quit(0)
	elif "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/yagwang-experiment-screen.png"))
		print("YAGWANG CAPTURE: PASS")
		quit(0)
