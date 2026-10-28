extends SceneTree
## Run externally against a release PCK in an empty directory.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(ContentLoader.SCHEMA_PATH) or not FileAccess.file_exists(ItemCatalog.DEFAULT_PATH):
		push_error("Export omitted content JSON or schema")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/baseline.json"):
		push_error("Test fixture must not ship in release content")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/space-experiment.json"):
		push_error("Experimental item must not ship in release content")
		quit(1)
		return
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	await process_frame
	if main.inventory == null or main.session.display_snapshot().is_empty():
		push_error("Exported main scene failed to load content")
		quit(1)
		return
	if main.inventory.config.routes.size() != 2 or not FileAccess.file_exists(PresentationArt.INDEX) or not PresentationArt.actor_region("reaper").has_area() or not PresentationArt.item_region("sword").has_area():
		push_error("Export omitted route data or retro art atlas")
		quit(1)
		return
	if not main.layout.guide.visible or main.layout.guide.heading.text != "보따리 준비":
		push_error("Exported first-play guide failed to display")
		quit(1)
		return
	if main.inventory.config.events.size() != 1 or StoryBook.load_entries().size() != 4 or main.layout.buttons.story.text != "사연 1":
		push_error("Export omitted initial narrative")
		quit(1)
		return
	print("EXPORT CONTENT: PASS — ", main.inventory.definitions.size(), " definitions")
	main.queue_free()
	await process_frame
	quit(0)
