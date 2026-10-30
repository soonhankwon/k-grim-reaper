extends SceneTree

const Experiment = preload("res://tests/multiplier_experiment_setup.gd")
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
	var loaded := ContentLoader.new().load_json(Experiment.CONTENT_PATH)
	check(loaded.error.is_empty(), "experiment data validates")
	if not loaded.error.is_empty():
		quit(1)
		return
	var raw: Dictionary = loaded.raw
	var model := ItemCatalog.from_validated(raw)
	var result := model.action_result("sword")
	check(result.error.is_empty() and result.power == 16, "base 6 plus 2, multiplied by 2 equals 16")
	check(result.sources == ["봉인부 +2", "실험용 배율 옥가락지 ×2"], "preview attributes addition and multiplier separately")
	var plan: Dictionary = result.effects[0]
	check(plan.base == 6 and plan.bonuses.size() == 1 and plan.multipliers.size() == 1, "plan preserves calculation components")
	var text := " ".join(EffectText.lines(model.combat_snapshot().sword, model.combat_snapshot(), "sword"))
	check("Attack 16" in text and not text.contains("Calculation:"), "item description shows final power without a raw formula")
	check(model.preview("seal", Vector2i(1,0), 0).attacks.sword == 12, "preview moving addition recalculates before multiplication")
	check(model.preview("ring", Vector2i(0,0), 0).attacks.sword == 8, "preview moving multiplier removes it")
	await _test_combat(raw)
	_test_validation(raw)
	_test_stacking(raw)
	_test_ranges(raw)
	_test_limits(raw)
	await _test_atomic_save(raw)
	_test_csv()
	await _test_ui()
	print("MULTIPLIER TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_combat(raw: Dictionary) -> void:
	var model := ItemCatalog.from_validated(raw)
	var session := BattleSession.new()
	root.add_child(session)
	session.reset(model)
	check(session.submit({"type":"start"}).is_empty(), "battle starts")
	session.skip_playback()
	var before := session.display_snapshot()
	var request := {"type":"use_item", "uid":"sword"}
	var simulated := CombatSimulator.resolve(before, request)
	var tape := simulated.events()
	check(simulated.error.is_empty() and simulated.after().enemy_health == 2, "actual damage matches 16 preview")
	check(tape.map(func(event): return event.kind) == ["action_started", "adjacency_bonus", "power_multiplier", "damage"], "event order is addition then multiplier then damage")
	check(tape[2].cause_id == tape[1].id and tape[3].cause_id == tape[2].id and tape[2].factor == 2, "multiplier event has causal link and factor")
	check(session.submit(request).is_empty(), "session submits the same command")
	check(session.display_snapshot().enemy_health == before.enemy_health and session.state_snapshot() == simulated.after(), "playback does not show committed damage early")
	session.skip_playback()
	check(session.display_snapshot() == simulated.after(), "skip presents committed result")
	session.queue_free()
	await process_frame

func _test_validation(raw: Dictionary) -> void:
	var bad := raw.duplicate(true)
	var effect: Dictionary = ContentLoader.index(bad.effects).fixture_multiplier
	effect.amount = 0
	check(not ContentLoader.new().validate(bad).error.is_empty(), "zero factor rejected")
	effect.amount = -1
	check(not ContentLoader.new().validate(bad).error.is_empty(), "negative factor rejected")
	effect.amount = 1.5
	check(not ContentLoader.new().validate(bad).error.is_empty(), "fractional factor rejected")
	effect.amount = 2
	effect.scale = "per_neighbor"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "scaled factor rejected")
	effect.scale = "flat"
	effect.trigger = "use"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "multiplier cannot be an executable effect")
	check(ContentLoader.new().validate(JSON.parse_string(JSON.stringify(raw))).raw == raw, "JSON roundtrip keeps factor")

