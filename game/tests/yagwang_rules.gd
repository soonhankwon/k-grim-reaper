extends RefCounted
## Isolated, unsaved prototype rules. All state and authored parameters are values.

var settings: Dictionary

func _init(data: Dictionary) -> void:
	settings = data.duplicate(true)

static func validate(data: Variant) -> String:
	if not data is Dictionary: return "Prototype rules must be an object."
	for key in ["target_tag", "lure_tag"]:
		if not data.get(key) is String or str(data[key]).is_empty(): return "Missing tag: " + key
	for key in ["countdown", "dawn_turn", "energy_penalty", "exposed_rows"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or float(value) != floorf(float(value)) or int(value) < 1 or int(value) > 99: return "Invalid value: " + key
	return ""

func target(state: Dictionary) -> String:
	# Exposed tagged objects take priority. Hidden tagged objects are never
	# selected as fallback; other objects compete by their lowest occupied row.
	var items: Dictionary = state.packed_items
	var first_exposed_row := int(state.config.grid_height) - int(settings.exposed_rows)
	var choices: Array[String] = []
	for uid: String in items:
		if settings.target_tag not in items[uid].tags: continue
		for cell: Vector2i in items[uid].cells:
			if cell.y >= first_exposed_row:
				choices.append(uid)
				break
	if choices.is_empty():
		var lowest := -1
		for uid: String in items:
			if settings.target_tag in items[uid].tags: continue
			for cell: Vector2i in items[uid].cells:
				if cell.y > lowest:
					lowest = cell.y
					choices.clear()
				if cell.y == lowest and uid not in choices: choices.append(uid)
	choices.sort()
	return choices[0] if not choices.is_empty() else ""

func use_error(state: Dictionary, uid: String) -> String:
	if state.phase == "battle" and state.packed_items.has(uid) and settings.lure_tag in state.packed_items[uid].tags:
		var puzzle: Dictionary = state.get("puzzle", {})
		if puzzle.get("lure_used", false): return "This item has already been used in this battle."
		if state.energy < InventoryRules.action_cost(state, state.packed_items[uid]).total: return "Not enough energy."
		return ""
	return CombatSimulator.use_error(state, uid)

func resolve(before: Dictionary, request: Dictionary) -> CombatResolution:
	var kind := str(request.get("type", ""))
	var uid := str(request.get("uid", ""))
	if kind == "use_item" and before.phase == "battle" and before.packed_items.has(uid) and settings.lure_tag in before.packed_items[uid].tags:
		return _lure(before, uid)
	var puzzle: Dictionary = before.get("puzzle", {})
	var stunned: bool = kind == "end_turn" and before.phase == "battle" and int(puzzle.get("stun", 0)) > 0
	var base := CombatSimulator.resolve(before, request, {"suppress_enemy_intent": stunned})
	if not base.error.is_empty(): return base
	var state := base.after()
	var events := base.events()
	if stunned:
		var cancelled := false
		for event: Dictionary in events:
			if event.kind == "intent_cancelled": cancelled = true
			if cancelled: event.after.puzzle.stun = 0
	if kind == "start":
		state.puzzle = {"target":target(state), "remaining":int(settings.countdown), "stun":0, "lure_used":false, "stolen":"", "saved_item":{}, "saved_packed":{}}
		_record(state, events, "target_marked", "Yagwanggwi targets %s. Theft after %d enemy actions." % [_name(state, state.puzzle.target), state.puzzle.remaining], {"source":state.puzzle.target, "cause_id":events.back().id if not events.is_empty() else 0})
	elif state.has("puzzle"):
		puzzle = state.puzzle
		if kind == "use_item" and puzzle.stolen.is_empty() and not puzzle.target.is_empty() and not state.packed_items.has(puzzle.target):
			puzzle.target = target(state)
			_record(state, events, "target_marked", "Yagwanggwi now targets %s." % _name(state, puzzle.target), {"source":puzzle.target, "cause_id":events.back().id if not events.is_empty() else 0})
		if kind == "end_turn" and state.phase == "battle":
			var tick := _last_event_id(events, "turn_started")
			var theft_cause := tick
			if stunned:
				puzzle.stun = 0
				_record(state, events, "counting_finished", "Counting the sieve delays the search by one turn.", {"cause_id":_last_event_id(events, "intent_cancelled")})
			elif puzzle.stolen.is_empty() and not puzzle.target.is_empty():
				puzzle.remaining -= 1
				if puzzle.remaining <= 0: theft_cause = _steal(state, events, tick)
				else: _record(state, events, "countdown", "Enemy actions until theft: %d" % puzzle.remaining, {"cause_id":tick})
			if not puzzle.stolen.is_empty():
				state.energy = maxi(0, int(state.config.energy_per_turn) - int(settings.energy_penalty))
				_record(state, events, "energy_penalty", "An item was stolen. Energy reduced by %d this turn." % settings.energy_penalty, {"source":puzzle.stolen, "cause_id":theft_cause})
			if int(before.turn) >= int(settings.dawn_turn):
				state.phase = "victory"
				_record(state, events, "victory", "The rooster crows. Yagwanggwi flees at dawn!", {"cause_id":tick})
		if state.phase == "victory" and not puzzle.stolen.is_empty(): _restore(state, events, _last_event_id(events, "victory"))
	if events.size() > CombatSimulator.MAX_EFFECTS:
		return CombatResolution.new(before, before, [], "The cascade limit was reached; the action was not applied.")
	return CombatResolution.new(before, state, events)

func _lure(before: Dictionary, uid: String) -> CombatResolution:
	var error := use_error(before, uid)
	if not error.is_empty(): return CombatResolution.new(before, before, [], error)
	var state := before.duplicate(true)
	var events: Array = []
	var cost: int = InventoryRules.action_cost(state, state.packed_items[uid]).total
	state.energy -= cost
	state.used[uid] = int(state.used.get(uid, 0)) + 1
	var cause := _record(state, events, "action_started", "Use %s · Energy %d" % [state.packed_items[uid].name, cost], {"source":uid, "cost":cost})
	state.puzzle.lure_used = true
	state.puzzle.stun = 1
	_record(state, events, "distraction", "Counting holes cancels the next enemy action and search.", {"source":uid, "cause_id":cause})
	return CombatResolution.new(before, state, events)

func _steal(state: Dictionary, events: Array, cause: int) -> int:
	var puzzle: Dictionary = state.puzzle
	var uid: String = puzzle.target
	if uid.is_empty() or not state.packed_items.has(uid): return 0
	puzzle.stolen = uid
	puzzle.saved_item = state.inventory_items[uid].duplicate(true)
	puzzle.saved_packed = state.packed_items[uid].duplicate(true)
	state.packed_items.erase(uid)
	state.inventory_items[uid].origin = Vector2i(-1, -1)
	return _record(state, events, "item_stolen", "%s was stolen and cannot be used during this battle." % puzzle.saved_packed.name, {"source":uid, "cause_id":cause})

func _restore(state: Dictionary, events: Array, cause: int) -> void:
	var puzzle: Dictionary = state.puzzle
	var uid: String = puzzle.stolen
	state.inventory_items[uid] = puzzle.saved_item.duplicate(true)
	state.packed_items[uid] = puzzle.saved_packed.duplicate(true)
	puzzle.stolen = ""
	puzzle.saved_item = {}
	puzzle.saved_packed = {}
	_record(state, events, "item_returned", "The stolen item returns to its original place.", {"source":uid, "cause_id":cause})

func _name(state: Dictionary, uid: String) -> String:
	return str(state.packed_items[uid].name) if state.packed_items.has(uid) else "nothing"

func _last_event_id(events: Array, kind: String) -> int:
	for index in range(events.size() - 1, -1, -1):
		if events[index].kind == kind: return int(events[index].id)
	return 0

func _record(state: Dictionary, events: Array, kind: String, message: String, details: Dictionary = {}) -> int:
	state.messages.append(message)
	if state.messages.size() > 30: state.messages.pop_front()
	var event := details.duplicate(true)
	event.merge({"id":events.size() + 1, "cause_id":int(details.get("cause_id", 0)), "kind":kind, "message":message, "after":state.duplicate(true)}, true)
	events.append(event)
	return event.id
