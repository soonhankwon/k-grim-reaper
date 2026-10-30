extends SceneTree

var checks := 0
var failures := 0
var folder := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	folder = ProjectSettings.globalize_path("res://../build/production-synergy/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	_test_content()
	_test_reflection()
	_test_previous_save()
	await _test_persistence()
	await _test_ui()
	print("PRODUCTION SYNERGY TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func model() -> InventoryModel:
	return ItemCatalog.create_inventory()

func state_for(inv: InventoryModel, route_index := 1) -> Dictionary:
	var state := CombatResolver.new(inv).snapshot()
	var route: Dictionary = state.config.routes[route_index]
	state.route = {"choice":route.id, "step":1}
	state.encounter = route.encounters[1]
	state.enemy_health = state.config.encounters[state.encounter].hp
	state.phase = "battle"
	return state

func _test_content() -> void:
	var raw := ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH)
	check(raw.error.is_empty() and raw.raw.items.size() == 12 and raw.raw.encounters.size() == 3, "shipping content has unchanged item and enemy counts")
	var csv := ContentLoader.new().load_csv_directory(ProjectSettings.globalize_path("res://../content/source"))
	check(csv.error.is_empty() and csv.raw == raw.raw, "shipping CSV and JSON agree")
	var inv := model()
	check(inv.action_result("sword").power == 12, "initial diagonal ring doubles sword")
	check(inv.place("seal", Vector2i(2,1), 0), "additive seal can be placed")
	var plan := inv.action_result("sword")
	check(plan.power == 16 and plan.effects[0].base == 6 and plan.effects[0].bonuses.size() == 1 and plan.effects[0].multipliers.size() == 1, "addition precedes diagonal multiplier")
	var text := " ".join(EffectText.lines(inv.combat_snapshot().sword, inv.combat_snapshot(), "sword"))
	check(text.contains("Attack 16") and not text.contains("Calculation:"), "computed power is displayed without a raw formula")
	check(inv.preview("ring", Vector2i(0,0), 0).attacks.sword == 8, "moving out of diagonal removes multiplier")
	var links := InventoryRules.synergy_links(inv.combat_snapshot(), "sword")
	check(links.error.is_empty() and links.links.filter(func(link): return link.kind == "multiply" and link.range == "diagonal").size() == 1, "actual multiplier connection is diagonal")
	var fast := state_for(inv)
	var safe := state_for(inv, 0)
	check(CombatSimulator.enemy(fast).hp < CombatSimulator.enemy(safe).hp and CombatSimulator.enemy(fast).reactions.size() == 1 and CombatSimulator.enemy(safe).reactions.is_empty(), "routes trade lower health against retaliation")

func _test_reflection() -> void:
	var inv := model()
	inv.place("seal", Vector2i(2,1), 0)
	var state := state_for(inv)
	var original := state.duplicate(true)
	var result := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	var events := result.events()
	check(result.error.is_empty() and state == original, "pure resolution leaves input untouched")
	check(events.map(func(event): return event.kind) == ["action_started", "adjacency_bonus", "power_multiplier", "damage", "damage"], "calculation and counter form ordered event tape")
	check(events[2].cause_id == events[1].id and events[3].cause_id == events[2].id and events[4].cause_id == events[3].id, "multiplier and counter have causal links")
	check(result.after().enemy_health == 8 and result.after().health == 26 and result.after().energy == 1, "16 damage, 2 retaliation and frost cost agree")
	check(CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"}).events() == events, "event order deterministic")
	var shielded := state.duplicate(true)
	shielded.enemy_guard = 99
	result = CombatSimulator.resolve(shielded, {"type":"use_item", "uid":"sword"})
	check(result.after().health == 28 and result.events().filter(func(event): return event.kind == "damage").size() == 1, "fully blocked hit cannot trigger retaliation")
	shielded = state.duplicate(true)
	shielded.guard = 5
	result = CombatSimulator.resolve(shielded, {"type":"use_item", "uid":"sword"})
	check(result.after().health == 28 and result.after().guard == 3, "player guard absorbs retaliation")
	var lethal := state.duplicate(true)
	lethal.enemy_health = 1
	lethal.health = 2
	result = CombatSimulator.resolve(lethal, {"type":"use_item", "uid":"sword"})
	check(result.after().phase == "defeat" and result.after().health == 0 and result.events().filter(func(event): return event.kind == "victory").is_empty(), "retaliation on lethal hit settles mutual death as defeat")

func _test_previous_save() -> void:
	var raw: Dictionary = ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH).raw
	raw.effects = raw.effects.filter(func(unit): return unit.id not in ["jade_diagonal_factor", "arang_pain_reaction"])
	var item_index := ContentLoader.index(raw.items)
	item_index.sword.description = "상하좌우의 물건에 따라 위력이 달라지는 오래된 검."
	item_index.seal.description = "인접한 무기를 강화합니다. 대각선은 인접하지 않습니다."
	var ring: Dictionary = item_index.ring
	ring.description = "돌려주지 못한 마지막 약속을 담은 유품."
	ring.effect_ids = ""
	var encounters := ContentLoader.index(raw.encounters)
	encounters.gate_2.hp = 24
	encounters.gate_3.hp = 30
	encounters.gate_3.reaction_ids = ""
	var routes := ContentLoader.index(raw.routes)
	routes.mist_path.description = "대숲에서 아랑을 만납니다. 첫 행동은 방어이며 체력이 낮습니다."
	routes.moon_path.description = "연못을 지나 아랑을 만납니다. 첫 행동은 공격이며 체력이 높습니다."
	var valid := ContentLoader.new().validate(raw)
	check(valid.error.is_empty(), "previous content validates")
	if not valid.error.is_empty(): return
	var previous := ItemCatalog.from_validated(valid.raw)
	var slot := folder.path_join("previous.json")
	var original := SaveCodec.encode(CombatResolver.new(previous).snapshot(), previous, [])
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	var result := SaveService.new(slot).load_slot(model())
	check(result.status == "incompatible" and FileAccess.get_file_as_string(slot) == original, "0.15 content save is preserved on mismatch")

func _test_persistence() -> void:
	var inv := model()
	inv.place("seal", Vector2i(2,1), 0)
	var state := state_for(inv)
	var slot := folder.path_join("counter.json")
	var service := SaveService.new(slot)
	check(service.load_slot(inv).status == "missing" and service.write_slot(state, inv, []).is_empty(), "isolated counter battle saves")
	var session := BattleSession.new()
	root.add_child(session)
	session.save_service = service
	session.reset(inv, state)
	var before := session.display_snapshot()
	check(session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "counter command commits")
	var committed := session.state_snapshot()
	check(session.display_snapshot() == before and committed.health == 26, "counter remains hidden until playback")
	var restored := SaveService.new(slot).load_slot(model())
	check(restored.status == "ok" and restored.state == committed, "reopen restores resolved counter without replay")
	check(not session.submit({"type":"use_item", "uid":"sword"}).is_empty(), "rapid input blocked")
	session.skip_playback()
	check(session.display_snapshot() == committed, "skip shows committed counter outcome")
	session.queue_free()
	await process_frame

func _test_ui() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	check(main.session.place("seal", Vector2i(2,1), 0).is_empty(), "rearrange in the real UI session")
	var state := state_for(main.inventory)
	state.phase = "packing"
	main.session.reset(main.inventory, state)
	main._select("sword")
	await process_frame
	await process_frame
	check(main.labels.enemy_reactions.visible and main.labels.enemy_reactions.text.contains("HP hit") and main.labels.enemy_reactions.text.contains("Attack 2 (you)") and main.labels.enemy_reactions.text.contains("lethal: yes"), "retaliation is visible before combat with condition and amount")
	check(main.layout.reaction_scroll.get_v_scroll_bar().max_value <= main.layout.reaction_scroll.get_v_scroll_bar().page, "complete current reaction fits without scrolling")
	check(not main.layout.reaction_panel.get_global_rect().intersects(main.labels.notice.get_global_rect()) and not main.layout.reaction_panel.get_global_rect().intersects(main.labels.intent.get_global_rect()), "reaction warning leaves the notice and enemy intent visible")
	var legend: Label = main.labels.synergy_state
	check(legend.get_theme_font("font").get_string_size(legend.text, HORIZONTAL_ALIGNMENT_LEFT, -1, legend.get_theme_font_size("font_size")).x <= legend.size.x, "synergy legend fits on one line")
	check(main.labels.power.text.contains("Attack 16") and main.layout.synergy_breakdown.rows.any(func(row): return row.amount == 16 and row.multipliers.any(func(mult): return mult.factor == 2)), "actual shipping detail explains multiplication with its source")
	check(main.board.synergy_view().links.filter(func(link): return link.kind == "multiply" and link.range == "diagonal").size() == 1, "actual board shows diagonal multiplication link")
	for size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = size
		await process_frame
		var warning: Rect2 = main.labels.enemy_reactions.get_global_rect()
		check(Rect2(Vector2.ZERO, main.size).encloses(warning) and not warning.intersects(main.board.get_global_rect()) and not warning.intersects(main.primary.get_global_rect()), "warning fits without covering board or button")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/production-synergy.png"))
	check(main.session.submit({"type":"start"}).is_empty(), "start risk encounter")
	main.session.skip_playback()
	check(main.labels.enemy_reactions.visible and main.labels.enemy_reactions.text.contains("1/action"), "warning remains visible during battle")
	var route_state: Dictionary = main.session.display_snapshot()
	route_state.phase = "route"
	route_state.route = {"choice":"", "step":0}
	route_state.encounter = 0
	route_state.enemy_health = 0
	main.session.reset(main.inventory, route_state)
	await process_frame
	check(main.layout.routes.choices.size() == 2, "route choices visible")
	if main.layout.routes.choices.size() == 2:
		check(not main.layout.routes.choices[0].reaction_label.visible and main.layout.routes.choices[1].reaction_label.text.contains("HP hit → Attack 2 (you)") and main.layout.routes.choices[1].reaction_label.text.contains("lethal: yes"), "only risk route discloses its counter before selection")
		check(main.layout.routes.get_global_rect().encloses(main.layout.routes.choices[1].get_global_rect()), "route choice and reaction fit the panel")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/production-synergy-route.png"))
	main.queue_free()
	await process_frame
