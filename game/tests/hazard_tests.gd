extends SceneTree

var checks := 0
var failures := 0
var folder := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	folder = ProjectSettings.globalize_path("res://../build/hazard-tests/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	_test_data()
	_test_costs()
	_test_previous_save()
	await _test_session()
	await _test_ui()
	print("HAZARD TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func battle_state(model: InventoryModel) -> Dictionary:
	var state := CombatResolver.new(model).snapshot()
	state.route = {"choice":state.config.routes[0].id, "step":1}
	state.encounter = state.config.routes[0].encounters[1]
	state.phase = "battle"
	state.enemy_health = state.config.encounters[state.encounter].hp
	return state

func _test_data() -> void:
	var loaded := ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH)
	check(loaded.error.is_empty() and loaded.raw.hazards.size() == 1, "shipping hazard validates")
	if not loaded.error.is_empty(): return
	var raw: Dictionary = loaded.raw
	for kind in ["outside", "duplicate_cell", "missing_tag", "unknown_tag", "bad_step", "duplicate_step", "zero_cost", "empty_label"]:
		var bad := raw.duplicate(true)
		match kind:
			"outside": bad.hazards[0].cells = "0:0|5:0"
			"duplicate_cell": bad.hazards[0].cells = "0:0|0:0"
			"missing_tag": bad.hazards[0].required_tags = ""
			"unknown_tag": bad.hazards[0].required_tags = "missing_tag"
			"bad_step": bad.hazards[0].step = 3
			"duplicate_step":
				var other: Dictionary = bad.hazards[0].duplicate(true)
				other.id = "other_hazard"
				bad.hazards.append(other)
			"zero_cost": bad.hazards[0].cost_increase = 0
			"empty_label": bad.hazards[0].label = ""
		check(not ContentLoader.new().validate(bad).error.is_empty(), "invalid hazard rejected: " + kind)
	var csv := ContentLoader.new().load_csv_directory(ProjectSettings.globalize_path("res://../content/source"))
	check(csv.error.is_empty() and csv.raw == raw, "CSV and shipping JSON match")
	var absent := raw.duplicate(true)
	absent.erase("hazards")
	var empty := absent.duplicate(true)
	empty.hazards = []
	check(ContentLoader.new().validate(absent).raw == ContentLoader.new().validate(empty).raw, "empty and absent hazards retain canonical form")
	check(ItemCatalog.from_validated(raw).content_hash != ItemCatalog.from_validated(ContentLoader.new().validate(absent).raw).content_hash, "hazard data contributes to content hash")

func _test_costs() -> void:
	var model := ItemCatalog.create_inventory()
	var initial := CombatResolver.new(model).snapshot()
	var state := battle_state(model)
	var weapon: Dictionary = state.packed_items.sword
	check(InventoryRules.active_hazards(initial).is_empty(), "first encounter is not frosted")
	check(InventoryRules.active_hazards(state).size() == 1, "second encounter is frosted")
	var cost := InventoryRules.action_cost(state, weapon)
	check(cost.base == 1 and cost.extra == 1 and cost.total == 2, "frosted weapon costs two")
	var multiple := weapon.duplicate(true)
	multiple.cells = [Vector2i(0,0),Vector2i(1,0),Vector2i(2,0)]
	check(InventoryRules.action_cost(state, multiple).extra == 1, "multiple cells apply penalty only once")
	multiple.cells = [Vector2i(1,1),Vector2i(2,1),Vector2i(3,1)]
	check(InventoryRules.action_cost(state, multiple).total == 1, "interior rotation avoids penalty")
	var nonweapon: Dictionary = state.packed_items.bell.duplicate(true)
	nonweapon.cells = [Vector2i(0,0)]
	check(InventoryRules.action_cost(state, nonweapon).total == nonweapon.cost, "unrelated item does not incur penalty")
	var before := state.duplicate(true)
	state.energy = 1
	var bad := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	check(not bad.error.is_empty() and bad.after() == state and bad.events().is_empty(), "insufficient energy rejects without mutation")
	state.energy = 2
	var valid := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	var repeated := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	check(valid.error.is_empty() and valid.after().energy == 0 and state.energy == 2, "simulation applies exact modified cost without changing input")
	check(valid.events() == repeated.events(), "same state produces deterministic event sequence")
	check(valid.events()[0].kind == "action_started" and valid.events()[0].cost == 2 and valid.events()[0].hazard_cost == 1, "event records cost and cause")
	check(before.packed_items == state.packed_items, "cost projection does not alter inventory")
	state.phase = "event_result"
	check(InventoryRules.active_hazards(state).is_empty(), "hazard clears after encounter")
	# An unaffordable only attack must not lock a player inside battle.
	state = battle_state(model)
	state.phase = "packing"
	state.config.energy_per_turn = 1
	state.energy = 1
	state.packed_items = {"sword":state.packed_items.sword}
	var start := CombatSimulator.resolve(state, {"type":"start"})
	check(not start.error.is_empty() and start.after() == state, "cannot start with no affordable attack")

func _test_previous_save() -> void:
	var raw: Dictionary = ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH).raw
	raw.erase("hazards")
	var previous := ItemCatalog.from_validated(ContentLoader.new().validate(raw).raw)
	var slot := folder.path_join("previous.json")
	var text := SaveCodec.encode(CombatResolver.new(previous).snapshot(), previous, [])
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var result := SaveService.new(slot).load_slot(ItemCatalog.create_inventory())
	check(result.status == "incompatible" and FileAccess.get_file_as_string(slot) == text, "previous catalog save is preserved on content mismatch")

