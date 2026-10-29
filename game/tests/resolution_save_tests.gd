extends SceneTree

const Experiment = preload("res://tests/arang_experiment_setup.gd")
var checks := 0
var failures := 0
var base := ""

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func submit(main: Control, request: Dictionary) -> String:
	var error: String = main.session.submit(request)
	if error.is_empty(): main.session.skip_playback()
	return error

func combat(main: Control) -> bool:
	for round_number in range(8):
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty() and not submit(main, {"type":"use_item", "uid":uid}).is_empty(): return false
		if main.session.display_snapshot().phase != "battle": break
		if not submit(main, {"type":"end_turn"}).is_empty(): return false
	return main.session.display_snapshot().phase in ["reward", "event_result"]

func read_slot(slot: String) -> Dictionary:
	return SaveService.new(slot).load_slot(ItemCatalog.create_inventory(Experiment.CONTENT_PATH))

func saved(main: Control, slot: String, label: String) -> void:
	var result := read_slot(slot)
	check(result.status == "ok", label + " loads: " + str(result.get("error", "")))
	if result.status == "ok": check(result.state == main.session.state_snapshot(), label + " preserves committed values")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	base = ProjectSettings.globalize_path("res://../build/resolution-saves/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	_test_content_validation()
	_test_csv()
	_test_v3_migration()
	for kind in ["resolution", "combat"]:
		await _test_run(kind)
	print("RESOLUTION SAVE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_content_validation() -> void:
	var raw: Dictionary = ContentLoader.new().load_json(Experiment.CONTENT_PATH).raw
	for kind in ["unknown_event", "duplicate", "missing_text", "bad_flag"]:
		var bad := raw.duplicate(true)
		match kind:
			"unknown_event": bad.resolutions[0].event_id = "does_not_exist"
			"duplicate": bad.resolutions.append(bad.resolutions[0].duplicate(true))
			"missing_text": bad.resolutions[0].result = ""
			"bad_flag": bad.resolutions[0].allow_stash = "yes"
		check(not ContentLoader.new().validate(bad).error.is_empty(), "invalid resolution rejected: " + kind)
	var without := raw.duplicate(true)
	without.erase("resolutions")
	var empty := without.duplicate(true)
	empty.resolutions = []
	check(ContentLoader.new().validate(empty).raw == ContentLoader.new().validate(without).raw, "empty optional table retains canonical hash")
	check(ItemCatalog.from_validated(raw).content_hash != ItemCatalog.from_validated(ContentLoader.new().validate(without).raw).content_hash, "resolution content contributes to hash")

func _test_csv() -> void:
	var dir := base.path_join("csv")
	DirAccess.make_dir_recursive_absolute(dir)
	var source := ProjectSettings.globalize_path("res://../content/source")
	for name in ["items.csv", "effects.csv", "tags.csv", "loadout.csv", "encounters.csv", "rules.csv", "rewards.csv", "routes.csv", "events.csv", "art.json"]:
		check(DirAccess.copy_absolute(source.path_join(name), dir.path_join(name)) == OK, "copy CSV " + name)
	var path := dir.path_join("resolutions.csv")
	check(not ContentLoader.new().load_csv_directory(dir).error.is_empty(), "missing resolutions sheet is rejected")
	var file := FileAccess.open(path, FileAccess.WRITE)
	var columns: Array = JSON.parse_string(FileAccess.get_file_as_string(ContentLoader.SCHEMA_PATH)).tables.resolutions.keys()
	file.store_csv_line(PackedStringArray(columns))
	var source_row: Dictionary = Experiment.load_resolution()
	var row: PackedStringArray = []
	for column: String in columns: row.append(str(source_row[column]))
	file.store_csv_line(row)
	file.close()
	var loaded := ContentLoader.new().load_csv_directory(dir)
	check(loaded.error.is_empty() and loaded.raw.resolutions.size() == 1, "CSV resolution accepted")
	if loaded.error.is_empty():
		check(loaded.raw.resolutions[0] == source_row and ContentLoader.new().validate(JSON.parse_string(JSON.stringify(loaded.raw))).raw == loaded.raw, "CSV and JSON share normalized resolution values")

func _test_v3_migration() -> void:
	var model := ItemCatalog.create_inventory()
	var initial := CombatResolver.new(model).snapshot()
	var doc: Dictionary = JSON.parse_string(JSON.parse_string(SaveCodec.encode(initial, model, [])).payload)
	doc.version = 3
	var before := SaveCodec._wrap(doc)
	var result := SaveCodec.new().decode(before, model)
	check(result.status == "ok" and result.get("migrated", false) and result.state == initial, "old version migrates unchanged data")
	doc.content_hash = "different"
	check(SaveCodec.new().decode(SaveCodec._wrap(doc), model).status == "incompatible", "old version with different content is not migrated")
	doc.content_hash = model.content_hash
	doc.state.event = {"method":"resolution"}
	check(SaveCodec.new().decode(SaveCodec._wrap(doc), model).status == "corrupt", "old version cannot invent new method")

func _test_run(kind: String) -> void:
	var slot := base.path_join(kind + ".json")
	var main := Experiment.create(root, slot)
	check(main != null and main.session.save_service != null, "isolated saved run created")
	if main == null: return
	saved(main, slot, "initial")
	check(submit(main, {"type":"start"}).is_empty() and combat(main), "first fight")
	check(submit(main, {"type":"reward_skip", "offer_id":main.session.display_snapshot().reward.offer_id}).is_empty(), "first reward")
	check(submit(main, {"type":"advance"}).is_empty(), "event opens")
	var event: Dictionary = main.session.display_snapshot().event
	check(submit(main, {"type":"event_take", "event_id":event.id}).is_empty(), "take")
	check(submit(main, {"type":"event_confirm", "event_id":event.id}).is_empty(), "confirm stashed evidence")
	saved(main, slot, "stashed confirmed evidence")
	check(submit(main, {"type":"choose_route", "route_id":main.inventory.config.routes[0].id}).is_empty(), "choose route")
	if kind == "resolution":
		check(main.session.stash("hat").is_empty() and main.session.place(event.uid, Vector2i(1,2), 0).is_empty(), "pack evidence")
	saved(main, slot, "preparation")
	check(submit(main, {"type":"start"}).is_empty(), "start second fight")
	if kind == "resolution":
		var original := FileAccess.get_file_as_string(slot)
		var file := FileAccess.open(slot, FileAccess.WRITE)
		file.store_string("external change")
		file.close()
		var before: Dictionary = main.session.state_snapshot()
		check(not main.session.submit({"type":"resolve_encounter"}).is_empty() and main.session.state_snapshot() == before, "conflict rejects resolution without mutation")
		file = FileAccess.open(slot, FileAccess.WRITE)
		file.store_string(original)
		file.close()
		check(main.session.submit({"type":"resolve_encounter"}).is_empty(), "resolve commits")
		check(main.session.display_snapshot().phase == "battle" and main.session.state_snapshot().phase == "event_result", "committed result waits for playback")
		saved(main, slot, "resolution during playback")
		var fresh := Experiment.create(root, slot)
		check(fresh != null and fresh.session.display_snapshot() == main.session.state_snapshot(), "new UI restores committed result without replay")
		if fresh != null:
			check(fresh.layout.encounter_event.description.text == Experiment.load_resolution().result, "restored resolution text visible")
			fresh.queue_free()
		main.session.skip_playback()
		var doc: Dictionary = JSON.parse_string(JSON.parse_string(FileAccess.get_file_as_string(slot)).payload)
		doc.state.event.selected = "leave"
		check(SaveCodec.new().decode(SaveCodec._wrap(doc), ItemCatalog.create_inventory(Experiment.CONTENT_PATH)).status == "corrupt", "forged result without evidence rejected")
	else:
		check(combat(main), "fight finishes")
		saved(main, slot, "combat result with pending reward")
	check(submit(main, {"type":"event_continue", "event_id":event.id}).is_empty() and main.session.display_snapshot().phase == "complete", "both endings complete")
	saved(main, slot, "completed ending")
	check(not main.session.submit({"type":"event_continue", "event_id":event.id}).is_empty(), "ending cannot repeat after restore")
	main.queue_free()
	await process_frame