func _test_stacking(raw: Dictionary) -> void:
	var stacked := raw.duplicate(true)
	var effects := ContentLoader.index(stacked.effects)
	effects.seal_bonus.stack_group = "shared"
	effects.fixture_multiplier.stack_group = "shared"
	var second: Dictionary = effects.fixture_multiplier.duplicate(true)
	second.id = "fixture_multiplier_second"
	second.amount = 3
	second.priority = 1
	stacked.effects.append(second)
	ContentLoader.index(stacked.items).ring.effect_ids += "|fixture_multiplier_second"
	var model := ItemCatalog.from_validated(ContentLoader.new().validate(stacked).raw)
	check(model.action_result("sword").power == 16, "same multiplier group uses first priority; additive group is independent")
	second.priority = -1
	model = ItemCatalog.from_validated(ContentLoader.new().validate(stacked).raw)
	check(model.action_result("sword").power == 24, "multiplier group respects priority")
	second.stack_group = ""
	model = ItemCatalog.from_validated(ContentLoader.new().validate(stacked).raw)
	check(model.action_result("sword").power == 48, "separate multipliers compound")
	check(model.action_result("sword").effects[0].multipliers.map(func(entry): return entry.factor) == [3, 2], "multipliers have deterministic priority order")

func _overflow_data(raw: Dictionary, owner: String, affects: String) -> Dictionary:
	var data := raw.duplicate(true)
	var indexes := ContentLoader.index(data.effects)
	var item: Dictionary = ContentLoader.index(data.items)[owner]
	var base: Dictionary = indexes.fixture_multiplier
	base.target = "self"
	base.required_tags = ""
	base.amount = 100000
	base.affects = affects
	var ids: Array[String] = ["fixture_multiplier"]
	for i in 3:
		var copy: Dictionary = base.duplicate(true)
		copy.id = "fixture_extra_%d" % i
		data.effects.append(copy)
		ids.append(copy.id)
	item.effect_ids += "|" + "|".join(ids)
	if owner != "ring": ContentLoader.index(data.items).ring.effect_ids = ""
	return data

func _test_ranges(raw: Dictionary) -> void:
	var ranged := raw.duplicate(true)
	ContentLoader.index(ranged.effects).fixture_multiplier.target = "diagonal_items"
	var row: Dictionary = ContentLoader.index(ranged.loadout).ring
	row.x = 4
	row.y = 3
	var validated := ContentLoader.new().validate(ranged)
	check(validated.error.is_empty(), "diagonal multiplier data validates")
	var model := ItemCatalog.from_validated(validated.raw)
	check(model.action_result("sword").power == 16, "diagonal multiplier composes with orthogonal additive bonus")
	check(model.place("ring", Vector2i(0,0), 0) and model.action_result("sword").power == 8, "diagonal multiplier disappears outside range")
	var self_data := raw.duplicate(true)
	var multiplier: Dictionary = ContentLoader.index(self_data.effects).fixture_multiplier
	multiplier.target = "self"
	multiplier.required_tags = ""
	multiplier.affects = "guard"
	ContentLoader.index(self_data.items).ring.effect_ids = ""
	ContentLoader.index(self_data.items).hat.effect_ids += "|fixture_multiplier"
	var self_model := ItemCatalog.from_validated(ContentLoader.new().validate(self_data).raw)
	check(self_model.action_result("hat").power == 10, "self multiplier applies to defense")
	var battle := CombatResolver.new(self_model)
	battle.start_battle()
	battle.use_item("hat")
	check(battle.guard == 10, "guard action uses the same multiplied value")

