extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_test_catalog()
	_test_rotation_and_placement()
	_test_adjacency()
	_test_combat()
	_test_consumption()
	_test_three_encounters()
	_test_offensive_build()
	print("RULE TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func fresh_definition(id: String, shape: Array[Vector2i]) -> ItemData:
	var item := ItemData.new()
	item.id = StringName(id)
	item.display_name = id
	item.footprint = shape
	return item

func _test_catalog() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	check(model.items.size() == 12, "12 authored item instances loaded")
	check(model.used_cells() == 12, "initial occupied cells")
	check(model.history.is_empty(), "initialization is not undoable")
	for id: String in model.items:
		var item := model.definition(id)
		var seen: Array[Vector2i] = []
		for point in item.footprint:
			check(not seen.has(point) and point.x >= 0 and point.y >= 0, "valid footprint: " + id)
			seen.append(point)
		check(not item.display_name.is_empty(), "item display name: " + id)

func _test_rotation_and_placement() -> void:
	var item := fresh_definition("elbow", [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1)])
	check(GridRules.cells(item.footprint, 4) == GridRules.cells(item.footprint, 0), "four rotations restore shape")
	check(GridRules.cells(item.footprint, -1) == GridRules.cells(item.footprint, 3), "negative rotations normalized")
	check(GridRules.cells(item.footprint, 1).has(Vector2i(1,0)) and not GridRules.cells(item.footprint, 1).has(Vector2i(1,1)), "L rotation uses normalized origin")
	var model := InventoryModel.new()
	check(model.add_item("a", item, Vector2i(0,0)), "initial item add")
	check(model.add_item("b", fresh_definition("dot", [Vector2i.ZERO]), Vector2i(1,0)), "L empty corner can be occupied")
	var before := model.items.duplicate(true)
	check(not model.place("a", Vector2i(4,3), 0), "bounds reject multi-cell overflow")
	check(not model.place("a", Vector2i(0,0), 1), "rotation cannot overlap other item")
	check(model.items == before and model.history.is_empty(), "invalid placement does not mutate state/history")
	check(model.place("a", Vector2i(2,0), 1), "valid rotation and move")
	check(model.definition("a").footprint == item.footprint, "definition unchanged by rotation")
	check(model.undo() and model.items == before, "undo restores rotation and origin")
	check(model.move_to_stash("b"), "stash move")
	check(not model.is_packed("b") and model.undo() and model.is_packed("b"), "stash undo")
	model.locked = true
	check(not model.place("a", Vector2i(2,0), 0) and not model.move_to_stash("a") and not model.undo(), "battle locks layout and history")

func _test_adjacency() -> void:
	var model := InventoryModel.new()
	var sword := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").definitions["sword"] as ItemData
	var seal := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").definitions["seal"] as ItemData
	model.add_item("sword", sword, Vector2i(1,0))
	model.add_item("seal", seal, Vector2i(0,0))
	model.add_item("seal2", seal, Vector2i(2,0))
	check(model.action_result("sword").power == 8, "same named talisman only counted once")
	check(model.adjacent("sword", "seal") and not model.adjacent("sword", "sword"), "edge adjacency excludes self")
	var before := model.items.duplicate(true)
	model.preview("seal", Vector2i(4,3), 0)
	check(model.items == before, "preview never mutates placements")
	model.move_to_stash("seal2")
	model.place("seal", Vector2i(2,3), 0)
	check(model.action_result("sword").power == 6, "diagonal is not adjacency")
	var lamp_model := InventoryModel.new()
	var lamp := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").definitions["lantern"] as ItemData
	var ring := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").definitions["ring"] as ItemData
	lamp_model.add_item("lamp", lamp, Vector2i(1,1))
	lamp_model.add_item("a", ring, Vector2i(0,1))
	lamp_model.add_item("b", ring, Vector2i(2,1))
	lamp_model.add_item("c", ring, Vector2i(1,0))
	check(lamp_model.passive_guard() == 8, "lantern has a two-keepsake cap")
	lamp_model.move_to_stash("b")
	lamp_model.move_to_stash("c")
	check(lamp_model.passive_guard() == 4, "only packed adjacent keepsakes count")
	var wide := fresh_definition("wide_keepsake", [Vector2i.ZERO, Vector2i(0,1)])
	wide.tags = PackedStringArray(["keepsake"])
	lamp_model.move_to_stash("a")
	lamp_model.add_item("wide", wide, Vector2i(2,1))
	check(lamp_model.passive_guard() == 4, "multiple shared edges do not multiply one keepsake")

