extends SceneTree
## Run externally against a release PCK in an empty directory.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var legacy_name := "".join([String.chr(0xc800), String.chr(0xc2b9), " ", String.chr(0xbcf4), String.chr(0xb530), String.chr(0xb9ac), " — ", String.chr(0xccab), " ", String.chr(0xc778), String.chr(0xb3c4)])
	if ProjectSettings.get_setting("application/config/name") != legacy_name or ProjectSettings.globalize_path("user://").trim_suffix("/").get_file() != legacy_name:
		push_error("Export changed the existing user data directory")
		quit(1)
		return
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
	var launcher := (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	launcher.save_enabled = false
	root.add_child(launcher)
	await process_frame
	await process_frame
	if launcher.game != null or launcher.intro == null:
		push_error("Export omitted the introduction screen")
		quit(1)
		return
	launcher.intro.action_button.pressed.emit()
	await process_frame
	var main: Control = launcher.game
	if main == null or main.session.display_snapshot().get("phase", "") != "packing":
		push_error("Exported introduction did not open preparation")
		quit(1)
		return
	var bitmap_font: FontFile = main.theme.default_font.base_font
	if bitmap_font == null or not bitmap_font.data.is_empty() or not bitmap_font.has_char(0x2192) or bitmap_font.get_texture_count(0, Vector2i(16, 0)) == 0:
		push_error("Export omitted the bitmap font or its UI glyphs")
		quit(1)
		return
	if not ResourceLoader.exists("res://assets/visuals/vfx-particles-v1.png") or not ResourceLoader.exists("res://shaders/ink_dissolve.gdshader") or not ResourceLoader.exists("res://shaders/ink_wipe.gdshader") or PresentationArt.visual_texture("res://assets/visuals/arang-memory-v1.png") == null or main.cinematics.entries.get("boss_intros", {}).is_empty() or not PresentationSound.CUES.has("snap"):
		push_error("Export omitted cinematic shaders, still, audio or presentation data")
		quit(1)
		return
	var intros: Dictionary = main.cinematics.entries.get("boss_intros", {})
	if intros.get("spirit_2", {}).get("title", "") != "ARANG" or intros.get("yagwang", {}).get("title", "") != "YAGWANGGWI" or main.vfx.data.get("profiles", {}).size() != 4 or main.vfx.data.get("rules", []).size() != 5:
		push_error("Export omitted English titles or particle texture")
		quit(1)
		return
	if main.inventory == null or main.session.display_snapshot().is_empty():
		push_error("Exported main scene failed to load content")
		quit(1)
		return
	if main.inventory.config.routes.size() != 2 or not FileAccess.file_exists(PresentationArt.INDEX) or not PresentationArt.actor_region("reaper").has_area() or not PresentationArt.item_region("sword").has_area():
		push_error("Export omitted route data or retro art atlas")
		quit(1)
		return
	if not PresentationArt.BACKGROUND.resource_path.ends_with("afterlife-ink-v2.png") or not PresentationArt.ITEMS.resource_path.ends_with("items-360-v1.png") or not PresentationArt.ACTORS.resource_path.ends_with("actors-woodcut-v2.png"):
		push_error("Exported game is not using the new visual assets")
		quit(1)
		return
	if not PresentationArt.actor_texture("spirit_1").resource_path.ends_with("actors-360-v1.png") or not PresentationArt.actor_texture("spirit_2").resource_path.ends_with("actors-360-v1.png") or not PresentationArt.background_for_actor("spirit_1").resource_path.ends_with("arang-office-v1.png") or not PresentationArt.background_for_actor("spirit_2").resource_path.ends_with("arang-bamboo-v1.png"):
		push_error("Export omitted the stage-one character or background resources")
		quit(1)
		return
	if main.inventory.config.resolutions.size() != 1:
		push_error("Export omitted the stage-one resolution")
		quit(1)
		return
	if main.inventory.config.hazards.size() != 1 or main.inventory.config.hazards[0].cells.size() != 5:
		push_error("Export omitted the stage-one grid hazard")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/diagonal-experiment.json"):
		push_error("Diagonal experiment must not ship in release content")
		quit(1)
		return
	for path in ["res://assets/visuals/yagwang-winter-v1.png", "res://assets/visuals/yagwang-boss-v1.png", "res://assets/visuals/yagwang-sieve-v1.png"]:
		if ResourceLoader.exists(path):
			push_error("Experimental art must not ship in release content")
			quit(1)
			return
	if FileAccess.file_exists("res://tests/fixtures/yagwang-experiment.json") or FileAccess.file_exists("res://tests/fixtures/yagwang-rules.json"):
		push_error("Yagwang experiment must not ship in release content")
		quit(1)
		return
	if FileAccess.file_exists("res://tests/fixtures/multiplier-experiment.json"):
		push_error("Multiplier experiment must not ship in release content")
		quit(1)
		return
	if not main.layout.guide.visible or main.layout.guide.heading.text != "Prepare Your Bag":
		push_error("Exported first-play guide failed to display")
		quit(1)
		return
	main._select("seal")
	main._place("seal", Vector2i(2,1), 0)
	main._select("sword")
	if main.inventory.action_result("sword").power != 16 or EffectText.enemy_reactions(main.inventory.config.encounters[2].reactions).size() != 1:
		push_error("Export omitted the production diagonal multiplier or enemy reaction")
		quit(1)
		return
	if not main.labels.synergy_state.text.contains("Gold: add") or not main.labels.connections.text.contains("Sealing Talisman → Sain Sword"):
		push_error("Exported synergy connection did not reflect the displayed layout")
		quit(1)
		return
	var breakdown: SynergyBreakdown = main.layout.synergy_breakdown
	if breakdown.rows.is_empty() or breakdown.rows[0].base != 6 or breakdown.rows[0].amount != 16 or breakdown.rows[0].bonuses[0].source != "seal" or breakdown.rows[0].multipliers[0].source != "ring":
		push_error("Exported synergy source icons do not match the calculated attack")
		quit(1)
		return
	if main.inventory.config.events.size() != 1 or StoryBook.load_entries().size() != 4 or main.layout.buttons.story.text != "Story 1":
		push_error("Export omitted initial narrative")
		quit(1)
		return
	var route_view: Dictionary = main.session.display_snapshot()
	route_view.phase = "route"
	main.layout.routes.refresh(route_view, false)
	await process_frame
	await process_frame
	if main.layout.routes.choices.size() != 2 or main.layout.routes.choices[0].motif != "bamboo" or main.layout.routes.choices[1].motif != "pond" or not main.layout.routes.choices[1].reaction_label.text.contains("Attack 2 (you)"):
		push_error("Export omitted route card art or enemy intent details")
		quit(1)
		return
	print("EXPORT CONTENT: PASS — ", main.inventory.definitions.size(), " definitions")
	launcher.queue_free()
	await process_frame
	quit(0)
