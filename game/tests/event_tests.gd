extends SceneTree

const LEGACY_CATALOG := "res://tests/fixtures/catalog-v0.13.json"

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func submit(session: BattleSession, request: Dictionary) -> String:
	var error := session.submit(request)
	if error.is_empty(): session.skip_playback()
	return error

func check_v3(session: BattleSession, model: InventoryModel, label: String) -> void:
	var state := session.state_snapshot()
	var doc: Dictionary = JSON.parse_string(JSON.parse_string(SaveCodec.encode(state, model, model.history)).payload)
	doc.version = 3
	var restored := SaveCodec.new().decode(SaveCodec._wrap(doc), model)
	check(restored.status == "ok" and restored.get("migrated", false) and restored.state == state and restored.history == model.history, "v3 migration: " + label)

func make_event(session: BattleSession, model: InventoryModel) -> void:
	var state := CombatSimulator.initial_state(model.config)
	state.phase = "battle"
	state.enemy_health = 1
	state.health = 10
	session.reset(model, state)
	check(submit(session, {"type":"use_item", "uid":"sword"}).is_empty(), "first victory")
	check(submit(session, {"type":"reward_skip", "offer_id":session.display_snapshot().reward.offer_id}).is_empty(), "skip first reward")
	check(submit(session, {"type":"advance"}).is_empty() and session.display_snapshot().phase == "event", "first victory opens event")

