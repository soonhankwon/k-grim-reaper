extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fixture_raw() -> Dictionary:
	var raw: Dictionary = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	raw.rewards = [{"id":"gift_one", "encounter_id":"gate_1", "item_ids":"coin|mirror|rope"},
		{"id":"gift_two", "encounter_id":"gate_2", "item_ids":"yakgwa|sandals|order"}]
	raw.routes = [{"id":"normal", "name":"안개 길", "description":"순서대로", "encounter_ids":"gate_1|gate_2|gate_3", "reward_ids":"gift_one|gift_two"},
		{"id":"reverse", "name":"달 길", "description":"파수꾼부터", "encounter_ids":"gate_1|gate_3|gate_2", "reward_ids":"gift_one|gift_two"}]
	return raw

func make_model(raw: Dictionary) -> InventoryModel:
	var result := ContentLoader.new().validate(raw)
	check(result.error.is_empty(), "route fixture validates: " + str(result.error))
	return ItemCatalog.from_validated(result.raw) if result.error.is_empty() else null

func finish_battle(model: InventoryModel, state: Dictionary) -> CombatResolver:
	state.phase = "battle"
	state.enemy_health = 1
	state.used.clear()
	state.energy = state.config.energy_per_turn
	var battle := CombatResolver.new(model, state)
	battle.use_item("sword")
	return battle

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_validation()
	_test_paths()
	_test_migration()
	await _test_route_save()
	print("ROUTE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_validation() -> void:
	var original := fixture_raw()
	var bad := original.duplicate(true)
	bad.routes[0].encounter_ids = "gate_1|missing|gate_3"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "unknown encounter rejected")
	bad = original.duplicate(true)
	bad.routes[0].encounter_ids = "gate_1|gate_2|gate_2"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "duplicate encounter rejected")
	bad = original.duplicate(true)
	bad.routes[0].encounter_ids = "gate_2|gate_1|gate_3"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "every route starts at the same first encounter")
	bad = original.duplicate(true)
	bad.routes[0].reward_ids = "gift_one|missing"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "unknown reward rejected")
	bad = original.duplicate(true)
	bad.routes[0].reward_ids = "gift_two|gift_one"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "common first encounter has common reward")
	bad = original.duplicate(true)
	bad.routes[1].encounter_ids = bad.routes[0].encounter_ids
	check(not ContentLoader.new().validate(bad).error.is_empty(), "duplicate route order rejected")
	bad = original.duplicate(true)
	bad.routes.resize(1)
	check(not ContentLoader.new().validate(bad).error.is_empty(), "route selection requires multiple paths")

func _test_paths() -> void:
	for choice in ["normal", "reverse"]:
		var model := make_model(fixture_raw())
		var battle := finish_battle(model, CombatSimulator.initial_state(model.config))
		check(battle.phase == "reward" and battle.snapshot().reward.offer_id == "gift_one", "first encounter has common reward")
		battle.submit({"type":"reward_skip", "offer_id":"gift_one"})
		battle.advance()
		check(battle.phase == "route" and battle.inventory.locked and battle.encounter == 0, "advancement stops at locked route choice")
		var before := battle.snapshot()
		var bad := battle.submit({"type":"choose_route", "route_id":"missing"})
		check(not bad.error.is_empty() and battle.snapshot() == before, "invalid route changes nothing")
		var chosen := battle.submit({"type":"choose_route", "route_id":choice})
		var wanted := 1 if choice == "normal" else 2
		check(chosen.error.is_empty() and battle.phase == "packing" and battle.encounter == wanted and battle.snapshot().route.step == 1, "chosen route determines next encounter")
		check(not battle.submit({"type":"choose_route", "route_id":choice}).error.is_empty(), "route cannot be selected twice")
		battle = finish_battle(model, battle.snapshot())
		check(battle.phase == "reward" and battle.snapshot().reward.offer_id == "gift_two", "second reward follows route step, including reversed enemy")
		battle.submit({"type":"reward_skip", "offer_id":"gift_two"})
		battle.advance()
		check(battle.phase == "packing" and battle.encounter == (2 if choice == "normal" else 1), "remaining encounter follows in the correct order")
		battle = finish_battle(model, battle.snapshot())
		check(battle.phase == "victory" and battle.snapshot().reward.is_empty(), "last route step has no reward")
		battle.advance()
		check(battle.phase == "complete", "both paths finish after three distinct encounters")

