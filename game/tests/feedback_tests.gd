extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	var battle := CombatResolver.new(model)
	battle.start_battle()
	var initial := battle.snapshot()
	var result := CombatSimulator.resolve(initial, {"type":"use_item", "uid":"sword"})
	var events := result.events()
	var hit: Dictionary = events[-1]
	var before: Dictionary = events[-2].after
	var after: Dictionary = hit.after
	var batch := CombatResolution.new(before, after, [hit])
	var road := RoadView.new()
	root.add_child(road)
	var playback := CombatPlayback.new()
	root.add_child(playback)
	playback.bind_feedback(road)
	playback.seconds_per_step = 1.0
	playback.reset(before)
	playback.play(batch)
	playback.queue._process(0)
	var command: CombatEventCommand = playback.queue._current
	check(road.feedback_target == "enemy" and road.feedback_kind == "damage" and not road.feedback_impact, "damage chooses only the target and hides the value before impact")
	check(playback.snapshot().enemy_health == before.enemy_health, "health stays on preceding snapshot before impact")
	var observed := {"presented":0}
	var listener := func(): observed.presented += 1
	playback.presented.connect(listener)
	command._impact()
	check(playback.snapshot() == after and road.feedback_impact and road.feedback_text == "-6", "impact displays actual damage with its matching snapshot")
	command._impact()
	check(observed.presented == 1, "duplicate impact cannot present twice")
	playback.presented.disconnect(listener)
	playback.skip()
	check(not playback.is_busy() and playback.snapshot() == after and road.feedback_target.is_empty() and not road.feedback_impact, "skip snaps to final state and clears transient visuals")
	command._impact()
	check(playback.snapshot() == after and road.feedback_target.is_empty(), "late impact after skip is ignored")
	# Zero-duration playback still applies the snapshot exactly once and clears visuals.
	playback.seconds_per_step = 0.0
	playback.reset(before)
	playback.play(batch)
	playback.queue._process(0)
	playback.queue._process(0)
	check(not playback.is_busy() and playback.snapshot() == after and road.feedback_target.is_empty(), "zero-duration commands finish synchronously")
	# A hit fully absorbed by guard must show the absorbed amount, not a health loss.
	var blocked := initial.duplicate(true)
	blocked.enemy_guard = 10
	var guarded := CombatSimulator.resolve(blocked, {"type":"use_item", "uid":"sword"}).events()
	road.begin_feedback(guarded[-1], guarded[-2].after)
	check(road.feedback_text == "막음 6" and not road.feedback_impact, "blocked damage is represented separately from health damage")
	road.impact_feedback()
	check(road.feedback_target == "enemy" and road.feedback_impact, "blocked hit is anchored to the defender")
	road.clear_feedback()
	# Reflected damage targets the player, guard uses actual delta, and healing is capped.
	var reflected := {"kind":"damage", "target":"player", "health_damage":3, "absorbed":0, "after":before}
	road.begin_feedback(reflected, before)
	check(road.feedback_target == "player" and road.feedback_text == "-3", "reflected damage points at the player")
	var guard_after := before.duplicate(true)
	guard_after.guard += 5
	road.begin_feedback({"kind":"guard", "target":"player", "after":guard_after}, before)
	check(road.feedback_text == "방어 +5", "guard text reflects the actual snapshot delta")
	var heal_before := before.duplicate(true)
	heal_before.health = heal_before.config.max_health - 2
	var heal_after := heal_before.duplicate(true)
	heal_after.health = heal_after.config.max_health
	road.begin_feedback({"kind":"heal", "target":"player", "amount":7, "after":heal_after}, heal_before)
	check(road.feedback_text == "+2", "healing displays actual capped recovery")
	road.clear_feedback()
	# A full reaction cascade keeps target, number and snapshot aligned at every impact.
	var cascade := initial.duplicate(true)
	cascade.reactions = [
		{"id":"spikes", "name":"spikes", "owner":"enemy", "effect":"damage", "target":"player", "amount":3},
		{"id":"shield", "name":"shield", "owner":"player", "effect":"guard", "target":"player", "amount":5}]
	var cascade_result := CombatSimulator.resolve(cascade, {"type":"use_item", "uid":"sword"})
	var cascade_events := cascade_result.events()
	var shown: Array = []
	playback.seconds_per_step = 0.0
	playback.reset(cascade)
	playback.play(cascade_result)
	var capture := func(): shown.append({"snapshot":playback.snapshot(), "target":road.feedback_target, "text":road.feedback_text, "impact":road.feedback_impact})
	playback.presented.connect(capture)
	for i in 20:
		if not playback.is_busy(): break
		playback.queue._process(0)
	playback.presented.disconnect(capture)
	check(shown.size() == cascade_events.size() + 1, "cascade presents every recorded snapshot and one final reconciliation")
	if shown.size() == cascade_events.size() + 1:
		for i in cascade_events.size(): check(shown[i].snapshot == cascade_events[i].after and shown[i].impact, "cascade impact follows its event snapshot")
		check(shown[1].target == "enemy" and shown[1].text == "-6" and shown[2].target == "player" and shown[2].text == "-3" and shown[3].text == "방어 +5", "hit, reflection and guard feedback follow FIFO targets")
	playback.seconds_per_step = 0.08
	playback.reset(before)
	playback.play(batch)
	await create_timer(0.3).timeout
	check(not playback.is_busy() and playback.snapshot() == after and road.feedback_target.is_empty(), "real Tween completes and clears feedback")
	playback.seconds_per_step = 0.5
	playback.reset(before)
	playback.play(batch)
	playback.queue._process(0)
	command = playback.queue._current
	command._impact()
	playback.reset(before)
	await create_timer(0.3).timeout
	check(playback.snapshot() == before and road.feedback_target.is_empty(), "restart after impact cancels late callbacks and visuals")
	playback.play(batch)
	playback.queue._process(0)
	playback.queue._process(5.0)
	check(not playback.is_busy() and playback.snapshot() == after and road.feedback_target.is_empty(), "watchdog clears feedback and recovers final snapshot")
	# A listener may restart synchronously during impact; never announce the old event afterward.
	playback.reset(before)
	playback.play(batch)
	playback.queue._process(0)
	command = playback.queue._current
	var notices := {"count":0}
	var count_notice := func(_event): notices.count += 1
	var restart_on_present := func(): playback.reset(before)
	playback.event_presented.connect(count_notice)
	playback.presented.connect(restart_on_present, CONNECT_ONE_SHOT)
	command._impact()
	playback.event_presented.disconnect(count_notice)
	check(notices.count == 0 and playback.snapshot() == before and road.feedback_target.is_empty(), "restart during impact suppresses the obsolete event message")
	playback.reset(before)
	playback.play(batch)
	playback.queue._process(0)
	playback.free()
	check(road.feedback_target.is_empty(), "removing playback clears feedback on a surviving view")
	var surviving_playback := CombatPlayback.new()
	root.add_child(surviving_playback)
	surviving_playback.bind_feedback(road)
	surviving_playback.seconds_per_step = 0.08
	surviving_playback.reset(before)
	surviving_playback.play(batch)
	surviving_playback.queue._process(0)
	road.free()
	await create_timer(0.3).timeout
	check(not surviving_playback.is_busy() and surviving_playback.snapshot() == after, "freeing the view during a Tween still completes playback")
	surviving_playback.queue_free()
	await process_frame
	print("FEEDBACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
