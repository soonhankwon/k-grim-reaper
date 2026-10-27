extends SceneTree

class FaultSave extends SaveService:
	var fail_write := ""
	var fail_replace := ""
	func _init(filename: String) -> void: super(filename)
	func _write_text(filename: String, text: String) -> String:
		if fail_write == "all" or (fail_write == "backup" and ".bak." in filename): return "모의 디스크 쓰기 오류"
		return super._write_text(filename, text)
	func _replace_file(from: String, to: String) -> Error:
		if fail_replace == "primary" and to == path: return ERR_CANT_CREATE
		if fail_replace == "backup" and to == path + ".bak": return ERR_CANT_CREATE
		return super._replace_file(from, to)

var checks := 0
var failures := 0
var base: String

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture() -> InventoryModel:
	var raw: Dictionary = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	raw.rewards = [{"id":"gift_one", "encounter_id":"gate_1", "item_ids":"coin|mirror|rope"},
		{"id":"gift_two", "encounter_id":"gate_2", "item_ids":"yakgwa|sandals|order"}]
	var result := ContentLoader.new().validate(raw)
	check(result.error.is_empty(), "save fixture validates")
	return ItemCatalog.from_validated(result.raw)

func reopen(filename: String) -> Dictionary:
	var model := fixture()
	var service := SaveService.new(filename)
	var loaded := service.load_slot(model)
	return {"model": model, "service": service, "loaded": loaded}

func check_loaded(filename: String, expected: Dictionary, history: Array, description: String) -> void:
	var result := reopen(filename)
	check(result.loaded.status == "ok", description + " loads")
	if result.loaded.status != "ok": return
	if result.loaded.state != expected:
		for field in expected:
			if result.loaded.state.get(field) != expected[field]: print("DIFF ", description, " ", field, " saved=", result.loaded.state.get(field), " expected=", expected[field])
	if result.loaded.history != history: print("HISTORY DIFF ", description, " saved=", result.loaded.history, " expected=", history)
	check(result.loaded.state == expected and result.loaded.history == history, description + " preserves exact state and undo history")
	check(result.loaded.items.keys() == expected.inventory_items.keys(), description + " preserves stash item order")

func overwrite(filename: String, text: String) -> void:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func edit_payload(text: String, field: String, value: Variant) -> String:
	var envelope: Dictionary = JSON.parse_string(text)
	var doc: Dictionary = JSON.parse_string(envelope.payload)
	doc[field] = value
	var payload := JSON.stringify(doc, "", true)
	return JSON.stringify({"payload":payload, "checksum":payload.sha256_text()}, "", true) + "\n"

