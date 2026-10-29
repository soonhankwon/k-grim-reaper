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
	model.place("ring", Vector2i(0, 0), 0)
	var session := BattleSession.new()
	root.add_child(session)
	session.reset(model)
	check(not session.preview_end_turn().error.is_empty(), "cannot preview outside battle")
	check(session.submit({"type":"start"}).is_empty(), "battle starts")
	check(not session.preview_end_turn().error.is_empty(), "busy playback cannot preview")
	session.skip_playback()
	var before := session.display_snapshot()
	var history := model.history.duplicate(true)
	var expected := CombatSimulator.resolve(before, {"type":"end_turn"})
	var preview := session.preview_end_turn()
	check(preview.error.is_empty() and preview.after() == expected.after() and preview.events() == expected.events(), "preview uses the same complete simulation")
	check(session.state_snapshot() == before and session.display_snapshot() == before and model.history == history, "preview never mutates state, display or inventory history")
	# A real isolated save remains byte-for-byte untouched by repeated previews.
	var slot := ProjectSettings.globalize_path("res://../build/turn-preview-test-%d.json" % OS.get_process_id())
	var service := SaveService.new(slot)
	check(service.load_slot(model).status == "missing", "isolated test slot starts empty")
	check(service.write_slot(before, model, history).is_empty(), "write initial test slot")
	session.save_service = service
	var saved_hash := FileAccess.get_sha256(slot)
	session.preview_end_turn()
	session.preview_end_turn()
	check(FileAccess.get_sha256(slot) == saved_hash and not FileAccess.file_exists(slot + ".bak"), "preview does not write or rotate save files")
	session.save_service = null
	DirAccess.remove_absolute(slot)
	check(preview.events().any(func(event): return event.kind == "guard"), "automatic defense included")
	var preview_after := preview.after()
	check(session.submit({"type":"end_turn"}).is_empty(), "actual turn ends")
	check(not session.preview_end_turn().error.is_empty(), "preview is unavailable after commit during playback")
	check(session.state_snapshot() == preview_after, "committed outcome matches preview")
	session.skip_playback()
	check(session.display_snapshot() == preview_after, "skipping playback presents the committed outcome")
	var reactive := before.duplicate(true)
	reactive.guard = 0
	reactive.reactions = [{"id":"counter", "name":"counter", "owner":"player", "effect":"damage", "target":"enemy", "amount":2}]
	session.reset(model, reactive)
	var chain := session.preview_end_turn()
	check(chain.error.is_empty() and chain.events().any(func(event): return event.kind == "damage" and event.target == "enemy"), "preview includes damage reactions")
	check(session.state_snapshot() == reactive, "reaction preview remains read only")
	var lethal := reactive.duplicate(true)
	lethal.health = 1
	session.reset(model, lethal)
	var death := session.preview_end_turn()
	check(death.after().phase == "defeat", "lethal attack previews defeat")
	var invalid := before.duplicate(true)
	invalid.reactions = [{"id":"duplicate", "name":"a", "owner":"player", "effect":"guard", "target":"player", "amount":1}, {"id":"duplicate", "name":"b", "owner":"player", "effect":"guard", "target":"player", "amount":1}]
	session.reset(model, invalid)
	var bad := session.preview_end_turn()
	check(not bad.error.is_empty() and bad.after() == invalid and bad.events().is_empty(), "invalid reaction returns error without a partial prediction")
	var cycle := before.duplicate(true)
	cycle.guard = 0
	cycle.health = 1000
	cycle.enemy_health = 1000
	cycle.reactions = [{"id":"p", "name":"p", "owner":"player", "effect":"damage", "target":"enemy", "amount":1, "max_per_action":128}, {"id":"e", "name":"e", "owner":"enemy", "effect":"damage", "target":"player", "amount":1, "max_per_action":128}]
	session.reset(model, cycle)
	var overflow := session.preview_end_turn()
	check(not overflow.error.is_empty() and overflow.after() == cycle and overflow.events().is_empty(), "cycle limit rejects entire preview")
	check(session.state_snapshot() == cycle and session.display_snapshot() == cycle, "failed preview cannot commit partial state")
	session.queue_free()
	await process_frame
	print("TURN PREVIEW TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
