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
	if not PresentationArt.BACKGROUND.resource_path.ends_with("afterlife-ink-v2.png") or not PresentationArt.ITEMS.resource_path.ends_with("items-minhwa-v2.png") or not PresentationArt.ACTORS.resource_path.ends_with("actors-woodcut-v2.png"):
		push_error("Exported game is not using the new visual assets")
		quit(1)
		return
	if not PresentationArt.actor_texture("spirit_1").resource_path.ends_with("arang-actors-v1.png") or not PresentationArt.actor_texture("spirit_2").resource_path.ends_with("arang-actors-v1.png") or not PresentationArt.background_for_actor("spirit_1").resource_path.ends_with("arang-office-v1.png") or not PresentationArt.background_for_actor("spirit_2").resource_path.ends_with("arang-bamboo-v1.png"):
		push_error("Export omitted the stage-one character or background resources")
		quit(1)
		return
	if main.inventory.config.resolutions.size() != 1:
		push_error("Export omitted the stage-one resolution")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/diagonal-experiment.json"):
		push_error("Diagonal experiment must not ship in release content")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/multiplier-experiment.json"):
		push_error("Multiplier experiment must not ship in release content")
		quit(1)
		return
	if not main.layout.guide.visible or main.layout.guide.heading.text != "보따리 준비":
		push_error("Exported first-play guide failed to display")
		quit(1)
		return
	main._select("seal")
	main._place("seal", Vector2i(2,1), 0)
	main._select("sword")
	if not main.labels.synergy_state.text.contains("현재 연결") or not main.labels.connections.text.contains("봉인부 → 낡은 사인검"):
		push_error("Exported synergy connection did not reflect the displayed layout")
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