func _test_combat() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	model.place("seal", Vector2i(2,1), 0)
	model.place("ring", Vector2i(0,0), 0)
	var combat := CombatResolver.new(model)
	check(not combat.use_item("sword").is_empty(), "no attacks during packing")
	check(combat.start_battle().is_empty() and model.locked and model.history.is_empty(), "start locks and clears layout history")
	check(not model.place("seal", Vector2i(4,1), 0), "layout locked during battle")
	var shown: int = model.action_result("sword").power
	check(combat.use_item("sword").is_empty() and combat.enemy_health == 18-shown, "preview damage matches combat")
	var hp := combat.enemy_health
	check(not combat.use_item("sword").is_empty() and combat.enemy_health == hp, "item can be used only once per turn")
	check(combat.use_item("hat").is_empty(), "guard action")
	check(combat.guard == 5 and combat.energy == 1, "guard and energy accounting")
	var player_hp := combat.health
	combat.end_turn()
	check(combat.health == player_hp, "active guard plus lantern prevents incoming damage")
	check(combat.guard == 0 and combat.energy == 3 and combat.used.is_empty(), "next turn expires defense and refreshes actions")
	combat.use_item("sword")
	combat.use_item("bell")
	check(combat.phase == "victory" and not model.locked, "lethal attack immediately wins and unlocks packing")
	combat.end_turn()
	check(combat.health == player_hp, "no enemy retaliation after victory")
	combat.advance()
	check(combat.phase == "packing" and combat.encounter == 1, "next enemy prepares separately")
	combat.start_battle()
	combat.end_turn()
	check(combat.enemy_guard == 6 and combat.intent().amount == 9, "second enemy alternates guard and attack")
	combat.use_item("sword")
	check(combat.enemy_guard == 0 and combat.enemy_health == 22, "enemy guard absorbs part of damage")
	var empty := InventoryModel.new()
	empty.config = model.config
	check(not CombatResolver.new(empty).start_battle().is_empty(), "cannot start without offensive tool")

func _test_consumption() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	model.place("yakgwa", Vector2i(4,1), 0)
	model.place("order", Vector2i(2,0), 0)
	var initial := CombatSimulator.initial_state(ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").config)
	initial.health = 20
	var combat := CombatResolver.new(model, initial)
	combat.start_battle()
	combat.use_item("yakgwa")
	check(combat.health == 27 and combat.energy == 3 and not model.items.has("yakgwa"), "consumable heals, costs zero, removes occupied cells")
	check(not model.undo(), "cannot undo consumption")
	combat.use_item("order")
	check(combat.energy == 1, "two-energy item")
	combat.use_item("hat")
	check(not combat.use_item("bell").is_empty() and combat.energy == 0, "insufficient energy cannot spend or attack")

func _test_three_encounters() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	model.place("seal", Vector2i(2,1), 0)
	model.place("ring", Vector2i(0,0), 0)
	model.place("coin", Vector2i(1,1), 0)
	var combat := CombatResolver.new(model)
	for encounter in 3:
		check(combat.start_battle().is_empty(), "start encounter %d" % encounter)
		var iterations := 0
		while combat.phase == "battle" and iterations < 30:
			for uid in ["coin", "sword", "bell", "hat"]:
				if combat.use_error(uid).is_empty():
					combat.use_item(uid)
			combat.end_turn()
			iterations += 1
		check(combat.phase == "victory", "defensive adjacency build clears encounter %d" % encounter)
		combat.advance()
	check(combat.phase == "complete" and combat.health > 0, "full three-fight practice run completes")
	var initial := CombatSimulator.initial_state(ItemCatalog.create_inventory("res://tests/fixtures/baseline.json").config)
	initial.health = 1
	var fragile := CombatResolver.new(ItemCatalog.create_inventory("res://tests/fixtures/baseline.json"), initial)
	fragile.start_battle()
	fragile.end_turn()
	check(fragile.phase == "defeat" and fragile.inventory.locked, "defeat prevents further layout and combat actions")

func _test_offensive_build() -> void:
	var model := ItemCatalog.create_inventory("res://tests/fixtures/baseline.json")
	# A second viable layout trades passive protection for short, high-damage fights.
	for uid: String in model.items.keys():
		model.move_to_stash(uid)
	check(model.place("sword", Vector2i(1,0), 0), "offensive sword placement")
	check(model.place("seal", Vector2i(2,1), 0), "offensive seal placement")
	check(model.place("rope", Vector2i(3,0), 0), "offensive L-shaped rope placement")
	check(model.place("order", Vector2i(0,0), 0), "offensive order placement")
	check(model.place("bell", Vector2i(0,2), 0), "offensive bell placement")
	check(model.action_result("rope").power == 6 and model.passive_guard() == 0, "one seal boosts two adjacent weapons without lantern")
	var combat := CombatResolver.new(model)
	for encounter in 3:
		check(combat.start_battle().is_empty(), "offensive encounter starts %d" % encounter)
		var iterations := 0
		while combat.phase == "battle" and iterations < 30:
			for uid in ["sword", "order", "rope", "bell"]:
				if combat.use_error(uid).is_empty():
					combat.use_item(uid)
			combat.end_turn()
			iterations += 1
		check(combat.phase == "victory", "offensive build clears encounter %d" % encounter)
		combat.advance()
	check(combat.phase == "complete" and combat.health > 0, "second distinct layout completes practice run")
