extends SceneTree
const Experiment = preload("res://tests/yagwang_experiment_setup.gd")
const Rules = preload("res://tests/yagwang_rules.gd")
var checks := 0
var failures := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)

func _initialize() -> void:
	call_deferred("_run")

func submit(main: Control, request: Dictionary) -> String:
	var error: String = main.session.submit(request)
	if error.is_empty(): main.session.skip_playback()
	return error

func _run() -> void:
	var settings := Experiment.settings()
	check(not settings.is_empty() and Rules.validate(settings).is_empty(), "prototype settings validate")
	check(not Rules.validate({"target_tag":"x"}).is_empty(), "missing settings rejected")
	var bad := settings.duplicate(true)
	bad.dawn_turn = 1.5
	check(not Rules.validate(bad).is_empty(), "fractional turns rejected")
	var catalog := ContentLoader.new().load_json(Experiment.CONTENT_PATH)
	check(catalog.error.is_empty(), "prototype catalog validates")
	var tampered: Dictionary = catalog.raw.duplicate(true)
	tampered.art.icons.sieve.texture_path = "res://assets/visuals/../missing.png"
	check(not ContentLoader.new().validate(tampered).error.is_empty(), "visual path traversal rejected")
	tampered = catalog.raw.duplicate(true)
	tampered.art.actors.yagwang.background_path = "res://assets/visuals/missing.png"
	check(not ContentLoader.new().validate(tampered).error.is_empty(), "missing visual resource rejected")
	tampered = catalog.raw.duplicate(true)
	tampered.art.icons.sieve.background_path = "res://assets/visuals/yagwang-winter-v1.png"
	check(not ContentLoader.new().validate(tampered).error.is_empty(), "background path rejected on item icon")
	check(ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH).raw.items.size() == 12, "shipping catalog remains unchanged")
	var main := Experiment.create(root)
	check(main != null, "prototype launches")
	if main == null:
		quit(1)
		return
	await process_frame
	check(main.session.save_service == null, "prototype has no save service")
	check(main.cinematics.z_index > main.layout.get_node("YagwangPresenter").z_index, "cinematic overlays target panel and experiment banner")
	check(main.layout.background_texture.resource_path.ends_with("yagwang-winter-v1.png"), "winter backdrop used in game")
	check(main.road.enemy_visual.texture_path.ends_with("yagwang-boss-v1.png") and PresentationArt.visual_texture(main.road.enemy_visual.texture_path) != null, "boss sprite used in game")
	check(main.inventory.definition("sieve").icon.texture_path.ends_with("yagwang-sieve-v1.png") and PresentationArt.visual_texture(main.inventory.definition("sieve").icon.texture_path) != null, "sieve sprite used in game")
	check(PresentationArt.visual_texture(main.road.enemy_visual.texture_path).get_image().detect_alpha() != Image.ALPHA_NONE and PresentationArt.visual_texture(main.inventory.definition("sieve").icon.texture_path).get_image().detect_alpha() != Image.ALPHA_NONE, "sprites preserve alpha")
	check(not main.inventory.is_packed("sieve") and main.inventory.definition("sieve").footprint.size() == 4, "2x2 lure begins in stash")
	var status: Label = main.layout.get_node("YagwangPresenter/YagwangPanel/ScrollContainer/YagwangStatus")
	check(status.text.contains("Straw Shoes"), "marked target disclosed before battle")
	check(main.board.threat_cells.size() == 5 and main.board.target_cells == [Vector2i(4,2), Vector2i(4,3)] and not main.board.target_preview, "bottom row and exposed multi-cell footwear are marked")
	var pure := Rules.new(settings)
	var clean_view: Dictionary = main.session.display_snapshot()
	check(pure.target(clean_view) == "sandals", "exposed footwear is prioritized")
	var alternative := clean_view.duplicate(true)
	alternative.packed_items.sandals.cells = [Vector2i(4,1), Vector2i(4,2)]
	check(pure.target(alternative) == "lantern", "hidden footwear yields the lowest other item")
	check(main.inventory.placement_error("sandals", Vector2i(3,3), 1).is_empty(), "rotated footwear fits the bottom row")
	var rotated := clean_view.duplicate(true)
	rotated.packed_items = main.inventory.preview("sandals", Vector2i(3,3), 1).snapshot
	check(pure.target(rotated) == "sandals", "rotated multi-cell footprint is used for exposure")
	var hidden_only := alternative.duplicate(true)
	hidden_only.packed_items = {"sandals": alternative.packed_items.sandals}
	check(pure.target(hidden_only).is_empty(), "hidden footwear is not selected when no other object exists")
	var no_target := pure.resolve(clean_view, {"type":"start"}).after()
	no_target.packed_items = hidden_only.packed_items
	no_target.puzzle.target = ""
	var no_target_result: CombatResolution = pure.resolve(no_target, {"type":"end_turn"})
	check(no_target_result.error.is_empty() and no_target_result.after().puzzle.remaining == settings.countdown and no_target_result.after().puzzle.stolen.is_empty(), "no-target turns do not decrement or steal")
	var tie := alternative.duplicate(true)
	tie.packed_items = {"z": {"tags": [], "cells": [Vector2i(0,3)]}, "a": {"tags": [], "cells": [Vector2i(1,3)]}, "sandals": alternative.packed_items.sandals}
	check(pure.target(tie) == "a", "ties are resolved deterministically by instance id")
	var wider_settings := settings.duplicate(true)
	wider_settings.exposed_rows = 2
	check(Rules.new(wider_settings).target(alternative) == "sandals", "exposure depth is data driven")
	var invalid_settings := settings.duplicate(true)
	invalid_settings.exposed_rows = 0
	check(not Rules.validate(invalid_settings).is_empty(), "zero exposure rows rejected")
	main._select("sandals")
	main.board.hover_cell = Vector2i(4,1)
	main.board.synergy_changed.emit()
	check(status.text.contains("Preview") and status.text.contains("Soul Lantern") and main.board.target_preview, "valid preview shows the changed target")
	check(main.session.display_snapshot() == clean_view and main.board.target_cells == [Vector2i(2,2), Vector2i(2,3)], "preview does not commit and marks predicted target")
	main.board.hover_cell = Vector2i(3,0)
	main.board.synergy_changed.emit()
	check(not main.board.target_preview and status.text.contains("Straw Shoes"), "invalid placement keeps current target")
	main.board.hover_cell = Vector2i(4,1)
	main.board.synergy_changed.emit()
	check(main.session.place("sandals", Vector2i(4,1), 0).is_empty(), "footwear can be moved clear of the bottom row")
	check(status.text.contains("Current") and status.text.contains("Soul Lantern") and not main.board.target_preview, "confirmed target updates")
	check(submit(main, {"type":"start"}).is_empty() and main.session.display_snapshot().puzzle.target == "lantern", "battle locks in the previewed target")
	for i in 2: check(submit(main, {"type":"end_turn"}).is_empty(), "protected footwear scenario advances")
	var theft_preview: CombatResolution = main.session.preview_end_turn()
	check(theft_preview.after().puzzle.stolen == "lantern" and theft_preview.after().packed_items.has("sandals"), "predicted theft preserves protected footwear")
	var theft_events := theft_preview.events()
	var stolen_event: Dictionary = theft_events.filter(func(event): return event.kind == "item_stolen")[0]
	var penalty_event: Dictionary = theft_events.filter(func(event): return event.kind == "energy_penalty")[0]
	check(stolen_event.cause_id > 0 and penalty_event.cause_id == stolen_event.id, "theft and penalty preserve their causal event ids")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot() == theft_preview.after(), "protected footwear preview equals actual theft")
	check(main.inventory.is_packed("sandals") and not main.inventory.is_packed("lantern") and main.board.target_cells.is_empty(), "fallback item is removed and marker clears")
	check(not main.layout.get_node("TargetThread").visible, "target thread clears when the item is stolen")
	main._reset_run()
	check(main.session.display_snapshot() == clean_view and status.text.contains("Straw Shoes"), "restart restores exposed starting layout")
	for viewport_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = viewport_size
		await process_frame
		check(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(status.get_global_rect()), "status stays within viewport")
	root.size = Vector2i(1280,720)
	await process_frame
	var available := false
	for y in 3:
		for x in 4: available = available or main.inventory.placement_error("sieve", Vector2i(x,y), 0).is_empty()
	check(not available, "no 2x2 slot exists without rearranging or stashing gear")
	check(main.session.stash("hat").is_empty() and main.session.place("sieve", Vector2i(0,0), 0).is_empty(), "lure can replace hat")
	var before_start: Dictionary = main.session.display_snapshot()
	check(main.session.submit({"type":"start"}).is_empty(), "battle starts")
	check(main.session.is_busy() and main.session.display_snapshot() == before_start, "playback starts from displayed pre-action state")
	check(not main.session.submit({"type":"start"}).is_empty(), "duplicate input rejected during playback")
	main.session.skip_playback()
	var view: Dictionary = main.session.display_snapshot()
	check(view.puzzle.target == "sandals" and view.puzzle.remaining == 3, "footwear marked before enemy action")
	var target_thread: Line2D = main.layout.get_node("TargetThread")
	check(target_thread.visible and target_thread.points.size() == 21 and target_thread.modulate.a == 1.0, "committed target is connected to the boss with a visible thread")
	var presenter: Control = main.layout.get_node("YagwangPresenter")
	check(presenter.begin_thread_feedback({"kind":"target_marked"}) and target_thread.modulate.a == 0.0, "thread begins hidden for the target event")
	presenter.set_thread_progress(0.75)
	check(is_equal_approx(target_thread.modulate.a, 0.5), "thread lights according to playback progress")
	presenter.clear_thread_feedback()
	check(target_thread.modulate.a == 1.0 and target_thread.visible, "thread settles after cancellation or completion")
	check(status.text.contains("Straw Shoes") and status.text.contains("3 actions") and status.text.contains("6"), "target and counters visible")
	var preview: CombatResolution = main.session.preview_end_turn()
	check(preview.error.is_empty() and preview.after().puzzle.remaining == 2 and preview.after().health == 23, "turn preview includes attack and countdown")
	check(main.session.display_snapshot() == view, "preview never mutates display state")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot() == preview.after(), "preview matches committed turn")
	var lure_before: Dictionary = main.session.display_snapshot()
	var lure_result: CombatResolution = Rules.new(settings).resolve(lure_before, {"type":"use_item", "uid":"sieve"})
	var lure_events := lure_result.events()
	check(lure_events.size() == 2 and lure_events[0].after.puzzle.stun == 0 and lure_events[1].after.puzzle.stun == 1 and lure_events[1].cause_id == lure_events[0].id, "lure playback applies effect at the causal event")
	main._activate_item("sieve")
	check(main.session.is_busy(), "clicking the lure submits through the session")
	main.session.skip_playback()
	view = main.session.display_snapshot()
	check(view.energy == 2 and view.puzzle.stun == 1 and view.puzzle.lure_used, "lure consumes energy and queues one cancelled intent")
	check(not main.session.submit({"type":"use_item", "uid":"sieve"}).is_empty(), "lure is once per battle")
	check(main.labels.intent.text.contains("cancelled") and main.layout.intent_icon.operation == "counting", "cancelled intent and counting icon are visible")
	preview = main.session.preview_end_turn()
	check(preview.after().health == view.health and preview.after().puzzle.remaining == 2 and preview.events().any(func(e): return e.kind == "intent_cancelled"), "lure cancels damage and pauses theft countdown")
	check(preview.events().filter(func(e): return e.kind == "turn_started")[0].after.puzzle.stun == 0, "next-turn playback no longer displays expired stun")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot() == preview.after(), "lure preview matches action")
	check(main.layout.intent_icon.operation == "damage", "normal intent icon returns when counting expires")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot().puzzle.remaining == 1, "countdown resumes")
	preview = main.session.preview_end_turn()
	check(preview.after().puzzle.stolen == "sandals" and preview.after().energy == 2 and not preview.after().packed_items.has("sandals"), "preview includes theft and energy penalty")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot() == preview.after(), "theft preview matches committed turn")
	view = main.session.display_snapshot()
	check(main.inventory.items.sandals.origin == Vector2i(-1,-1) and not view.packed_items.has("sandals"), "stolen gear disabled consistently in model and view")
	check(not main.session.place("sandals", Vector2i(4,2), 0).is_empty(), "cannot move stolen gear during battle")
	check(submit(main, {"type":"end_turn"}).is_empty(), "battle reaches final turn")
	preview = main.session.preview_end_turn()
	check(preview.after().phase == "victory" and preview.after().packed_items.has("sandals") and preview.after().inventory_items.sandals.origin == Vector2i(4,2), "dawn victory restores stolen gear")
	check(submit(main, {"type":"end_turn"}).is_empty() and main.session.display_snapshot() == preview.after(), "dawn preview matches playback")
	check(main.inventory.is_packed("sandals"), "committed inventory restores item")
	check(submit(main, {"type":"advance"}).is_empty() and main.session.display_snapshot().phase == "complete", "victory completes scenario")
	main._reset_run()
	check(main.session.display_snapshot().phase == "packing" and main.session.save_service == null, "restart resets isolated battle")
	check(main.layout.background_texture.resource_path.ends_with("yagwang-winter-v1.png") and main.road.enemy_visual.texture_path.ends_with("yagwang-boss-v1.png"), "experiment art survives reset")
	check(main.session.stash("sandals").is_empty(), "footwear can be stashed")
	check(submit(main, {"type":"start"}).is_empty() and main.session.display_snapshot().puzzle.target == "lantern", "lowest packed item becomes fallback target")
	main._reset_run()
	check(submit(main, {"type":"start"}).is_empty(), "second battle starts")
	for i in 3:
		check(submit(main, {"type":"use_item", "uid":"sword"}).is_empty(), "early attack succeeds")
		check(submit(main, {"type":"use_item", "uid":"bell"}).is_empty(), "early second attack succeeds")
		check(submit(main, {"type":"end_turn"}).is_empty(), "unprotected countdown advances")
	check(main.session.display_snapshot().puzzle.stolen == "sandals", "theft occurs without lure")
	var fatal: Dictionary = main.session.display_snapshot().duplicate(true)
	fatal.turn = settings.dawn_turn
	fatal.health = 1
	fatal.guard = 0
	var fatal_result: CombatResolution = Rules.new(settings).resolve(fatal, {"type":"end_turn"})
	check(fatal_result.after().phase == "defeat" and not fatal_result.events().any(func(e): return e.kind == "victory"), "fatal final attack defeats player before dawn")
	for i in 4:
		if main.session.display_snapshot().phase != "battle": break
		check(submit(main, {"type":"use_item", "uid":"sword"}).is_empty(), "sword attack succeeds")
		if main.session.display_snapshot().phase == "battle": check(submit(main, {"type":"end_turn"}).is_empty(), "attack build advances")
	check(main.session.display_snapshot().phase == "victory" and main.inventory.is_packed("sandals"), "combat victory also returns stolen gear")
	main._reset_run()
	check(main.session.submit({"type":"start"}).is_empty() and main.session.is_busy(), "restart test has an active queue")
	main._reset_run()
	await create_timer(0.4).timeout
	check(main.session.display_snapshot().phase == "packing" and not main.session.is_busy(), "restart cancels old experiment playback")
	check(main.session.submit({"type":"start"}).is_empty(), "scene exit test has an active queue")
	main.queue_free()
	await process_frame
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = SaveService.new(ProjectSettings.globalize_path("res://../build/yagwang-no-save.json"))
	check(not session.install_unsaved_ruleset(Rules.new(settings)), "custom rules cannot be installed with a save service")
	session.save_service = null
	check(session.install_unsaved_ruleset(Rules.new(settings)), "unsaved rules can be installed")
	var inv := ItemCatalog.create_inventory(Experiment.CONTENT_PATH)
	session.reset(inv)
	session.save_service = SaveService.new(ProjectSettings.globalize_path("res://../build/yagwang-no-save.json"))
	check(not session.submit({"type":"start"}).is_empty() and not session.place("hat", Vector2i(0,0), 0).is_empty() and not session.prepare_new(inv).is_empty(), "late save attachment cannot write custom state")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path("res://../build/yagwang-no-save.json")), "unsaved experiment wrote no file")
	session.queue_free()
	await process_frame
	print("YAGWANG TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
