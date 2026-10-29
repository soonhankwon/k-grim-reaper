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
	var center := {"cells": [Vector2i(1, 1)]}
	var edge := {"cells": [Vector2i(2, 1)]}
	var corner := {"cells": [Vector2i(2, 2)]}
	check(GridRules.in_range(center, edge, "orthogonal") and not GridRules.in_range(center, edge, "diagonal"), "orthogonal and diagonal differ")
	check(GridRules.in_range(center, corner, "diagonal") and not GridRules.in_range(center, corner, "orthogonal"), "corner only matches diagonal")
	check(GridRules.in_range(center, edge, "neighbor") and GridRules.in_range(center, corner, "neighbor"), "union matches both kinds of contact")
	check(not GridRules.in_range(center, center, "neighbor") and not GridRules.in_range(center, corner, "unknown"), "same cell and unknown mode do not match")
	var l_shape := {"cells": GridRules.cells([Vector2i(0,0), Vector2i(0,1), Vector2i(1,1)], 0)}
	var corner_touch := {"cells": [Vector2i(2,0)]}
	check(GridRules.in_range(l_shape, corner_touch, "diagonal"), "diagonal contact works with irregular footprints")
	for rotation in 4:
		var rotated := {"cells": GridRules.cells([Vector2i(0,0), Vector2i(0,1), Vector2i(1,1)], rotation)}
		check(rotated.cells.size() == 3 and GridRules.in_range(rotated, {"cells":[Vector2i(-1,-1)]}, "diagonal") == rotated.cells.has(Vector2i.ZERO), "rotation uses transformed occupied cells")
	var source := ContentLoader.new().load_json("res://tests/fixtures/baseline.json")
	var experiment := ContentLoader.new().load_json("res://tests/fixtures/diagonal-experiment.json")
	check(experiment.error.is_empty(), "isolated playable diagonal fixture validates")
	if experiment.error.is_empty():
		var demo := ItemCatalog.from_validated(experiment.raw)
		check(demo.action_result("sword").power == 8, "playable experiment starts with a visible diagonal bonus")
		check(demo.place("seal", Vector2i(1,0), 0) and demo.action_result("sword").power == 6, "moving test talisman away removes bonus")
	var raw: Dictionary = source.raw.duplicate(true)
	var effects := ContentLoader.index(raw.effects)
	effects.seal_bonus.target = "diagonal_items"
	effects.lantern_guard.scale = "per_diagonal"
	var validated := ContentLoader.new().validate(raw)
	check(validated.error.is_empty(), "new range values validate for JSON content")
	var roundtrip := ContentLoader.new().validate(JSON.parse_string(JSON.stringify(raw)))
	check(roundtrip.error.is_empty() and roundtrip.raw == validated.raw, "JSON roundtrip retains range values")
	var bad := raw.duplicate(true)
	ContentLoader.index(bad.effects).sword_use.target = "diagonal_items"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "execute effects cannot target item ranges")
	bad = raw.duplicate(true)
	ContentLoader.index(bad.effects).seal_bonus.target = "opponent"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "modifier cannot target actors")
	bad = raw.duplicate(true)
	ContentLoader.index(bad.effects).lantern_guard.scale = "per_diagonall"
	check(not ContentLoader.new().validate(bad).error.is_empty(), "unknown range rejected")
	if validated.error.is_empty(): await _test_battle(validated.raw)
	_test_range_dedup(raw)
	_test_csv()
	print("DIAGONAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_battle(raw: Dictionary) -> void:
	var model := ItemCatalog.from_validated(raw)
	for uid: String in model.items.keys():
		if model.is_packed(uid): model.move_to_stash(uid)
	check(model.place("sword", Vector2i(1,0), 0) and model.place("seal", Vector2i(0,3), 0), "test items fit with diagonal-only contact")
	check(model.action_result("sword").power == 8, "diagonal modifier applies to weapon")
	check("대각선 물건" in " ".join(EffectText.lines(model.combat_snapshot().seal, model.combat_snapshot(), "seal")), "effect text describes diagonal target")
	var session := BattleSession.new()
	root.add_child(session)
	session.reset(model)
	check(session.submit({"type":"start"}).is_empty(), "diagonal setup enters battle")
	session.skip_playback()
	var before := session.display_snapshot()
	check(session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "modified attack submits")
	check(session.state_snapshot().enemy_health == before.enemy_health - 8, "combat equals inventory preview")
	check(session.display_snapshot().enemy_health == before.enemy_health, "prediction does not leak into playback")
	session.skip_playback()
	check(session.display_snapshot().enemy_health == before.enemy_health - 8, "playback reaches modified result")
	session.queue_free()
	await process_frame
	model = ItemCatalog.from_validated(raw)
	for uid: String in model.items.keys():
		if model.is_packed(uid): model.move_to_stash(uid)
	check(model.place("sword", Vector2i(3,0), 0) and model.place("lantern", Vector2i(1,0), 0) and model.place("ring", Vector2i(0,2), 0), "conditional diagonal fixture fits")
	check(model.passive_guard() == 4, "diagonal conditional scaling applies")
	var battle := CombatResolver.new(model)
	battle.start_battle()
	var result := CombatSimulator.resolve(battle.snapshot(), {"type":"end_turn"})
	check(result.error.is_empty() and result.after().health == model.config.max_health - 1, "turn-end simulation uses diagonal guard")
	check("대각선" in " ".join(EffectText.lines(model.combat_snapshot().lantern, model.combat_snapshot(), "lantern")), "effect text describes diagonal scaling")

func _test_range_dedup(raw: Dictionary) -> void:
	var model := ItemCatalog.from_validated(raw)
	var use := ItemCodec.effect(model.definitions.sword.effects[0])
	var modifier := ItemCodec.effect(model.definitions.seal.effects[0])
	modifier.target = "neighbor_items"
	modifier.stack_group = ""
	var items := {"x":{"name":"X", "cells":[Vector2i(1,0), Vector2i(1,1)], "tags":["weapon"], "effects":[use]},
		"y":{"name":"Y", "cells":[Vector2i(0,0), Vector2i(0,1)], "tags":[], "effects":[modifier]}}
	var plan := EffectApplier.plan(items, "x", "use")
	check(plan.size() == 1 and plan[0].amount == 8 and plan[0].bonuses.size() == 1, "multiple orthogonal and diagonal contacts apply modifier once")
	modifier.scale = "per_neighbor"
	modifier.condition_tags = ["weapon"]
	modifier.max_matches = 5
	plan = EffectApplier.plan(items, "x", "use")
	check(plan[0].amount == 8 and plan[0].bonuses.size() == 1, "union scaling counts one multi-cell instance once")
	items.z = {"name":"Z", "cells":[Vector2i(0,2)], "tags":["weapon"], "effects":[]}
	plan = EffectApplier.plan(items, "x", "use")
	check(plan[0].amount == 10, "separate matching instances both contribute")
	modifier.max_matches = 1
	check(EffectApplier.plan(items, "x", "use")[0].amount == 8, "max_matches caps matching instances")
	modifier.max_matches = 5
	modifier.target = "diagonal_items"
	items.y.cells = [Vector2i(0,0)]
	items.x.cells = [Vector2i(1,0)]
	plan = EffectApplier.plan(items, "x", "use")
	check(plan[0].amount == 6, "orthogonal-only contact does not activate diagonal modifier")

func _test_csv() -> void:
	var dir := ProjectSettings.globalize_path("res://../build/diagonal-csv-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var source := ProjectSettings.globalize_path("res://../content/source")
	for name in ["items.csv", "tags.csv", "loadout.csv", "encounters.csv", "rules.csv", "rewards.csv", "routes.csv", "events.csv", "resolutions.csv", "art.json"]:
		check(DirAccess.copy_absolute(source.path_join(name), dir.path_join(name)) == OK, "copy test data " + name)
	var input := FileAccess.open(source.path_join("effects.csv"), FileAccess.READ)
	var output := FileAccess.open(dir.path_join("effects.csv"), FileAccess.WRITE)
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() == 1 and row[0].is_empty(): continue
		if row[0] == "seal_bonus": row[3] = "neighbor_items"
		if row[0] == "lantern_guard": row[7] = "per_neighbor"
		output.store_csv_line(row)
	input.close()
	output.close()
	var loaded := ContentLoader.new().load_csv_directory(dir)
	check(loaded.error.is_empty(), "CSV accepts extended range values")
	if loaded.error.is_empty():
		check(ContentLoader.index(loaded.raw.effects).seal_bonus.target == "neighbor_items" and ContentLoader.index(loaded.raw.effects).lantern_guard.scale == "per_neighbor", "CSV retains range values")
		var again := ContentLoader.new().validate(JSON.parse_string(JSON.stringify(loaded.raw)))
		check(again.error.is_empty() and again.raw == loaded.raw, "CSV to JSON uses same validator")
		var model := ItemCatalog.from_validated(again.raw)
		for uid: String in model.items.keys():
			if model.is_packed(uid): model.move_to_stash(uid)
		var placed := model.place("sword", Vector2i(3,0), 0) and model.place("seal", Vector2i(2,3), 0) and model.place("lantern", Vector2i(0,1), 0) and model.place("ring", Vector2i(1,0), 0)
		check(placed and model.action_result("sword").power == 8 and model.passive_guard() == 4, "CSV-to-JSON data materializes and runs both union ranges")
