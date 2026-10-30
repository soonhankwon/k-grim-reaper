extends RefCounted

const CONTENT_PATH := "res://tests/fixtures/yagwang-experiment.json"
const RULES_PATH := "res://tests/fixtures/yagwang-rules.json"
const Rules = preload("res://tests/yagwang_rules.gd")
const Presenter = preload("res://tests/yagwang_presenter.gd")

static func settings() -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null: return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if Rules.validate(data).is_empty() else {}

static func create(parent: Node) -> Control:
	var config := settings()
	var loaded := ContentLoader.new().load_json(CONTENT_PATH)
	if config.is_empty() or not loaded.error.is_empty(): return null
	if int(config.exposed_rows) > int(loaded.raw.rules[0].grid_height): return null
	var tags := ContentLoader.index(loaded.raw.tags)
	if not tags.has(config.target_tag) or not tags.has(config.lure_tag) or config.target_tag == config.lure_tag: return null
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = CONTENT_PATH
	main.save_enabled = false
	parent.add_child(main)
	if main.inventory == null or not main.session.install_unsaved_ruleset(Rules.new(config)):
		main.queue_free()
		return null
	main.story_entries.clear()
	var presenter := Presenter.new()
	presenter.name = "YagwangPresenter"
	presenter.setup(main, config)
	main.layout.add_child(presenter)
	main.session.playback.bind_telegraph(presenter)
	main.session.reset(main.inventory)
	return main
