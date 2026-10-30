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
	var fixture_main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	fixture_main.save_enabled = false
	fixture_main.content_path = "res://tests/fixtures/baseline.json"
	root.add_child(fixture_main)
	check(not fixture_main.cinematics.story_dialogue_enabled, "fixture catalogs cannot inherit shipping narrative through shared actor art")
	var fixture_event := {"kind":"battle_started", "after":fixture_main.session.display_snapshot()}
	check(not fixture_main.cinematics.begin_event(fixture_event), "shared guard art alone does not trigger the shipping dialogue")
	fixture_main.queue_free()
	# The first guard speaks during the recorded start event, before its snapshot is presented.
	check(main.session.submit({"type":"start"}).is_empty(), "guard battle starts")
	main.session.playback.queue._process(0)
	check(main.cinematics.mode == "dialogue" and main.cinematics.data.speaker == "Terrified Guard", "guard warns of the bamboo before combat")
	check(main.session.display_snapshot().phase == "packing" and main.session.state_snapshot().phase == "battle", "guard dialogue does not reveal the committed battle snapshot early")
	check(not main.session.submit({"type":"start"}).is_empty(), "dialogue blocks duplicate input")
	main.session.skip_playback()
	check(main.session.display_snapshot().phase == "battle" and not main.cinematics.visible, "skip reconciles and clears guard dialogue")
	var guard_state: Dictionary = main.session.display_snapshot()
	guard_state.enemy_health = 1
	main.session.reset(main.inventory, guard_state)
	check(main.session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "guard defeat submitted")
	for i in 20:
		main.session.playback.queue._process(0)
		var cmd: CombatEventCommand = main.session.playback.queue._current
		if cmd == null: break
		if cmd._event.kind == "victory": break
		if cmd._tween != null: cmd._tween.kill()
		cmd._impact()
		cmd._complete()
	check(main.cinematics.mode == "dialogue" and main.cinematics.data.text.contains("grove"), "guard victory leads to the grove")
	check(main.session.display_snapshot().phase == "battle" and main.session.state_snapshot().phase == "reward", "guard victory dialogue does not reveal the reward early")
	main.session.skip_playback()
	check(main.session.display_snapshot().phase == "reward" and not main.cinematics.visible, "skipping guard victory shows the reward")
	# Restart and zero-duration playback must not leave dialogue or delayed impacts behind.
	guard_state.phase = "packing"
	guard_state.enemy_health = guard_state.config.encounters[0].hp
	guard_state.used = {}
	main.session.reset(main.inventory, guard_state)
	check(main.session.submit({"type":"start"}).is_empty(), "dialogue restart case starts")
	main.session.playback.queue._process(0)
	var stale: CombatEventCommand = main.session.playback.queue._current
	main.session.reset(main.inventory, guard_state)
	stale._impact()
	check(not main.cinematics.visible and main.session.display_snapshot().phase == "packing", "reset cancels dialogue and ignores late impact")
	check(main.session.submit({"type":"start"}).is_empty(), "missing dialogue completion case starts")
	main.session.playback.queue._process(0)
	main.session.playback.queue._process(4.1)
	check(not main.cinematics.visible and not main.session.is_busy() and main.session.display_snapshot().phase == "battle", "watchdog clears dialogue and shows committed state")
	main.session.reset(main.inventory, guard_state)
	main.session.playback.seconds_per_step = 0.0
	check(main.session.submit({"type":"start"}).is_empty(), "zero-duration dialogue case starts")
	main.session.playback.queue._process(0)
	main.session.playback.queue._process(0)
	check(main.session.display_snapshot().phase == "battle" and not main.cinematics.visible and not main.session.is_busy(), "zero-duration dialogue completes immediately")
	main.session.playback.seconds_per_step = 0.16
	main.session.reset(main.inventory, guard_state)
	check(main.session.submit({"type":"start"}).is_empty(), "natural guard dialogue starts")
	await create_timer(3.7).timeout
	check(main.session.display_snapshot().phase == "battle" and not main.cinematics.visible and not main.session.is_busy(), "guard dialogue completes before watchdog timeout")
	var route_state: Dictionary = main.session.display_snapshot()
	route_state.phase = "route"
	route_state.route = {"choice":"", "step":0}
	main.session.reset(main.inventory, route_state)
	check(main.session.submit({"type":"choose_route", "route_id":route_state.config.routes[0].id}).is_empty(), "route to frost is accepted")
	main.session.playback.queue._process(0)
	check(main.session.playback._frost and main.board.frost_progress == 0.0, "frost transition belongs to the queued route event")
	var frost_command: CombatEventCommand = main.session.playback.queue._current
	frost_command._impact()
	main.session.playback._update_feedback_progress(0.75)
	check(main.board.hazards.size() == 1 and is_equal_approx(main.board.frost_progress, 0.5), "displayed frost grows after the matching snapshot")
	main.session.skip_playback()
	check(main.board.frost_progress == 1.0 and not main.session.is_busy(), "skipping frost shows the complete committed hazard")
	var view: Dictionary = main.session.display_snapshot()
	var route: Dictionary = view.config.routes[0]
	view.route = {"choice":route.id, "step":1}
	view.encounter = route.encounters[1]
	view.phase = "packing"
	view.enemy_health = view.config.encounters[view.encounter].hp
	main.session.reset(main.inventory, view)
	check(main.session.submit({"type":"start"}).is_empty(), "boss battle starts")
	check(main.session.state_snapshot().phase == "battle" and main.session.display_snapshot().phase == "packing", "boss result commits before cinematic but remains visually hidden")
	main.session.playback.queue._process(0)
	check(main.cinematics.visible and main.cinematics.mode == "intro", "boss intro begins through event queue")
	check(main.cinematics.data.title == "ARANG" and main.cinematics.data.epithet == "THE VENGEFUL SPIRIT", "boss epithet is sourced from presentation data")
	var introductions: Dictionary = main.cinematics.entries.boss_intros
	check(introductions.yagwang.title == "YAGWANGGWI" and introductions.yagwang.epithet == "THE SHOE THIEF", "yagwang title and epithet are English")
	for entry: Dictionary in introductions.values():
		var ascii_only := true
		var words := str(entry.title) + str(entry.epithet)
		for index in words.length(): ascii_only = ascii_only and words.unicode_at(index) < 128
		check(ascii_only, "all cinematic titles use English characters")
	check(VfxPlayer.ATLAS.get_size() == Vector2(64,64), "shared particle atlas is 64 by 64")
	check(main.vfx.data.profiles.size() == 4 and main.vfx.burst.one_shot and main.vfx.burst.speed_scale == 0.0, "particle emitter uses the atlas and is controlled by playback")
	check(not main.session.submit({"type":"start"}).is_empty(), "cinematic blocks duplicate requests")
	main.cinematics.set_progress(0.8)
	check(main.cinematics._stamp_played, "stamp cue fires at its presentation time")
	main.cinematics.set_progress(0.95)
	check((main.cinematics.wipe.material as ShaderMaterial).get_shader_parameter("coverage") > 0.0, "ink wipe closes the cinematic near its end")
	main.session.skip_playback()
	check(not main.cinematics.visible and main.session.display_snapshot().phase == "battle" and not main.session.is_busy(), "skip finishes committed state and clears intro")
	check(not main.sounds.player.playing, "skip stops sound")
	main._toggle_sound()
	main.sounds.cue("stamp")
	check(not main.sounds.enabled and not main.sounds.player.playing, "sound toggle prevents audio")
	main._toggle_sound()
	check(main.sounds.enabled, "sound can be reenabled")
	# Turn stamp is a short queue command and cannot expose the next turn early.
	check(main.session.submit({"type":"end_turn"}).is_empty(), "turn ending submitted")
	main.session.playback.queue._process(0)
	var first: CombatEventCommand = main.session.playback.queue._current
	first._impact()
	if first._tween != null: first._tween.kill()
	first._complete()
	main.session.playback.queue._process(0)
	check(main.cinematics.visible and main.cinematics.mode == "turn" and is_equal_approx(main.cinematics.duration_seconds, 0.25), "turn stamp plays with bounded queue timing")
	check(main.session.display_snapshot().turn == 1, "next turn is not shown before the stamp impact")
	main.session.skip_playback()
	check(main.session.display_snapshot().turn == 2 and not main.cinematics.visible, "skip reconciles turn and clears stamp")
	var previous: Dictionary = main.session.display_snapshot()
	var prepared: Dictionary = previous.duplicate(true)
	previous.phase = "route"
	prepared.phase = "packing"
	check(main.board.begin_frost_feedback({"kind":"encounter_prepared", "after":prepared}, previous), "new frost accepts a presentation event")
	check(main.board.frost_progress == 0.0, "frost starts unanimated")
	main.board.set_frost_progress(0.75)
	check(is_equal_approx(main.board.frost_progress, 0.5), "frost grows after event impact")
	main.board.clear_frost_feedback()
	check(main.board.frost_progress == 1.0, "frost settles when cancelled or finished")
	# Actual event continuation is the transition to the current stage completion.
	view = main.session.state_snapshot()
	view.phase = "event_result"
	view.event = {"id":view.config.events[0].id, "uid":"event/test", "selected":"leave", "status":"resolved", "outcome":"leave", "method":""}
	main.session.reset(main.inventory, view)
	check(main.session.submit({"type":"event_continue", "event_id":view.event.id}).is_empty(), "stage ending accepted")
	main.session.playback.queue._process(0)
	check(main.cinematics.visible and main.cinematics.mode == "memory" and main.session.display_snapshot().phase == "event_result", "memory plays before final phase is presented")
	main.cinematics.set_progress(0.5)
	check(main.cinematics.progress == 0.5 and main.cinematics.data.caption.contains("bamboo"), "memory contains zoom progress and caption")
	main.session.skip_playback()
	check(main.session.display_snapshot().phase == "complete" and not main.cinematics.visible, "memory skip reveals completion")
	# A lethal hit is still a committed simulation event; playback only visualizes it.
	view = main.session.state_snapshot()
	view.phase = "battle"
	view.event = {}
	view.enemy_health = 1
	view.enemy_guard = 0
	view.energy = view.config.energy_per_turn
	view.used = {}
	var result := CombatSimulator.resolve(view, {"type":"use_item", "uid":"sword"})
	var hits := result.events().filter(func(event): return event.kind == "damage" and event.target == "enemy")
	check(result.error.is_empty() and hits.size() == 1, "lethal hit simulation succeeds")
	var hit: Dictionary = hits[0]
	var batch := CombatResolution.new(view, hit.after, [hit])
	main.session.playback.reset(view)
	main.session.playback.play(batch)
	main.session.playback.queue._process(0)
	check(main.road.feedback_lethal and main.session.playback._lethal and not main.road.feedback_impact, "lethal presentation is detected without revealing damage early")
	var command: CombatEventCommand = main.session.playback.queue._current
	command._impact()
	check(main.session.display_snapshot().enemy_health == 0 and main.road.feedback_impact, "health and lethal impact appear together")
	check(main.vfx.burst.visible and main.vfx.burst.emitting and main.vfx.burst.speed_scale == 0.0, "lethal impact starts the paused one-shot emitter")
	main.session.playback._update_feedback_progress(0.8)
	main.road._show_enemy(Vector2(866,62), Color.WHITE)
	check((main.road.enemy_sprite.material as ShaderMaterial).get_shader_parameter("dissolve") > 0.5, "ink shader receives playback dissolve progress")
	check(main.vfx.elapsed > 0.0 and main.vfx.burst.visible, "particle time advances only from playback progress")
	var particle_time: float = main.vfx.elapsed
	command._impact()
	check(main.vfx.elapsed == particle_time, "duplicate impact does not restart particles")
	main.session.skip_playback()
	check(not main.road.feedback_lethal and not main.session.is_busy() and main.session.display_snapshot().enemy_health == 0, "skip clears lethal feedback and keeps committed result")
	check(not main.vfx.burst.visible and not main.vfx.burst.emitting and main.vfx.elapsed == 0.0, "skip immediately hides and clears particle timing")
	main.session.playback.reset(view)
	main.session.playback.play(batch)
	main.session.playback.queue._process(0)
	command = main.session.playback.queue._current
	command._impact()
	main.session.playback._update_feedback_progress(0.75)
	check(main.vfx.burst.visible and main.vfx.elapsed > 0.0, "another lethal event restarts the emitter")
	main.session.playback.reset(view)
	await process_frame
	check(not main.vfx.burst.visible and main.vfx.elapsed == 0.0, "restart cancels active particle presentation")
	# Restart during a cinematic invalidates the queued impact and cancels its Tween.
	view.phase = "packing"
	view.enemy_health = view.config.encounters[view.encounter].hp
	main.session.reset(main.inventory, view)
	check(main.session.submit({"type":"start"}).is_empty(), "restart test starts")
	main.session.playback.queue._process(0)
	main._reset_run()
	await create_timer(0.4).timeout
	check(not main.cinematics.visible and main.session.display_snapshot().phase == "packing" and not main.session.is_busy(), "restart cancels stale cutscene callbacks")
	main.session.reset(main.inventory, view)
	check(main.session.submit({"type":"start"}).is_empty(), "natural playback test starts")
	await create_timer(2.9).timeout
	check(not main.session.is_busy() and not main.cinematics.visible and main.session.display_snapshot().phase == "battle", "boss intro completes naturally before watchdog timeout")
	for size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = size
		await process_frame
		check(Rect2(Vector2.ZERO, main.size).encloses(main.layout.buttons.sound.get_global_rect()), "sound toggle fits viewport " + str(size) + " rect=" + str(main.layout.buttons.sound.get_global_rect()))
	var closing_main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	closing_main.save_enabled = false
	root.add_child(closing_main)
	check(closing_main.session.submit({"type":"start"}).is_empty(), "scene exit case starts guard dialogue")
	closing_main.session.playback.queue._process(0)
	check(closing_main.cinematics.visible, "dialogue is visible before scene exit")
	var closing_ref: WeakRef = weakref(closing_main)
	closing_main.queue_free()
	await process_frame
	check(closing_ref.get_ref() == null, "scene exit frees active dialogue and its playback")
	main.queue_free()
	await process_frame
	print("CINEMATICS TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
