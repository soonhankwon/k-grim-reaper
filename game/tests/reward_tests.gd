extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func fixture() -> InventoryModel:
	var raw: Dictionary = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	raw.rewards = [{"id": "gift_one", "encounter_id": "gate_1", "item_ids": "coin|mirror|rope"},
		{"id": "gift_two", "encounter_id": "gate_2", "item_ids": "yakgwa|sandals|order"}]
	var loaded := ContentLoader.new().validate(raw)
	check(loaded.error.is_empty(), "reward fixture validates")
	return ItemCatalog.from_validated(loaded.raw)

func near_victory(model: InventoryModel, encounter := 0) -> Dictionary:
	var state := CombatSimulator.initial_state(model.config)
	state.phase = "battle"
	state.encounter = encounter
	state.enemy_health = 1
	return state

func request(kind: String, item_id := "", offer_id := "gift_one") -> Dictionary:
	return {"type": kind, "item_id": item_id, "offer_id": offer_id}

func unchanged(battle: CombatResolver, command: Dictionary, message: String) -> void:
	var before := battle.snapshot()
	var result := battle.submit(command)
	check(not result.error.is_empty() and result.after() == before and battle.snapshot() == before and result.events().is_empty(), message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_transactions()
	_test_outcomes()
	_test_complete_run()
	_test_schema()
	await _test_playback()
	print("REWARD TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_transactions() -> void:
	var model := fixture()
	var battle := CombatResolver.new(model, near_victory(model))
	unchanged(battle, request("reward_select", "coin"), "cannot choose before victory")
	battle.use_item("sword")
	var reward: Dictionary = battle.snapshot().reward
	var uid: String = reward.uid
	check(battle.phase == "reward" and reward.candidates == ["coin", "mirror", "rope"], "victory opens authored ordered candidates")
	unchanged(battle, {"type": "advance"}, "pending reward gates advancement")
	unchanged(battle, request("reward_select", "coin", "old_offer"), "stale offer rejected")
	unchanged(battle, request("reward_select", "hat"), "unoffered item rejected")
	unchanged(battle, request("reward_confirm"), "confirmation requires selection")
	var old_count := model.items.size()
	model.move_to_stash("hat")
	var before := battle.snapshot()
	var result := battle.submit(request("reward_select", "coin"))
	check(result.error.is_empty() and result.before() == before and model.items.size() == old_count + 1 and not model.is_packed(uid), "selection stages one distinct instance in stash")
	check(uid != "coin" and model.items.has("coin") and model.items.coin.definition == model.items[uid].definition, "same definition can have separate existing and reward instances")
	unchanged(battle, request("reward_confirm"), "unpacked candidate cannot be claimed")
	check(not model.place(uid, Vector2i(3,0), 0) and not model.is_packed(uid), "overlap cannot accidentally confirm a reward")
	model.place(uid, Vector2i(4,1), 0)
	check(model.undo() and not model.is_packed(uid), "tentative placement can be undone")
	model.place(uid, Vector2i(4,1), 0)
	unchanged(battle, request("reward_select", "coin"), "reselect does not reset a placed candidate")
	battle.submit(request("reward_select", "mirror"))
	check(model.items.size() == old_count + 1 and model.items[uid].definition == "mirror" and not model.is_packed(uid), "candidate change replaces tentative item without duplication")
	check(not model.is_packed("hat") and not model.undo(), "candidate change preserves other placements and invalidates stale undo")
	model.place(uid, Vector2i(1,2), 0)
	battle.submit(request("reward_skip"))
	check(battle.phase == "victory" and model.items.size() == old_count and not model.items.has(uid) and not model.is_packed("hat"), "skip removes tentative item while preserving existing item layout")
	check(not model.undo(), "skip cannot resurrect a tentative reward through undo")
	unchanged(battle, request("reward_confirm"), "skipped reward cannot be claimed later")
	battle.advance()
	check(battle.encounter == 1 and battle.phase == "packing" and battle.snapshot().reward.is_empty(), "skip advances once and clears the offer")
	# Claim, duplicate submission, and stale callback after a later encounter.
	model = fixture()
	battle = CombatResolver.new(model, near_victory(model))
	battle.use_item("sword")
	battle.submit(request("reward_select", "coin"))
	model.place(uid, Vector2i(4,1), 0)
	battle.submit(request("reward_confirm"))
	check(battle.phase == "victory" and battle.snapshot().reward.status == "claimed" and model.is_packed(uid), "claim preserves tested placement")
	check(model.history.is_empty(), "claim establishes a new undo boundary")
	unchanged(battle, request("reward_confirm"), "duplicate confirm cannot grant another item")
	unchanged(battle, request("reward_skip"), "late skip cannot remove a claimed item")
	battle.advance()
	check(model.items.has(uid) and model.is_packed(uid), "claimed instance survives next encounter")
	battle.start_battle()
	check(battle.use_item(uid).is_empty() and battle.guard == 1, "reward uses normal combat effect engine")
	var next := near_victory(model, 1)
	battle = CombatResolver.new(model, next)
	battle.use_item("sword")
	unchanged(battle, request("reward_confirm"), "old encounter confirmation cannot claim new offer")
	check(battle.snapshot().reward.offer_id == "gift_two", "next encounter gets its own offer")

func _test_outcomes() -> void:
	var model := fixture()
	var battle := CombatResolver.new(model, near_victory(model, 2))
	battle.use_item("sword")
	check(battle.phase == "victory" and battle.snapshot().reward.is_empty(), "last battle has no unusable reward")
	battle.advance()
	check(battle.phase == "complete", "last battle can finish normally")
	var state := near_victory(model)
	state.health = 1
	state.reactions = [{"id":"fatal", "name":"test", "owner":"enemy", "effect":"damage", "target":"player", "amount":1}]
	battle = CombatResolver.new(model, state)
	battle.use_item("sword")
	check(battle.phase == "defeat" and battle.snapshot().reward.is_empty(), "simultaneous death cannot open a reward")
	# Deterministic offers do not change with refresh or replay speed.
	model = fixture()
	state = near_victory(model)
	state.packed_items = model.combat_snapshot()
	state.inventory_items = model.items.duplicate(true)
	var a := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	var b := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
	check(a.after() == b.after() and a.events() == b.events() and state.phase == "battle", "offers and victory are deterministic without mutating input")

func _test_schema() -> void:
	var raw: Dictionary = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	for row in [
		{"id":"bad", "encounter_id":"missing", "item_ids":"coin"},
		{"id":"bad", "encounter_id":"gate_1", "item_ids":"missing"},
		{"id":"bad", "encounter_id":"gate_1", "item_ids":"coin|coin"},
		{"id":"bad", "encounter_id":"gate_1", "item_ids":"coin|mirror|rope|hat"},
		{"id":"bad", "encounter_id":"gate_1", "item_ids":""},
		{"id":"bad", "encounter_id":"gate_3", "item_ids":"coin"}]:
		raw.rewards = [row]
		check(not ContentLoader.new().validate(raw).error.is_empty(), "invalid offer rejected: " + str(row))
	raw.rewards = [{"id":"one", "encounter_id":"gate_1", "item_ids":"coin"}, {"id":"two", "encounter_id":"gate_1", "item_ids":"mirror"}]
	check(not ContentLoader.new().validate(raw).error.is_empty(), "encounter has at most one offer")
	raw.rewards.resize(1)
	ContentLoader.index(raw.items).coin.footprint = "0:0|5:5"
	check(not ContentLoader.new().validate(raw).error.is_empty(), "impossible reward footprint rejected before play")

func _test_complete_run() -> void:
	var model := fixture()
	for uid in ["rope", "sandals", "order", "coin", "mirror"]: model.items.erase(uid)
	model.place("seal", Vector2i(2,1), 0)
	model.place("ring", Vector2i(0,0), 0)
	var battle := CombatResolver.new(model)
	var active_reward := ""
	for encounter in 3:
		battle.start_battle()
		var turns := 0
		while battle.phase == "battle" and turns < 30:
			for uid in [active_reward, "sword", "bell", "hat"]:
				if battle.use_error(uid).is_empty(): battle.use_item(uid)
			battle.end_turn()
			turns += 1
		check(battle.phase in ["reward", "victory"], "seven-item start reaches victory %d without shortcuts" % encounter)
		if battle.phase == "reward":
			var reward: Dictionary = battle.snapshot().reward
			var candidate := "coin" if encounter == 0 else "yakgwa"
			battle.submit(request("reward_select", candidate, reward.offer_id))
			model.place(reward.uid, Vector2i(1,1) if encounter == 0 else Vector2i(4,1), 0)
			check(battle.submit(request("reward_confirm", "", reward.offer_id)).error.is_empty(), "reward placement is confirmed between fights")
			if encounter == 0: active_reward = reward.uid
		battle.advance()
	check(battle.phase == "complete" and battle.health > 0 and model.items.size() == 9, "three encounters and two claimed rewards complete one short run")

func _test_playback() -> void:
	var model := fixture()
	var session := BattleSession.new()
	root.add_child(session)
	model.changed.connect(session.refresh_layout)
	session.reset(model, near_victory(model))
	session.submit({"type":"use_item", "uid":"sword"})
	check(session.state_snapshot().phase == "reward" and session.display_snapshot().phase == "battle", "reward waits for victory playback")
	check(not session.submit(request("reward_select", "coin")).is_empty(), "early reward click rejected during combat playback")
	session.skip_playback()
	var uid: String = session.display_snapshot().reward.uid
	session.submit(request("reward_select", "coin"))
	check(model.items.has(uid) and not session.display_snapshot().inventory_items.has(uid), "tentative item and inventory projection use the same event boundary")
	check(not session.submit(request("reward_select", "mirror")).is_empty(), "rapid candidate click cannot overlap transactions")
	session.skip_playback()
	model.place(uid, Vector2i(4,1), 0)
	session.submit(request("reward_confirm"))
	check(not session.submit(request("reward_confirm")).is_empty(), "double confirmation blocked during playback")
	session.skip_playback()
	check(session.display_snapshot().reward.status == "claimed" and model.items.size() == 13, "skip playback shows one committed reward")
	session.reset(fixture())
	await process_frame
	check(session.display_snapshot().phase == "packing" and not session.state_snapshot().inventory_items.has(uid), "restart resets reward state and inventory")
	# Reset in the middle of choice playback must discard its late completion.
	model = fixture()
	session.reset(model, near_victory(model))
	session.submit({"type":"use_item", "uid":"sword"})
	session.skip_playback()
	session.submit(request("reward_select", "coin"))
	await process_frame
	session.reset(fixture())
	for frame in 5: await process_frame
	check(session.display_snapshot().phase == "packing" and not session.display_snapshot().inventory_items.has(uid), "late choice playback cannot leak into restarted run")
	session.queue_free()
	await process_frame
