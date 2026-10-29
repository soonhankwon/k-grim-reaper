extends RefCounted
## Local playtest setup; never reads a player save.

const CONTENT_PATH := "res://tests/fixtures/multiplier-experiment.json"

static func create(parent: Node) -> Control:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = CONTENT_PATH
	main.save_enabled = false
	parent.add_child(main)
	main.labels.chapter.size.x = 330
	var banner := Label.new()
	banner.name = "ExperimentBanner"
	banner.text = "배율 실험 · 저장 안 함"
	banner.position = Vector2(605, 14)
	banner.size = Vector2(160, 24)
	banner.add_theme_font_size_override("font_size", 13)
	banner.add_theme_color_override("font_color", Color("e9997b"))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.layout.add_child(banner)
	return main