func _run() -> void:
	_test_validation()
	_test_migration()
	await _test_choices()
	print("EVENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_validation() -> void:
	var original: Dictionary = ContentLoader.new().load_json(LEGACY_CATALOG).raw
	for kind in ["missing_item", "consumable", "wrong_step", "duplicate", "empty_text"]:
		var bad := original.duplicate(true)
		match kind:
			"missing_item": bad.events[0].item_id = "missing"
			"consumable": bad.events[0].item_id = "yakgwa"
			"wrong_step": bad.events[0].step = 1
			"duplicate": bad.events.append(bad.events[0].duplicate(true))
			"empty_text": bad.events[0].take_result = ""
		check(not ContentLoader.new().validate(bad).error.is_empty(), "invalid event is rejected: " + kind)

func _test_migration() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/catalog-v0.9.json"))
	var new_model := ItemCatalog.create_inventory(LEGACY_CATALOG)
	old.schema_version = 4
	old.events = []
	var loaded := ContentLoader.new().validate(old)
	check(loaded.error.is_empty(), "old catalog values validate in current schema")
	var normalized: Dictionary = loaded.raw.duplicate(true)
	normalized.erase("events")
	normalized.schema_version = 3
	var old_hash := JSON.stringify(normalized, "", true).sha256_text()
	check(old_hash == new_model.previous_content_hash, "old shipping catalog hash matches migration")
	var old_model := ItemCatalog.from_validated(loaded.raw)
	old_model.content_hash = old_hash
	for index in [0,1,2]:
		var state := CombatResolver.new(old_model).snapshot()
		state.encounter = index
		state.enemy_health = state.config.encounters[index].hp
		state.phase = "battle"
		state.route = {"choice":"" if index == 0 else state.config.routes[0].id,"step":index}
		var envelope: Dictionary = JSON.parse_string(SaveCodec.encode(state, old_model, []))
		var doc: Dictionary = JSON.parse_string(envelope.payload)
		doc.version = 2
		doc.state.erase("event")
		var text := SaveCodec._wrap(doc)
		var restored := SaveCodec.new().decode(text, new_model)
		check(restored.status == "ok" and restored.get("migrated", false) and restored.state.encounter == index and restored.state.event.is_empty(), "0.9 save migrates at step %d" % index)
		doc.content_hash = "different"
		check(SaveCodec.new().decode(SaveCodec._wrap(doc), new_model).status == "incompatible", "different legacy content is preserved")
	# Loading is read-only; the next successful action keeps the original as backup.
	var old_state := CombatResolver.new(old_model).snapshot()
	var old_envelope: Dictionary = JSON.parse_string(SaveCodec.encode(old_state, old_model, []))
	var old_doc: Dictionary = JSON.parse_string(old_envelope.payload)
	old_doc.version = 2
	old_doc.state.erase("event")
	var original := SaveCodec._wrap(old_doc)
	var folder := ProjectSettings.globalize_path("res://../build/event-migration/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var slot := folder.path_join("run.json")
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var service := SaveService.new(slot)
	var restored := service.load_slot(new_model)
	check(restored.status == "ok" and restored.get("migrated", false) and FileAccess.get_file_as_string(slot) == original, "loading 0.9 leaves original bytes intact")
	if restored.status == "ok":
		new_model.items = restored.items
		check(service.write_slot(restored.state, new_model, restored.history).is_empty() and FileAccess.get_file_as_string(slot + ".bak") == original, "next write backs up original 0.9 save")

func _test_choices() -> void:
	for variant in ["take", "leave", "stashed"]:
		var folder := ProjectSettings.globalize_path("res://../build/event-tests/%d/%s" % [OS.get_process_id(), variant])
		DirAccess.make_dir_recursive_absolute(folder)
		var slot := folder.path_join("run.json")
		var model := ItemCatalog.create_inventory(LEGACY_CATALOG)
		var service := SaveService.new(slot)
		check(service.load_slot(model).status == "missing", "isolated event slot")
		var session := BattleSession.new()
		root.add_child(session)
		session.save_service = service
		session.reset(model)
		make_event(session, model)
		check_v3(session, model, "event pending")
		var event: Dictionary = session.display_snapshot().event
		var id: String = event.id
		var uid: String = event.uid
		var before := session.state_snapshot()
		check(not session.submit({"type":"event_confirm", "event_id":id}).is_empty() and session.state_snapshot() == before, "unselected confirmation cannot mutate state")
		check(not session.submit({"type":"event_take", "event_id":"stale"}).is_empty(), "stale event ID rejected")
		var original := FileAccess.get_file_as_string(slot)
		var modified := FileAccess.open(slot, FileAccess.WRITE)
		modified.store_string("external change")
		modified.close()
		check(not session.submit({"type":"event_take", "event_id":id}).is_empty() and session.state_snapshot() == before and session.display_snapshot() == before, "save conflict rejects event without state or display changes")
		modified = FileAccess.open(slot, FileAccess.WRITE)
		modified.store_string(original)
		modified.close()
		check(submit(session, {"type":"event_take", "event_id":id}).is_empty(), "stage one relic")
		check_v3(session, model, "event item selected")
		check(model.items.has(uid) and not model.is_packed(uid), "selected relic begins in stash")
		check(not session.submit({"type":"event_confirm", "event_id":id}).is_empty(), "unpacked relic cannot be confirmed")
		if variant == "leave":
			check(submit(session, {"type":"event_leave", "event_id":id}).is_empty() and not model.items.has(uid), "leaving removes only tentative relic")
		else:
			check(session.stash("hat").is_empty() and session.place(uid, Vector2i(1,2), 0).is_empty(), "rearrange and pack relic")
			check(submit(session, {"type":"event_confirm", "event_id":id}).is_empty() and model.is_packed(uid), "confirm requires two occupied cells")
		check(session.display_snapshot().phase == "route", "choice advances once to route")
		check_v3(session, model, "route selection")
		before = session.state_snapshot()
		check(not session.submit({"type":"event_leave", "event_id":id}).is_empty() and session.state_snapshot() == before, "late change is rejected")
		var route: String = model.config.routes[1].id
		check(submit(session, {"type":"choose_route", "route_id":route}).is_empty(), "second route can be chosen")
		check_v3(session, model, "second encounter preparation")
		if variant == "stashed": check(session.stash(uid).is_empty(), "player can put the relic away before the follow-up")
		var state := session.display_snapshot()
		state.phase = "battle"
		state.enemy_health = 1
		state.health = 10
		state.energy = state.config.energy_per_turn
		state.used.clear()
		session.reset(model, state)
		var before_hit := session.state_snapshot()
		var simulated := CombatSimulator.resolve(before_hit, {"type":"use_item", "uid":"sword"})
		var events := simulated.events()
		check(events.size() >= 2 and events[-1].kind == "event_followup" and events[-2].kind == "victory" and events[-1].cause_id == events[-2].id and session.state_snapshot() == before_hit, "victory and follow-up are ordered, linked and purely simulated")
		check(session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "second battle commits")
		var committed := session.state_snapshot()
		check_v3(session, model, "follow-up result")
		check(committed.phase == "event_result" and session.display_snapshot().phase == "battle", "outcome waits for playback")
		var expected := "take" if variant == "take" else "leave"
		check(committed.event.outcome == expected and committed.health == (18 if expected == "take" else 14), "outcome checks currently packed relic and applies bounded heal")
		var loaded := SaveService.new(slot).load_slot(ItemCatalog.create_inventory(LEGACY_CATALOG))
		check(loaded.status == "ok" and loaded.state == committed, "follow-up saves before playback")
		session.skip_playback()
		check(session.display_snapshot() == committed, "skip shows exactly the committed outcome")
		check(submit(session, {"type":"event_continue", "event_id":id}).is_empty() and session.display_snapshot().phase == "reward", "follow-up leads to existing reward")
		check(not session.submit({"type":"event_continue", "event_id":id}).is_empty(), "follow-up cannot be applied twice")
		session.queue_free()
		await process_frame
