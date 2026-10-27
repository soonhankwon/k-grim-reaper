extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func battle() -> Dictionary:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	model.place("seal", Vector2i(2,1), 0)
	var resolver := CombatResolver.new(model)
	resolver.start_battle()
	return resolver.snapshot()

func reaction(id: String, owner: String, effect: String, target: String, amount: int, limit := 1) -> Dictionary:
	return {"id": id, "name": id, "owner": owner, "effect": effect,
		"target": target, "amount": amount, "max_per_action": limit}

func _initialize() -> void:
	var before := battle()
	before.reactions = [reaction("spikes", "enemy", "damage", "player", 3), reaction("shield", "player", "guard", "player", 5)]
	var untouched := before.duplicate(true)
	var request := {"type": "use_item", "uid": "sword"}
	var result := CombatSimulator.resolve(before, request)
	var after := result.after()
	var events := result.events()
	check(result.error.is_empty(), "cascade resolves")
	check(before == untouched and request == {"type": "use_item", "uid": "sword"}, "simulation leaves caller input untouched")
	check(after.enemy_health == 10 and after.health == 25 and after.guard == 5, "adjacency -> hit -> spikes -> reactive shield")
	check(events.map(func(event): return event.kind) == ["action_started", "adjacency_bonus", "damage", "damage", "guard"], "explicit ordered event tape")
	check(events[2].after.health == 28 and events[3].after.health == 25 and events[4].after.guard == 5, "each event records only its own presentation progress")
	check(events[3].cause_id == events[2].id and events[4].cause_id == events[3].id, "cascade causal IDs are connected")
	check(events[-1].after == after, "last presentation snapshot matches committed result")
	check(CombatSimulator.resolve(before, request).events() == events, "same values produce identical deterministic tape")
	before.reactions.reverse()
	check(CombatSimulator.resolve(before, request).events() == events, "reaction authoring order does not change priority/ID ordering or result")
	after.health = 1
	events[0].after.used.clear()
	check(result.after().health == 25 and result.events()[0].after.used.has("sword"), "result accessors return detached copies")
	var blocked := battle()
	blocked.enemy_guard = 99
	blocked.reactions = untouched.reactions.duplicate(true)
	var blocked_result := CombatSimulator.resolve(blocked, request)
	check(blocked_result.after().health == 28 and blocked_result.after().guard == 0, "fully absorbed hit does not trigger health-damage reactions")
	var lethal := untouched.duplicate(true)
	lethal.enemy_health = 1
	lethal.health = 3
	var lethal_result := CombatSimulator.resolve(lethal, request)
	check(lethal_result.after().phase == "defeat" and lethal_result.after().health == 0, "lethal spikes settle before victory/healing; mutual death is defeat")
	check(lethal_result.events().filter(func(event): return event.kind == "victory").is_empty(), "no premature victory event")
	check(lethal_result.after().guard == 0, "dead player cannot receive reactive guard")
	var cyclic := battle()
	cyclic.health = 1000
	cyclic.enemy_health = 1000
	cyclic.reactions = [reaction("enemy_reflect", "enemy", "damage", "player", 1), reaction("player_reflect", "player", "damage", "enemy", 1)]
	var once := CombatSimulator.resolve(cyclic, request)
	check(once.error.is_empty() and once.events().size() == 5, "mutual reflection terminates with once-per-root trigger counts")
	for item: Dictionary in cyclic.reactions: item.max_per_action = 128
	var rejected := CombatSimulator.resolve(cyclic, request)
	check(not rejected.error.is_empty() and rejected.after() == cyclic and rejected.events().is_empty(), "depth overflow rolls back costs, damage and the entire tape")
	var broad := battle()
	broad.reactions = []
	for i in 128:
		broad.reactions.append(reaction("guard_%03d" % i, "enemy", "guard", "enemy", 1))
	var overflow := CombatSimulator.resolve(broad, request)
	check(not overflow.error.is_empty() and overflow.after() == broad, "wide cascades hit effect-count budget and roll back")
	var bad := battle()
	bad.reactions = [reaction("duplicate", "enemy", "damage", "player", 1), reaction("duplicate", "enemy", "guard", "enemy", 1)]
	check(not CombatSimulator.resolve(bad, request).error.is_empty(), "duplicate trigger IDs rejected")
	var invalid := CombatSimulator.resolve(untouched, {"type": "use_item", "uid": "missing"})
	check(not invalid.error.is_empty() and invalid.after() == untouched, "invalid root action cannot mutate state")
	_test_commit_atomicity()
	print("CASCADE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_commit_atomicity() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	model.place("yakgwa", Vector2i(4,1), 0)
	var resolver := CombatResolver.new(model)
	resolver.start_battle()
	var observed := {"changes": 0}
	model.changed.connect(func(): observed.changes += 1)
	var result := resolver.submit({"type": "use_item", "uid": "yakgwa"})
	check(observed.changes == 0, "commit never emits partial inventory state")
	check(result.before().inventory_items.has("yakgwa") and not result.after().inventory_items.has("yakgwa"), "consumption is represented in before/after snapshots")
	check(not model.items.has("yakgwa") and not model.undo(), "consumption commits once and cannot be undone")