func wrap_doc(doc: Dictionary) -> String:
	var payload := JSON.stringify(doc, "", true)
	return JSON.stringify({"payload":payload, "checksum":payload.sha256_text()}, "", true) + "\n"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var parent := ProjectSettings.globalize_path("res://../build/save-tests")
	DirAccess.make_dir_recursive_absolute(parent)
	var serial := 0
	base = parent.path_join("%d-%d" % [OS.get_process_id(), serial])
	while DirAccess.dir_exists_absolute(base):
		serial += 1
		base = parent.path_join("%d-%d" % [OS.get_process_id(), serial])
	DirAccess.make_dir_absolute(base)
	await _test_play_and_resume()
	await _test_write_failures()
	_test_recovery_and_versions()
	_test_invalid_content()
	await _test_conflicting_sessions()
	print("SAVE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_play_and_resume() -> void:
	var filename := base.path_join("play.json")
	var model := fixture()
	var service := SaveService.new(filename)
	check(service.load_slot(model).status == "missing", "empty slot is distinct from corrupt slot")
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = service
	check(session.prepare_new(model).is_empty(), "new run written before installation")
	session.reset(model)
	check(session.place("seal", Vector2i(2,1), 0).is_empty(), "layout is saved through transaction")
	check_loaded(filename, session.state_snapshot(), model.history, "layout and undo")
	check(session.place("yakgwa", Vector2i(4,1), 0).is_empty(), "consumable placed")
	check(session.submit({"type":"start"}).is_empty(), "battle start saves")
	session.skip_playback()
	session.submit({"type":"use_item", "uid":"yakgwa"})
	check(not model.items.has("yakgwa") and session.display_snapshot().inventory_items.has("yakgwa"), "consumption committed while still visible")
	check_loaded(filename, session.state_snapshot(), model.history, "consumption including used removed instance")
	session.skip_playback()
	session.submit({"type":"use_item", "uid":"sword"})
	var committed := session.state_snapshot()
	check(session.display_snapshot().enemy_health == 18 and committed.enemy_health == 10, "playback remains behind saved combat state")
	var restored := reopen(filename)
	check(restored.loaded.status == "ok" and restored.loaded.state == committed, "reopen during attack restores committed damage once")
	session.skip_playback()
	session.submit({"type":"use_item", "uid":"bell"})
	session.skip_playback()
	session.submit({"type":"use_item", "uid":"hat"})
	session.skip_playback()
	session.submit({"type":"end_turn"})
	session.skip_playback()
	session.submit({"type":"use_item", "uid":"sword"})
	check(session.state_snapshot().phase == "reward" and session.display_snapshot().phase == "battle", "reward stays hidden during final hit")
	check_loaded(filename, session.state_snapshot(), model.history, "pending reward during victory animation")
	session.skip_playback()
	var reward: Dictionary = session.display_snapshot().reward
	var uid: String = reward.uid
	session.submit({"type":"reward_select", "offer_id":reward.offer_id, "item_id":"coin"})
	check_loaded(filename, session.state_snapshot(), model.history, "tentative reward during choice animation")
	session.skip_playback()
	check(session.place(uid, Vector2i(4,1), 0).is_empty(), "tentative item can be saved in bag")
	check_loaded(filename, session.state_snapshot(), model.history, "tentative reward placement")
	check(session.undo_layout().is_empty() and not model.is_packed(uid), "undo restores tentative stash")
	check_loaded(filename, session.state_snapshot(), model.history, "undo")
	session.place(uid, Vector2i(4,1), 0)
	session.submit({"type":"reward_confirm", "offer_id":reward.offer_id})
	check_loaded(filename, session.state_snapshot(), model.history, "claimed reward during animation")
	session.skip_playback()
	var saved := reopen(filename)
	check(saved.loaded.status == "ok" and saved.loaded.state.reward.status == "claimed" and saved.loaded.items.has(uid), "reward persists exactly once")
	check(not session.submit({"type":"reward_confirm", "offer_id":reward.offer_id}).is_empty(), "repeated claim remains rejected")
	session.submit({"type":"advance"})
	session.skip_playback()
	check_loaded(filename, session.state_snapshot(), model.history, "next encounter")
	var next := fixture()
	check(session.prepare_new(next).is_empty(), "restart writes new state")
	session.reset(next)
	check_loaded(filename, session.state_snapshot(), next.history, "new run")
	session.queue_free()
	await process_frame

func _test_write_failures() -> void:
	var filename := base.path_join("fault.json")
	var model := fixture()
	var service := FaultSave.new(filename)
	service.load_slot(model)
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = service
	session.prepare_new(model)
	session.reset(model)
	var before := session.state_snapshot()
	var disk := FileAccess.get_sha256(filename)
	service.fail_write = "all"
	check(not session.place("seal", Vector2i(2,1), 0).is_empty() and session.state_snapshot() == before and model.history.is_empty(), "failed layout save cannot publish layout or undo")
	check(not session.submit({"type":"start"}).is_empty() and session.state_snapshot() == before and not session.is_busy(), "failed combat save cannot commit or play")
	check(FileAccess.get_sha256(filename) == disk, "failed writes keep original primary")
	service.fail_write = "backup"
	check(not session.place("seal", Vector2i(2,1), 0).is_empty() and FileAccess.get_sha256(filename) == disk, "failed backup write keeps original state")
	service.fail_write = ""
	service.fail_replace = "backup"
	check(not session.place("seal", Vector2i(2,1), 0).is_empty() and FileAccess.get_sha256(filename) == disk, "failed backup rename keeps original state")
	service.fail_replace = "primary"
	check(not session.place("seal", Vector2i(2,1), 0).is_empty() and FileAccess.get_sha256(filename) == disk and session.state_snapshot() == before, "failed primary rename keeps disk and memory unchanged")
	service.fail_replace = ""
	check(session.place("seal", Vector2i(2,1), 0).is_empty(), "transient failure can be retried")
	check_loaded(filename, session.state_snapshot(), model.history, "retry after failed writes")
	service.fail_write = "all"
	var old := session.state_snapshot()
	check(not session.prepare_new(fixture()).is_empty() and session.state_snapshot() == old, "failed restart preserves old session")
	session.queue_free()
	await process_frame

func _test_recovery_and_versions() -> void:
	var filename := base.path_join("recover.json")
	var model := fixture()
	var service := SaveService.new(filename)
	service.load_slot(model)
	var resolver := CombatResolver.new(model)
	var old := resolver.snapshot()
	check(service.write_slot(old, model, []).is_empty(), "initial recovery fixture saved")
	model.place("seal", Vector2i(2,1), 0)
	check(service.write_slot(resolver.snapshot(), model, model.history).is_empty(), "later save keeps previous normal backup")
	var backup := FileAccess.get_file_as_string(filename + ".bak")
	overwrite(filename, "{broken")
	var damaged_hash := FileAccess.get_sha256(filename)
	var restored := reopen(filename)
	check(restored.loaded.status == "ok" and restored.loaded.get("recovered", false) and restored.loaded.state == old, "corrupt primary recovers previous known-good state")
	check(FileAccess.get_file_as_string(filename) == "{broken", "reading fallback does not silently overwrite broken primary")
	if restored.loaded.status == "ok":
		check(restored.service.write_slot(restored.loaded.state, restored.model, restored.loaded.history).is_empty(), "recovered state can be saved again")
		check(FileAccess.get_file_as_string(filename + ".bak") == backup, "repair never replaces good backup with corrupt primary")
		check(FileAccess.get_file_as_string(filename + ".damaged-" + damaged_hash) == "{broken", "repair preserves the damaged original separately")
	var good := FileAccess.get_file_as_string(filename)
	var newer := edit_payload(good, "version", SaveCodec.VERSION + 1)
	overwrite(filename, newer)
	var incompatible := reopen(filename)
	check(incompatible.loaded.status == "incompatible" and FileAccess.get_file_as_string(filename) == newer, "newer format is preserved, not replaced by older backup")
	check(not incompatible.service.write_slot(old, incompatible.model, []).is_empty(), "incompatible file cannot be overwritten by this session")
	check(incompatible.service.can_archive(), "incompatible save offers an explicit archive path")
	var original_hash := FileAccess.get_sha256(filename)
	var previous_backup := FileAccess.get_file_as_string(filename + ".bak")
	var backup_hash := FileAccess.get_sha256(filename + ".bak")
	check(incompatible.service.archive_and_start(CombatResolver.new(incompatible.model).snapshot(), incompatible.model, []).is_empty(), "explicit archive starts a new run")
	var folder := filename.get_base_dir().path_join("archive")
	check(FileAccess.get_file_as_string(folder.path_join(filename.get_file() + "." + original_hash + ".json")) == newer, "archive preserves incompatible primary byte-for-byte")
	check(FileAccess.get_file_as_string(folder.path_join(filename.get_file() + "." + backup_hash + ".json")) == previous_backup, "archive preserves previous backup byte-for-byte")
	check(reopen(filename).loaded.status == "ok", "fresh save works after archiving old content")
	var changed := edit_payload(good, "content_hash", "different")
	overwrite(filename, changed)
	incompatible = reopen(filename)
	check(incompatible.loaded.status == "incompatible" and FileAccess.get_file_as_string(filename) == changed, "different content fingerprint blocks restore and overwrite")
	overwrite(filename + ".bak", "changed externally")
	check(not incompatible.service.archive_and_start(CombatResolver.new(incompatible.model).snapshot(), incompatible.model, []).is_empty() and FileAccess.get_file_as_string(filename) == changed, "archive refuses a concurrently changed backup")
	overwrite(filename, "{broken")
	overwrite(filename + ".bak", "{also broken")
	check(reopen(filename).loaded.status == "error" and FileAccess.get_file_as_string(filename) == "{broken", "two corrupt copies block play without discarding either")
	var lock := filename + ".lock"
	DirAccess.make_dir_absolute(lock)
	check(reopen(filename).loaded.status == "error" and DirAccess.dir_exists_absolute(lock), "existing lock is not removed by a second session")
	DirAccess.remove_absolute(lock)

func _test_conflicting_sessions() -> void:
	var filename := base.path_join("conflict.json")
	var first := fixture()
	var store_a := SaveService.new(filename)
	store_a.load_slot(first)
	var session_a := BattleSession.new()
	root.add_child(session_a)
	session_a.save_service = store_a
	session_a.prepare_new(first)
	session_a.reset(first)
	var second := reopen(filename)
	var session_b := BattleSession.new()
	root.add_child(session_b)
	session_b.save_service = second.service
	session_b.reset(second.model, second.loaded.state)
	check(session_a.place("seal", Vector2i(2,1), 0).is_empty(), "first session updates file")
	var before := session_b.state_snapshot()
	check(not session_b.submit({"type":"start"}).is_empty() and session_b.state_snapshot() == before, "stale session cannot overwrite another session or commit")
	check(not session_b.place("seal", Vector2i(2,1), 0).is_empty() and session_b.state_snapshot() == before, "stale layout cannot overwrite another session")
	check_loaded(filename, session_a.state_snapshot(), first.history, "concurrent winner")
	check(session_a.submit({"type":"start"}).is_empty() and session_a.is_busy(), "restart test begins while playback is active")
	var fresh := fixture()
	check(session_a.prepare_new(fresh).is_empty(), "restart saves fresh run before replacing playback")
	session_a.reset(fresh)
	for frame in 5: await process_frame
	check_loaded(filename, session_a.state_snapshot(), fresh.history, "restart during playback")
	check(session_a.display_snapshot().phase == "packing" and not session_a.is_busy(), "late old playback cannot overwrite fresh run")
	session_a.queue_free()
	session_b.queue_free()
	await process_frame

func _test_invalid_content() -> void:
	var model := fixture()
	var state := CombatResolver.new(model).snapshot()
	var encoded := SaveCodec.encode(state, model, [])
	var envelope: Dictionary = JSON.parse_string(encoded)
	var original: Dictionary = JSON.parse_string(envelope.payload)
	var cases: Array[Dictionary] = []
	var bad := original.duplicate(true)
	bad.state.phase = "unknown"
	cases.append(bad)
	bad = original.duplicate(true)
	bad.state.health = -1
	cases.append(bad)
	bad = original.duplicate(true)
	bad.state.encounter = 99
	cases.append(bad)
	bad = original.duplicate(true)
	bad.state.used = {"sword": -3}
	cases.append(bad)
	bad = original.duplicate(true)
	bad.state.reactions = [{"arbitrary": "payload"}]
	cases.append(bad)
	bad = original.duplicate(true)
	bad.items[0].definition = "missing"
	cases.append(bad)
	bad = original.duplicate(true)
	bad.items.append(bad.items[0].duplicate(true))
	cases.append(bad)
	bad = original.duplicate(true)
	bad.items[0].origin = [9,9]
	cases.append(bad)
	bad = original.duplicate(true)
	bad.items[1].origin = bad.items[0].origin.duplicate()
	cases.append(bad)
	bad = original.duplicate(true)
	bad.items.append({"uid":"reward/gift_one", "definition":"coin", "origin":[-1,-1], "rotation":0})
	cases.append(bad)
	bad = original.duplicate(true)
	bad.state.phase = "reward"
	bad.state.enemy_health = 0
	bad.state.reward = {"offer_id":"gift_one", "uid":"reward/gift_one", "candidates":["coin", "mirror", "rope"], "selected":"coin", "status":"pending"}
	cases.append(bad)
	bad = original.duplicate(true)
	bad.history = [original.items.duplicate(true)]
	bad.history[0].pop_back()
	cases.append(bad)
	for i in cases.size():
		check(SaveCodec.new().decode(wrap_doc(cases[i]), model).status == "corrupt", "invalid stored state rejected safely: " + str(i))
