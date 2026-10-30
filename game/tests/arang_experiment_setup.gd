extends RefCounted
## Local scenario fixture; an explicit path is required to enable an isolated save.

const CONTENT_PATH := "res://tests/fixtures/arang-experiment.json"
const STORY_PATH := "res://tests/fixtures/arang-story-english.json"
const TEXT_PATH := "res://tests/fixtures/arang-english.json"

static func load_resolution() -> Dictionary:
	var result := ContentLoader.new().load_json(CONTENT_PATH)
	if not result.error.is_empty() or result.raw.get("resolutions", []).is_empty(): return {}
	return result.raw.resolutions[0].duplicate(true)

static func create(parent: Node, slot := "") -> Control:
	if load_resolution().is_empty() or StoryBook.load_entries(STORY_PATH).is_empty(): return null
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = CONTENT_PATH
	main.story_path = STORY_PATH
	main.presentation_text_path = TEXT_PATH
	main.save_enabled = not slot.is_empty()
	if main.save_enabled: main.save_path = slot
	parent.add_child(main)
	if main.inventory == null or (slot.is_empty() and main.session.save_service != null):
		main.queue_free()
		return null
	main.labels.edition.text = "Arang Demo" if slot.is_empty() else "Arang Demo · Saved"
	return main