func _test_limits(raw: Dictionary) -> void:
	var overflow := _overflow_data(raw, "sword", "damage")
	# Remove the ring's copy so it cannot apply the same effect twice.
	ContentLoader.index(overflow.items).ring.effect_ids = ""
	var valid := ContentLoader.new().validate(overflow)
	check(valid.error.is_empty(), "large multipliers are valid authored data")
	var model := ItemCatalog.from_validated(valid.raw)
	var preview := model.action_result("sword")
	check(not preview.error.is_empty() and "limit" in " ".join(EffectText.lines(model.combat_snapshot().sword, model.combat_snapshot(), "sword")), "overflow is shown as an error, not a number")
	check(not InventoryRules.totals(model.combat_snapshot(), "use", "enemy").error.is_empty(), "aggregate preview propagates overflow")
	var boundary_items := ItemCatalog.from_validated(raw).combat_snapshot()
	boundary_items.sword.effects[0].amount = 3002399751580330
	boundary_items.seal.effects[0].amount = 0
	boundary_items.ring.effects[0].amount = 3
	var boundary := EffectApplier.plan(boundary_items, "sword", "use")[0]
	check(boundary.error.is_empty() and boundary.amount == 9007199254740990, "exact integer boundary is accepted")
	boundary_items.sword.effects[0].amount += 1
	check(not EffectApplier.plan(boundary_items, "sword", "use")[0].error.is_empty(), "one step beyond exact boundary is rejected")
	var battle := CombatResolver.new(model)
	battle.start_battle()
	var before := battle.snapshot()
	var rejected := CombatSimulator.resolve(before, {"type":"use_item", "uid":"sword"})
	check(not rejected.error.is_empty() and rejected.after() == before and rejected.events().is_empty(), "overflow rejects the entire action including cost")
	var end_data := _overflow_data(raw, "lantern", "guard")
	var guard: Dictionary = ContentLoader.index(end_data.effects).lantern_guard
	guard.scale = "flat"
	guard.condition_tags = ""
	var end_model := ItemCatalog.from_validated(ContentLoader.new().validate(end_data).raw)
	var end_battle := CombatResolver.new(end_model)
	end_battle.start_battle()
	before = end_battle.snapshot()
	rejected = CombatSimulator.resolve(before, {"type":"end_turn"})
	check(not rejected.error.is_empty() and rejected.after() == before and rejected.events().is_empty(), "automatic guard overflow rejects the complete turn")
	var reaction_data := _overflow_data(raw, "ring", "damage")
	var response: Dictionary = ContentLoader.index(reaction_data.effects).sword_use.duplicate(true)
	response.id = "fixture_reaction"
	response.trigger = "damage_taken"
	response.amount = 6
	reaction_data.effects.append(response)
	ContentLoader.index(reaction_data.items).ring.effect_ids = "fixture_reaction|fixture_multiplier|fixture_extra_0|fixture_extra_1|fixture_extra_2"
	var reaction_model := ItemCatalog.from_validated(ContentLoader.new().validate(reaction_data).raw)
	var reaction_battle := CombatResolver.new(reaction_model)
	reaction_battle.start_battle()
	before = reaction_battle.snapshot()
	rejected = CombatSimulator.resolve(before, {"type":"end_turn"})
	check(not rejected.error.is_empty() and rejected.after() == before and rejected.events().is_empty(), "reactive overflow rolls back enemy damage and all prior events")
	var guard_state := before.duplicate(true)
	guard_state.guard = EffectApplier.MAX_EXACT
	var overguard := EffectApplier.evaluate(guard_state, {"kind":"guard", "target":"player", "amount":1, "label":"test"})
	check(overguard.has("error"), "guard accumulation respects exact save limit")
	var dead_data := _overflow_data(raw, "ring", "guard")
	var dead_response: Dictionary = ContentLoader.index(dead_data.effects).hat_use.duplicate(true)
	dead_response.id = "fixture_dead_guard"
	dead_response.trigger = "damage_taken"
	dead_response.amount = 6
	dead_data.effects.append(dead_response)
	ContentLoader.index(dead_data.items).ring.effect_ids = "fixture_dead_guard|fixture_multiplier|fixture_extra_0|fixture_extra_1|fixture_extra_2"
	var dead_model := ItemCatalog.from_validated(ContentLoader.new().validate(dead_data).raw)
	var dead_battle := CombatResolver.new(dead_model)
	dead_battle.start_battle()
	var dead := dead_battle.snapshot()
	dead.health = 1
	var death := CombatSimulator.resolve(dead, {"type":"end_turn"})
	check(death.error.is_empty() and death.after().phase == "defeat", "overflowing reaction targeting a dead player is skipped")