func old_format(state: Dictionary, model: InventoryModel, history: Array) -> String:
	var envelope: Dictionary = JSON.parse_string(SaveCodec.encode(state, model, history))
	var doc: Dictionary = JSON.parse_string(envelope.payload)
	doc.version = 1
	doc.content_hash = model.legacy_content_hash
	doc.state.erase("route")
	var payload := JSON.stringify(doc, "", true)
	return JSON.stringify({"payload":payload,"checksum":payload.sha256_text()}, "", true) + "\n"

func _test_migration() -> void:
	var old_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/catalog-v0.6.json"))
	old_raw.schema_version = 4
	old_raw.events = []
	old_raw.routes = []
	var old_model := make_model(old_raw)
	var new_model := ItemCatalog.create_inventory()
	check(new_model != null and old_model.legacy_content_hash == new_model.legacy_content_hash, "new route catalog recognizes the actual 0.6 content")
	if new_model == null: return
	old_model.content_hash = old_model.legacy_content_hash
	var before := CombatResolver.new(old_model).snapshot()
	var text := old_format(before, old_model, [])
	var migrated := SaveCodec.new().decode(text, new_model)
	check(migrated.status == "ok" and migrated.get("migrated", false) and migrated.state.phase == "packing" and migrated.state.route.choice.is_empty(), "0.6 initial run migrates without choosing a path")
	# Validate actual previous states at every encounter and preserve the legacy order.
	for index in [0,1,2]:
		var state := before.duplicate(true)
		state.encounter = index
		state.enemy_health = old_model.config.encounters[index].hp
		state.phase = "battle"
		var old := old_format(state, old_model, [])
		migrated = SaveCodec.new().decode(old, new_model)
		check(migrated.status == "ok" and migrated.state.encounter == index and migrated.state.route.step == index, "legacy battle resumes at encounter %d" % index)
		if index > 0 and migrated.status == "ok": check(RouteRules.current(migrated.state).encounters == [0,1,2], "legacy path preserves original order")
	var altered := new_model.copy_for_transaction()
	altered.legacy_content_hash = "different"
	check(SaveCodec.new().decode(text, altered).status == "incompatible", "different old content is not silently migrated")
	var corrupt: Dictionary = JSON.parse_string(text)
	corrupt.checksum = "bad"
	check(SaveCodec.new().decode(JSON.stringify(corrupt), new_model).status == "corrupt", "old saves still require integrity")

func _test_route_save() -> void:
	var folder := ProjectSettings.globalize_path("res://../build/route-tests/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var slot := folder.path_join("route.json")
	var model := make_model(fixture_raw())
	var battle := finish_battle(model, CombatSimulator.initial_state(model.config))
	battle.submit({"type":"reward_skip", "offer_id":"gift_one"})
	battle.advance()
	var store := SaveService.new(slot)
	check(store.load_slot(model).status == "missing", "isolated route slot starts empty")
	check(store.write_slot(battle.snapshot(), model, model.history).is_empty(), "route choice state saves")
	var restored := SaveService.new(slot).load_slot(make_model(fixture_raw()))
	check(restored.status == "ok" and restored.state.phase == "route" and restored.state.route.choice.is_empty(), "resume shows route choice without replay")
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = store
	session.reset(model, battle.snapshot())
	check(not session.place("seal", Vector2i(2,1), 0).is_empty(), "layout is locked during route choice")
	var original := FileAccess.get_file_as_string(slot)
	var changed := FileAccess.open(slot, FileAccess.WRITE)
	changed.store_string("external change")
	changed.close()
	var before := session.state_snapshot()
	check(not session.submit({"type":"choose_route", "route_id":"reverse"}).is_empty(), "concurrent save change rejects route choice")
	check(session.state_snapshot() == before and session.display_snapshot() == before and not session.is_busy(), "failed save leaves both snapshots at route choice")
	var restored_file := FileAccess.open(slot, FileAccess.WRITE)
	restored_file.store_string(original)
	restored_file.close()
	check(session.submit({"type":"choose_route", "route_id":"reverse"}).is_empty(), "route choice passes the session")
	check(not session.submit({"type":"choose_route", "route_id":"normal"}).is_empty(), "rapid choice is locked")
	var committed := session.state_snapshot()
	restored = SaveService.new(slot).load_slot(make_model(fixture_raw()))
	check(restored.status == "ok" and restored.state == committed and committed.encounter == 2, "route selection is saved before playback")
	session.skip_playback()
	check(session.display_snapshot() == committed, "skipping playback preserves route selection")
	session.queue_free()
	await process_frame
