extends RefCounted
## Local scenario fixture; an explicit path is required to enable an isolated save.

const CONTENT_PATH := "res://tests/fixtures/arang-experiment.json"
const STORY_PATH := "res://tests/fixtures/arang-story.json"

static func load_resolution() -> Dictionary:
	var result := ContentLoader.new().load_json(CONTENT_PATH)
	if not result.error.is_empty() or result.raw.get("resolutions", []).is_empty(): return {}
	return result.raw.resolutions[0].duplicate(true)

static func create(parent: Node, slot := "") -> Control:
	if load_resolution().is_empty() or StoryBook.load_entries(STORY_PATH).is_empty(): return null
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = CONTENT_PATH
	main.story_path = STORY_PATH
	main.save_enabled = not slot.is_empty()
	if main.save_enabled: main.save_path = slot
	parent.add_child(main)
	if main.inventory == null or (slot.is_empty() and main.session.save_service != null):
		main.queue_free()
		return null
	var banner := Label.new()
	banner.text = "아랑전설 시연 · 저장 안 함" if slot.is_empty() else "아랑전설 시연 · 별도 저장"
	banner.position = Vector2(605, 14)
	banner.size = Vector2(160, 24)
	banner.add_theme_font_size_override("font_size", 12)
	banner.add_theme_color_override("font_color", Color("e9997b"))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.layout.add_child(banner)
	return main