func _test_atomic_save(raw: Dictionary) -> void:
	var invalid := _overflow_data(raw, "sword", "damage")
	ContentLoader.index(invalid.items).ring.effect_ids = ""
	var model := ItemCatalog.from_validated(ContentLoader.new().validate(invalid).raw)
	var slot := ProjectSettings.globalize_path("res://../build/multiplier-save-%d.json" % OS.get_process_id())
	var service := SaveService.new(slot)
	check(service.load_slot(model).status == "missing", "isolated save starts empty")
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = service
	check(session.prepare_new(model).is_empty(), "isolated save initializes")
	session.reset(model)
	check(session.submit({"type":"start"}).is_empty(), "battle start saves")
	session.skip_playback()
	var before := session.state_snapshot()
	var digest := FileAccess.get_sha256(slot)
	check(not session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "session rejects overflow")
	check(session.state_snapshot() == before and FileAccess.get_sha256(slot) == digest, "failed action preserves state and saved bytes")
	session.queue_free()
	DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(slot + ".bak")
	await process_frame

func _test_csv() -> void:
	var dir := ProjectSettings.globalize_path("res://../build/multiplier-csv-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var source := ProjectSettings.globalize_path("res://../content/source")
	for name in ["items.csv", "tags.csv", "loadout.csv", "encounters.csv", "rules.csv", "rewards.csv", "routes.csv", "events.csv", "resolutions.csv", "hazards.csv", "art.json", "effects.csv"]:
		check(DirAccess.copy_absolute(source.path_join(name), dir.path_join(name)) == OK, "copy isolated CSV " + name)
	var effect_file := FileAccess.open(dir.path_join("effects.csv"), FileAccess.READ_WRITE)
	effect_file.seek_end()
	effect_file.store_csv_line(PackedStringArray(["fixture_multiplier", "modify", "multiply_power", "adjacent_items", "2", "weapon", "", "flat", "1", "damage", "", "1", "0"]))
	effect_file.close()
	var item_path := dir.path_join("items.csv")
	var input := FileAccess.open(item_path, FileAccess.READ)
	var rows: Array[PackedStringArray] = []
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() == 1 and row[0].is_empty(): continue
		if row[0] == "ring": row[9] = "fixture_multiplier"
		rows.append(row)
	input.close()
	var output := FileAccess.open(item_path, FileAccess.WRITE)
	for row in rows: output.store_csv_line(row)
	output.close()
	var loaded := ContentLoader.new().load_csv_directory(dir)
	check(loaded.error.is_empty(), "CSV accepts integer multiplier")
	if loaded.error.is_empty():
		var unit: Dictionary = ContentLoader.index(loaded.raw.effects).fixture_multiplier
		check(unit.amount == 2 and unit.operation == "multiply_power", "CSV keeps authored factor")
		var json := ContentLoader.new().validate(JSON.parse_string(JSON.stringify(loaded.raw)))
		check(json.error.is_empty() and json.raw == loaded.raw, "CSV and JSON use the same validator")
		var model := ItemCatalog.from_validated(json.raw)
		check(model.place("seal", Vector2i(2,1), 0) and model.place("ring", Vector2i(4,2), 0) and model.action_result("sword").power == 16, "CSV-to-resource data executes the multiplier")

func _test_ui() -> void:
	root.size = Vector2i(1280, 720)
	var main := Experiment.create(root)
	await process_frame
	check(not main.save_enabled and main.session.save_service == null, "experiment cannot read or write player saves")
	main._select("sword")
	check(not main.labels.power.text.contains("Calculation:") and main.layout.synergy_breakdown.rows.any(func(row): return row.base == 6 and row.amount == 16 and row.bonuses.any(func(bonus): return bonus.amount == 2) and row.multipliers.any(func(mult): return mult.factor == 2)), "visible icon breakdown explains the combination")
	main._select("ring")
	main._preview(Vector2i(0,0))
	check(main.labels.notice.text.contains("16 → 8"), "placement preview shows multiplier loss")
	main._reset_run()
	check(main.inventory.action_result("sword").power == 16 and main.session.save_service == null, "restart restores experiment without enabling saves")
	main.queue_free()
	await process_frame
