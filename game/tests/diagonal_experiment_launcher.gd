extends SceneTree
## Local-only isolated playtest, excluded from release packs.

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = "res://tests/fixtures/diagonal-experiment.json"
	main.save_enabled = false
	root.add_child(main)
	main.labels.chapter.size.x = 330
	var banner := Label.new()
	banner.name = "ExperimentBanner"
	banner.text = "대각선 실험 · 저장 안 함"
	banner.position = Vector2(605, 14)
	banner.size = Vector2(160, 24)
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", Color("e9997b"))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.layout.add_child(banner)
	if main.inventory == null:
		push_error("대각선 실험 콘텐츠를 열지 못했습니다.")
		quit(1)
		return
	if main.session.save_service != null:
		push_error("실험 모드는 저장 서비스를 사용하면 안 됩니다.")
		quit(1)
		return
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/diagonal-experiment-screen.png"))
		print("DIAGONAL EXPERIMENT CAPTURE: PASS")
		quit(0)
