extends SceneTree

var checks := 0
var failures := 0
var raw: Dictionary

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func reject(value: Dictionary, label: String) -> void:
	check(not ContentLoader.new().validate(value).error.is_empty(), label)

func make_model(value: Dictionary) -> InventoryModel:
	var validated := ContentLoader.new().validate(value)
	check(validated.error.is_empty(), "fixture validates: " + str(validated.error))
	return ItemCatalog.from_validated(validated.raw) if validated.error.is_empty() else null

func effect(id: String, operation: String, amount: int, trigger := "use", target := "self") -> Dictionary:
	return {"id": id, "trigger": trigger, "operation": operation, "target": target, "amount": amount,
		"required_tags": "", "condition_tags": "", "scale": "flat", "max_matches": 1, "affects": "",
		"stack_group": "", "max_per_action": 1, "priority": 0}

func _initialize() -> void:
	var loaded := ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH)
	check(loaded.error.is_empty(), "shipping JSON validates")
	if not loaded.error.is_empty():
		quit(1)
		return
	var shipping := ItemCatalog.create_inventory()
	check(shipping != null and shipping.definitions.size() == loaded.raw.items.size(), "shipping definitions load independently of balance fixtures")
	raw = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	var csv := ContentLoader.new().load_csv_directory(ProjectSettings.globalize_path("res://../content/source"))
	check(csv.error.is_empty(), "Google Sheets CSV source parses")
	check(csv.error.is_empty() and ContentLoader.new().validate(JSON.parse_string(JSON.stringify(csv.raw))).raw == csv.raw, "CSV-to-JSON roundtrip preserves normalized content")
	_test_validation()
	_test_unrecognized_names()
	_test_composition()
	_test_zero_assignment()
	_test_equipment_reactions()
	_test_csv()
	_test_scale()
	print("CONTENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_validation() -> void:
	var bad := raw.duplicate(true)
	bad.schema_version = 999
	reject(bad, "unknown schema version rejected")
	bad = raw.duplicate(true)
	bad.items.append(bad.items[0].duplicate(true))
	reject(bad, "duplicate item IDs rejected")
	bad = raw.duplicate(true)
	bad.effects[0].amount = 1.5
	reject(bad, "fractional integer rejected instead of truncated")
	bad.effects[0].amount = true
	reject(bad, "boolean is not an amount")
	bad.effects[0].amount = "#REF!"
	reject(bad, "spreadsheet error cannot enter numeric fields")
	bad.effects[0].amount = "=6*2"
	reject(bad, "formula text is never executed")
	bad.effects[0].amount = -1
	reject(bad, "negative unsigned amount rejected")
	bad = raw.duplicate(true)
	bad.items[0].effect_ids = "not_registered"
	reject(bad, "unresolved effect reference rejected")
	bad.items[0].effect_ids = "sword_use|sword_use"
	reject(bad, "duplicate composition reference rejected")
	bad = raw.duplicate(true)
	bad.items[0].tags = "unknown_tag"
	reject(bad, "tag typo rejected")
	bad = raw.duplicate(true)
	bad.effects[0].operation = "run_script"
	reject(bad, "unknown operation rejected")
	bad = raw.duplicate(true)
	bad.effects[0].required_tags = "weapon"
	reject(bad, "modifier-only fields rejected on executable effects")
	bad = raw.duplicate(true)
	bad.items[0].footprint = "0:0|0:0"
	reject(bad, "duplicate footprint cells rejected")
	bad.items[0].footprint = "-1:0"
	reject(bad, "negative footprint cell rejected")
	bad = raw.duplicate(true)
	bad.loadout[1].x = 3
	reject(bad, "overlapping initial layout rejected atomically")
	bad = raw.duplicate(true)
	bad.items[0].icon_id = "not_registered"
	reject(bad, "unresolved visual rejected")
	bad = raw.duplicate(true)
	bad.art.icons.sword.parts[0][4] = 999
	reject(bad, "invalid palette index rejected before rendering")
	bad = raw.duplicate(true)
	bad.encounters[0].intent_ids = "seal_bonus"
	reject(bad, "enemy cannot execute a modifier as an intent")
	bad = raw.duplicate(true)
	bad.effects[0].typo = 1
	reject(bad, "unknown field rejected")
	var reused := ContentLoader.new()
	reused.load_json("res://not_present.json")
	check(reused.load_json("res://tests/fixtures/baseline.json").error.is_empty(), "loader recovers after a failed read")

func _test_unrecognized_names() -> void:
	var renamed := raw.duplicate(true)
	var map: Dictionary = {}
	for table in ["items", "effects", "tags", "loadout", "encounters", "rules", "rewards", "routes", "events"]:
		for row: Dictionary in renamed[table]: map[row.id] = "new_" + str(row.id)
	for table in ["items", "effects", "tags", "loadout", "encounters", "rules", "rewards", "routes", "events"]:
		for row: Dictionary in renamed[table]:
			row.id = map[row.id]
			for key in ["tags", "effect_ids", "required_tags", "condition_tags", "intent_ids", "reaction_ids"]:
				if row.has(key):
					var values: PackedStringArray = []
					for id in ContentLoader.split_ids(row[key]): values.append(map[id])
					row[key] = "|".join(values)
			if row.has("item_id"): row.item_id = map[row.item_id]
	var model := make_model(renamed)
	if model == null: return
	model.place("new_seal", Vector2i(2,1), 0)
	model.place("new_ring", Vector2i(0,0), 0)
	check(model.action_result("new_sword").power == 8 and model.passive_guard() == 4, "arbitrary IDs and tag names retain all effects")
	var battle := CombatResolver.new(model)
	battle.start_battle()
	battle.use_item("new_sword")
	check(battle.enemy_health == 10 and battle.energy == 2, "renamed content executes without engine changes")

func _test_composition() -> void:
	var composed := raw.duplicate(true)
	composed.effects.append_array([effect("a_hit", "damage", 5, "use", "opponent"), effect("b_ward", "guard", 3), effect("c_mend", "heal", 4)])
	var item: Dictionary = composed.items[0]
	item.effect_ids = "c_mend|a_hit|b_ward"
	item.uses_per_turn = 2
	var model := make_model(composed)
	if model == null: return
	var initial := CombatSimulator.initial_state(model.config)
	initial.health = 20
	var battle := CombatResolver.new(model, initial)
	battle.start_battle()
	var result := battle.submit({"type": "use_item", "uid": "sword"})
	check(result.error.is_empty() and battle.energy == 2 and battle.guard == 3 and battle.health == 24 and battle.enemy_health == 13, "three units compose and charge energy once")
	check(result.events().map(func(e): return e.kind) == ["action_started", "damage", "guard", "heal"], "priority/ID determines effect order, not cell order")
	battle.use_item("sword")
	check(battle.energy == 1 and battle.health == 28 and battle.guard == 6, "data-defined two uses and health cap")
	check(not battle.use_item("sword").is_empty() and battle.energy == 1, "third use rejected without spending")
	var copy := model.combat_snapshot()
	copy.sword.effects[0].amount = 999
	check(model.definition("sword").effects[0].amount != 999, "resource definitions detached from simulation snapshots")
	composed.rules[0].max_health = 40
	composed.rules[0].energy_per_turn = 5
	composed.encounters[0].intent_ids = "c_mend"
	model = make_model(composed)
	initial = CombatSimulator.initial_state(model.config)
	battle = CombatResolver.new(model, initial)
	battle.start_battle()
	battle.use_item("sword")
	battle.end_turn()
	check(battle.health == 40 and battle.energy == 5 and battle.enemy_health == 17, "rules and enemy healing are data-driven with per-target maxima")

func _test_zero_assignment() -> void:
	var composed := raw.duplicate(true)
	composed.effects.append_array([effect("a_self_hit", "damage", 1), effect("b_guard", "guard", 4),
		effect("clear_on_hit", "set_guard", 0, "damage_taken"), effect("clear_on_end", "set_guard", 0, "turn_end")])
	ContentLoader.index(composed.items).hat.effect_ids = "a_self_hit|b_guard|clear_on_hit|clear_on_end"
	var model := make_model(composed)
	if model == null: return
	var battle := CombatResolver.new(model)
	battle.start_battle()
	var result := battle.submit({"type": "use_item", "uid": "hat"})
	check(result.error.is_empty() and battle.health == 27 and battle.guard == 0 and result.events()[-1].kind == "set_guard", "zero assignment reaction clears guard after queued composite effects")
	battle.use_item("mirror")
	result = battle.submit({"type": "end_turn"})
	check(result.error.is_empty() and battle.health == 22 and result.events()[0].kind == "set_guard", "turn-end zero assignment executes before enemy hit")

func _test_equipment_reactions() -> void:
	var reactive := raw.duplicate(true)
	reactive.effects.append(effect("enemy_thorns", "damage", 3, "damage_taken", "opponent"))
	reactive.effects.append(effect("reactive_ward", "guard", 5, "damage_taken"))
	reactive.encounters[0].reaction_ids = "enemy_thorns"
	ContentLoader.index(reactive.items).hat.effect_ids += "|reactive_ward"
	var model := make_model(reactive)
	if model == null: return
	var battle := CombatResolver.new(model)
	battle.start_battle()
	var result := battle.submit({"type": "use_item", "uid": "sword"})
	check(battle.health == 25 and battle.guard == 5 and battle.enemy_health == 12, "equipped reaction plus enemy reaction follows cascade")
	check(result.events()[-1].cause_id == result.events()[-2].id, "data reactions preserve cause IDs")
	model = make_model(reactive)
	model.move_to_stash("hat")
	battle = CombatResolver.new(model)
	battle.start_battle()
	battle.use_item("sword")
	check(battle.guard == 0 and battle.health == 25, "stashed items cannot react")
	# Consumption drops its reaction definition at the same atomic commit as the item.
	ContentLoader.index(reactive.items).sword.consumable = true
	ContentLoader.index(reactive.items).sword.effect_ids += "|reactive_ward"
	model = make_model(reactive)
	model.move_to_stash("hat")
	battle = CombatResolver.new(model)
	battle.start_battle()
	battle.use_item("sword")
	check(battle.guard == 5 and not model.items.has("sword"), "consumable reacts within its root before removal")
	battle.end_turn()
	battle.end_turn()
	check(battle.health == 18, "consumed reaction cannot leak into later turns")
	# A data-driven reflection cycle observes the same root limit and death timing.
	var reflected := reactive.duplicate(true)
	ContentLoader.index(reflected.items).sword.consumable = false
	reflected.effects.append(effect("player_thorns", "damage", 1, "damage_taken", "opponent"))
	ContentLoader.index(reflected.items).sword.effect_ids = "sword_use|player_thorns"
	model = make_model(reflected)
	battle = CombatResolver.new(model)
	battle.start_battle()
	result = battle.submit({"type": "use_item", "uid": "sword"})
	check(result.error.is_empty() and result.events().size() < 10, "data reflection triggers only once per root")

func _test_csv() -> void:
	var temporary := ProjectSettings.globalize_path("res://../build/content-test")
	DirAccess.make_dir_recursive_absolute(temporary)
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ContentLoader.SCHEMA_PATH))
	for table in ["items", "effects", "tags", "loadout", "encounters", "rules", "rewards", "routes", "events", "resolutions"]:
		var csv := FileAccess.open(temporary.path_join(table + ".csv"), FileAccess.WRITE)
		var columns: Array = schema.tables[table].keys()
		csv.store_csv_line(PackedStringArray(columns))
		for row: Dictionary in raw.get(table, []):
			var values: PackedStringArray = []
			for key: String in columns: values.append(str(row[key]))
			csv.store_csv_line(values)
		csv.close()
	var art := FileAccess.open(temporary.path_join("art.json"), FileAccess.WRITE)
	art.store_string(JSON.stringify(raw.art))
	art.close()
	var file := FileAccess.open(temporary.path_join("items.csv"), FileAccess.WRITE)
	var headers: Array = raw.items[0].keys()
	file.store_string("\ufeff")
	file.store_csv_line(PackedStringArray(headers))
	for row: Dictionary in raw.items:
		var values: PackedStringArray = []
		for key: String in headers: values.append("쉼표, 따옴표 \"텍스트\"\n두 번째 줄" if key == "description" else str(row[key]))
		file.store_csv_line(values)
	file.close()
	var loaded := ContentLoader.new().load_csv_directory(temporary)
	check(loaded.error.is_empty() and loaded.raw.items[0].description.contains("\n"), "CSV handles BOM, quoted commas, quotes and multiline Korean")
	file = FileAccess.open(temporary.path_join("effects.csv"), FileAccess.WRITE)
	file.store_string("id,id\nbad,bad\n")
	file.close()
	check(not ContentLoader.new().load_csv_directory(temporary).error.is_empty(), "duplicate CSV headers rejected")

func _test_scale() -> void:
	var expanded := raw.duplicate(true)
	for i in 500:
		var item: Dictionary = raw.items[0].duplicate(true)
		item.id = "generated_%04d" % i
		expanded.items.append(item)
	var loaded := ContentLoader.new().validate(expanded)
	check(loaded.error.is_empty(), "500 extra test definitions validate without content code")
	if not loaded.error.is_empty(): return
	var model := ItemCatalog.from_validated(loaded.raw)
	check(model.definitions.size() == 512 and model.items.size() == 12, "catalog capacity and run loadout remain separate")
	var state := CombatSimulator.initial_state(model.config)
	var values := model.combat_snapshot().values()[0] as Dictionary
	for i in 65: state.packed_items["active_%d" % i] = values.duplicate(true)
	var limited := CombatSimulator.resolve(state, {"type": "start"})
	check(not limited.error.is_empty() and limited.after() == state, "planning budget rejects oversized active set before expensive interpretation")
