extends SceneTree
## Run in two separate processes. `shipping` also runs against the release PCK.

func _initialize() -> void:
	call_deferred("_run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		fail("Expected slot, write/read, and fixture/shipping")
		return
	var slot: String = args[0]
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json" if args[2] == "fixture" else ItemCatalog.DEFAULT_PATH)
	if model == null:
		fail("Could not load process test content")
		return
	var store := SaveService.new(slot)
	var loaded := store.load_slot(model)
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = store
	if args[1] == "write":
		if loaded.status != "missing" or not session.prepare_new(model).is_empty():
			fail("Could not initialize isolated process slot")
			return
		session.reset(model)
		var chosen := ""
		for uid: String in model.combat_snapshot():
			for effect: Dictionary in model.action_result(uid).effects:
				if effect.kind == "damage" and effect.target == "enemy" and effect.amount > 0 and model.definition(uid).cost <= model.config.energy_per_turn:
					chosen = uid
					break
			if not chosen.is_empty(): break
		if chosen.is_empty() or not session.submit({"type":"start"}).is_empty():
			fail("No usable attack in initial loadout")
			return
		session.skip_playback()
		if not session.submit({"type":"use_item", "uid":chosen}).is_empty() or not session.is_busy():
			fail("Could not submit attack before exit")
			return
		var expected := SaveCodec.encode(session.state_snapshot(), model, model.history)
		var file := FileAccess.open(slot + ".expected", FileAccess.WRITE)
		if file == null:
			fail("Could not write process expectation")
			return
		file.store_string(expected)
		file.close()
		print("SAVE PROCESS WRITE: PASS")
	elif args[1] == "read":
		if loaded.status != "ok":
			fail("Could not reopen the previous process state: " + str(loaded.error))
			return
		model.items = loaded.items
		model.history = loaded.history
		session.reset(model, loaded.state)
		if session.is_busy() or session.display_snapshot() != loaded.state or SaveCodec.encode(session.state_snapshot(), model, model.history) != FileAccess.get_file_as_string(slot + ".expected"):
			fail("Restart did not restore the exact committed state")
			return
		print("SAVE PROCESS READ: PASS")
	else:
		fail("Unknown process test mode")
		return
	session.queue_free()
	await process_frame
	quit(0)
