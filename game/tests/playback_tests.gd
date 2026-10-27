extends SceneTree

class InstantCommand extends ActionCommand:
	var log: Array
	var label: String
	func _init(output: Array, value: String) -> void:
		log = output
		label = value
	func execute() -> void:
		log.append(label)
		finish()
		completed.emit() # A buggy duplicate completion must not advance another command.

class HangingCommand extends ActionCommand:
	var started := false
	func execute() -> void:
		started = true

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
	_test_queue()
	await _test_session()
	print("PLAYBACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_queue() -> void:
	var queue := ActionQueue.new()
	root.add_child(queue)
	var log: Array = []
	var first := InstantCommand.new(log, "first")
	var second := InstantCommand.new(log, "second")
	check(queue.start([first, second]), "queue accepts fresh batch")
	check(not queue.start([ActionCommand.new()]), "queue rejects overlapping batches")
	queue._process(0.0)
	check(log == ["first"] and queue.is_busy(), "synchronous completion executes only one command per frame")
	queue._process(0.0)
	queue._process(0.0)
	check(log == ["first", "second"] and not queue.is_busy(), "duplicate signals cannot skip or repeat commands")
	check(not queue.start([first]), "settled commands cannot be reused")
	var repeated := ActionCommand.new()
	check(not queue.start([repeated, repeated]), "same command cannot occupy two slots")
	var old := HangingCommand.new()
	queue.start([old])
	queue._process(0.0)
	var stale_completion := queue._completion
	queue.cancel()
	check(old.is_settled() and not queue.is_busy(), "cancel settles current command and releases gate")
	var current := HangingCommand.new()
	queue.start([current])
	queue._process(0.0)
	old.completed.emit()
	stale_completion.call()
	check(queue.is_busy() and current.started, "old epoch completion cannot finish a new command")
	var observed := {"failures": 0}
	queue.failed.connect(func(_reason): observed.failures += 1)
	queue._process(queue.timeout_seconds + 1)
	check(observed.failures == 1 and not queue.is_busy() and current.is_settled(), "missing completion times out without freezing")
	var teardown := HangingCommand.new()
	queue.start([teardown])
	queue._process(0.0)
	queue.free()
	check(teardown.is_settled(), "scene teardown cancels outstanding command")

func _drain(session: BattleSession) -> void:
	for frame in 100:
		if not session.is_busy(): return
		await process_frame
	check(false, "playback did not drain within frame budget")

func _test_session() -> void:
	var session := BattleSession.new()
	root.add_child(session)
	session.playback.seconds_per_step = 0.0
	var inventory := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	inventory.place("seal", Vector2i(2,1), 0)
	session.reset(inventory)
	check(session.submit({"type": "start"}).is_empty(), "session accepts battle start")
	check(session.display_snapshot().phase == "packing" and session.state_snapshot().phase == "battle", "canonical state commits before presentation starts")
	check(not session.submit({"type": "end_turn"}).is_empty(), "repeated input blocked during playback")
	await _drain(session)
	var before := session.state_snapshot()
	session.submit({"type": "use_item", "uid": "sword"})
	var committed := session.state_snapshot()
	check(committed.enemy_health == 10 and session.display_snapshot().enemy_health == 18, "presentation never leaks final damage early")
	check(not inventory.place("seal", Vector2i(4,1), 0), "canonical layout cannot change during playback")
	check(not session.submit({"type": "use_item", "uid": "bell"}).is_empty() and session.state_snapshot() == committed, "overlapping input cannot spend energy or enqueue actions")
	var captured: Array = []
	var capture := func(): captured.append(session.display_snapshot())
	session.presented.connect(capture)
	await _drain(session)
	session.presented.disconnect(capture)
	check(captured[0].enemy_health == before.enemy_health and captured[-1] == committed, "intermediate and final presentation snapshots are coherent")
	check(session.state_snapshot() == committed, "normal playback never changes committed simulation")
	session.submit({"type": "end_turn"})
	var end_state := session.state_snapshot()
	session.skip_playback()
	check(not session.is_busy() and session.display_snapshot() == end_state and session.state_snapshot() == end_state, "skip reconciles display without rerunning simulation")
	session.playback.seconds_per_step = 0.2
	session.submit({"type": "use_item", "uid": "sword"})
	await process_frame
	await process_frame
	var fresh := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	session.reset(fresh)
	await create_timer(0.3).timeout
	check(session.state_snapshot().phase == "packing" and session.display_snapshot().enemy_health == 18 and not session.is_busy(), "reset kills active Tween and stale callbacks")
	# Reset synchronously from a started callback, before the command receives its Tween.
	var reset_on_start := func(_event): session.reset(ItemCatalog.create_inventory("res://tests/fixtures/baseline.json"))
	session.event_started.connect(reset_on_start, CONNECT_ONE_SHOT)
	session.submit({"type": "start"})
	await process_frame
	await process_frame
	await create_timer(0.25).timeout
	check(session.display_snapshot().phase == "packing" and not session.is_busy(), "reentrant reset from command start cannot revive old presentation")
	var skip_on_start := func(_event): session.skip_playback()
	session.event_started.connect(skip_on_start, CONNECT_ONE_SHOT)
	session.submit({"type": "start"})
	await process_frame
	await process_frame
	check(session.display_snapshot().phase == "battle" and not session.is_busy(), "reentrant skip at command start leaves final presentation")
	session.reset(ItemCatalog.create_inventory("res://tests/fixtures/baseline.json"))
	# Force a real stalled command through the playback watchdog.
	session.playback.seconds_per_step = 10.0
	session.submit({"type": "start"})
	var final_state := session.state_snapshot()
	await process_frame
	await process_frame
	session.playback.queue._process(5.0)
	check(not session.is_busy() and session.display_snapshot() == final_state, "watchdog snaps display to committed state and unlocks")
	session.submit({"type": "end_turn"})
	await process_frame
	var owned_queue := session.playback.queue
	session.free()
	await process_frame
	check(not is_instance_valid(owned_queue), "session teardown frees the pending queue")