func _test_session() -> void:
	var model := ItemCatalog.create_inventory()
	var slot := folder.path_join("save.json")
	var service := SaveService.new(slot)
	check(service.load_slot(model).status == "missing", "isolated save starts empty")
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = service
	var initial := battle_state(model)
	check(service.write_slot(initial, model, []).is_empty(), "isolated battle state saved")
	session.reset(model, initial)
	var before := session.display_snapshot()
	var original := FileAccess.get_file_as_string(slot)
	var changed := FileAccess.open(slot, FileAccess.WRITE)
	changed.store_string("external change")
	changed.close()
	check(not session.submit({"type":"use_item", "uid":"sword"}).is_empty() and session.state_snapshot() == before and session.display_snapshot() == before, "save conflict preserves both snapshots")
	check(FileAccess.get_file_as_string(slot) == "external change", "conflicting file remains untouched")
	changed = FileAccess.open(slot, FileAccess.WRITE)
	changed.store_string(original)
	changed.close()
	check(session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "hazard action submits")
	var committed := session.state_snapshot()
	check(committed.energy == 1 and session.display_snapshot() == before, "cost commits before display playback")
	var loaded := SaveService.new(slot).load_slot(ItemCatalog.create_inventory())
	check(loaded.status == "ok" and loaded.state == committed, "reopen restores calculated cost without replay")
	session.skip_playback()
	check(session.display_snapshot() == committed, "skip reconciles exactly to saved state")
	check(not session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "repeat remains blocked")
	session.queue_free()
	await process_frame

func _test_ui() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	var state := battle_state(main.inventory)
	state.phase = "packing"
	main.session.reset(main.inventory, state)
	await process_frame
	check(main.board.hazards.size() == 1 and main.board.hazards[0].cells.size() == 5, "preparation displays five hazard cells")
	check(main.labels.help.text.contains("costs +1 energy") and main.layout.guide.body.text.contains("Weapon costs +1 energy"), "rules visible before battle")
	main._select("sword")
	check(main.labels.item_meta.text.contains("Energy 2") and main.labels.item_meta.text.contains("Spirit's Chill +1"), "details show modified cost and source")
	check(main.session.stash("hat").is_empty(), "remove hat to create room")
	main.board.select("sword", 1)
	main.board.hover_cell = Vector2i(1,1)
	main._refresh_details()
	main._preview(Vector2i(1,1))
	check(main.labels.item_meta.text.contains("Energy 1") and main.labels.item_meta.text.contains("Placement Preview"), "candidate details show new cost")
	check(main.labels.notice.text.contains("energy 2 → 1"), "placement preview explains cost change")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/frost-preview.png"))
	check(main.session.place("sword", Vector2i(1,1), 1).is_empty(), "rotated sword fits inside")
	main._select("sword")
	check(main.labels.item_meta.text.contains("Energy 1") and not main.labels.item_meta.text.contains("Spirit's Chill +1"), "committed placement displays reduced cost")
	check(main.session.undo_layout().is_empty(), "undo restores frosted placement")
	main.board.hover_cell = Vector2i(-100,-100)
	main._select("sword")
	check(main.labels.item_meta.text.contains("Energy 2"), "undo updates displayed cost")
	check(main.session.submit({"type":"start"}).is_empty(), "begin frosted encounter")
	main.session.skip_playback()
	var before_cost: Dictionary = main.session.display_snapshot()
	check(main.session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "frosted attack is accepted")
	main.session.playback.queue._process(0)
	check(main.road.feedback_caption == "HAZARD +1 ENERGY" and not main.road.feedback_impact and main.session.display_snapshot().energy == before_cost.energy, "hazard caption waits for recorded cost impact")
	check(main.session.playback._event_duration >= 0.85, "cost explanation remains readable")
	var cost_command: CombatEventCommand = main.session.playback.queue._current
	cost_command._impact()
	check(main.road.feedback_impact and main.session.display_snapshot().energy == before_cost.energy - 2, "extra cost and displayed energy change together")
	main.session.skip_playback()
	check(main.road.feedback_caption.is_empty() and main.session.display_snapshot() == main.session.state_snapshot(), "skip clears the hazard caption and shows the committed result")
	main.queue_free()
	await process_frame
