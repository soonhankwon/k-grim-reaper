extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	check(VfxPlayer.validate(main.vfx.data).is_empty(), "shipping VFX definitions validate")
	var bad: Dictionary = main.vfx.data.duplicate(true)
	bad.profiles.ink.count = 1000
	check(not VfxPlayer.validate(bad).is_empty(), "particle count bound is enforced")
	bad = main.vfx.data.duplicate(true)
	bad.rules[0].profile = "missing"
	check(not VfxPlayer.validate(bad).is_empty(), "unknown profile rejected")
	bad = main.vfx.data.duplicate(true)
	bad.rules.append(bad.rules[0].duplicate(true))
	check(not VfxPlayer.validate(bad).is_empty(), "duplicate rules rejected")
	var state: Dictionary = main.session.display_snapshot()
	state.phase = "route"
	state.route = {"choice":"", "step":0}
	main.session.reset(main.inventory, state)
	check(main.session.submit({"type":"choose_route", "route_id":state.config.routes[0].id}).is_empty(), "route selection accepted")
	main.session.playback.queue._process(0)
	check(main.vfx.active_rule.get("profile") == "frost" and not main.vfx.burst.visible, "frost prepared without early particles")
	check(main.session.display_snapshot().phase == "route", "hazard snapshot remains hidden before impact")
	var command: CombatEventCommand = main.session.playback.queue._current
	command._impact()
	check(main.vfx.burst.visible and main.vfx.impacted and main.board.hazards.size() == 1, "frost bursts at the hazard snapshot")
	main.session.playback._update_feedback_progress(0.8)
	check(main.vfx.elapsed > 0.0, "frost advances from queue progress")
	main.session.skip_playback()
	check(not main.vfx.burst.visible and main.vfx.active_rule.is_empty() and main.vfx.elapsed == 0.0, "skip clears frost")
	main._reset_run()
	check(main.session.place("ring", Vector2i(1,1), 0).is_empty(), "place ring next to lantern")
	check(main.session.submit({"type":"start"}).is_empty(), "battle starts")
	main.session.skip_playback()
	var preview: CombatResolution = main.session.preview_end_turn()
	var guards := preview.events().filter(func(event): return event.kind == "guard" and event.get("effect_id", "") == "lantern_guard")
	check(guards.size() == 1, "actual turn simulation emits lantern guard")
	check(main.session.submit({"type":"end_turn"}).is_empty(), "turn end accepted")
	main.session.playback.queue._process(0)
	check(main.vfx.active_rule.get("profile") == "embers" and not main.vfx.burst.visible, "embers prepared at lantern guard")
	command = main.session.playback.queue._current
	command._impact()
	main.session.playback._update_feedback_progress(0.8)
	check(main.vfx.burst.visible and main.vfx.elapsed > 0.0, "embers begin at impact and advance")
	var time: float = main.vfx.elapsed
	command._impact()
	check(main.vfx.elapsed == time, "duplicate impact does not restart embers")
	main.session.skip_playback()
	check(main.session.display_snapshot() == preview.after() and not main.vfx.burst.visible, "skip settles predicted state and clears embers")
	main._reset_run()
	state = main.session.display_snapshot()
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	check(main.session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "winning attack accepted")
	main.session.skip_playback()
	state = main.session.display_snapshot()
	check(state.phase == "reward", "actual victory offers reward")
	var offer: String = state.reward.offer_id
	check(main.session.submit({"type":"reward_select", "offer_id":offer, "item_id":state.reward.candidates[0]}).is_empty(), "reward selection accepted")
	main.session.skip_playback()
	var uid: String = main.session.display_snapshot().reward.uid
	check(main.session.stash("hat").is_empty(), "make space for reward")
	check(main.session.place(uid, Vector2i(1,2), 1).is_empty(), "place actual reward")
	check(main.session.submit({"type":"reward_confirm", "offer_id":offer}).is_empty(), "reward confirmation accepted")
	main.session.playback.queue._process(0)
	check(main.vfx.active_rule.get("profile") == "gilded" and not main.vfx.burst.visible, "gilded effect waits for confirmation impact")
	command = main.session.playback.queue._current
	command._impact()
	check(main.vfx.burst.visible and main.session.display_snapshot().phase == "victory", "reward and gilded particles appear together")
	main.session.playback._update_feedback_progress(0.8)
	check(main.vfx.elapsed > 0.0, "gilded particles advance with queue")
	main._reset_run()
	check(not main.vfx.burst.visible and main.vfx.active_rule.is_empty(), "restart cancels particles")
	check(not main.vfx.begin_feedback({"kind":"reward_confirm", "source":"missing", "after":main.session.display_snapshot()}, main.session.display_snapshot()), "missing source cannot generate particles")
	var model := ItemCatalog.create_inventory()
	check(model.add_item("test_coin", model.definitions.coin, Vector2i(2,1)), "existing coin fits test inventory")
	var coin_state := CombatResolver.new(model).snapshot()
	coin_state.phase = "battle"
	var coin_result := CombatSimulator.resolve(coin_state, {"type":"use_item", "uid":"test_coin"})
	var coin_events := coin_result.events().filter(func(event): return event.kind == "guard" and event.get("effect_id", "") == "coin_use")
	check(coin_result.error.is_empty() and coin_events.size() == 1, "coin simulation emits its guard event")
	if not coin_events.is_empty():
		check(main.vfx.begin_feedback(coin_events[0], coin_state) and main.vfx.active_rule.get("profile") == "gilded", "existing coin effect maps to gilded particles")
		main.vfx.clear_feedback()
		main.session.playback.seconds_per_step = 0.0
		main.session.playback.reset(coin_state)
		main.session.playback.play(CombatResolution.new(coin_state, coin_events[0].after, [coin_events[0]]))
		main.session.playback.queue._process(0)
		check(not main.vfx.burst.visible and main.vfx.active_rule.is_empty(), "zero-duration playback does not start particles")
		main.session.playback.seconds_per_step = 0.16
	main.queue_free()
	await process_frame
	print("VFX TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
