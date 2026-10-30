class_name SaveCodec
extends RefCounted
## Versioned, checked value format. Never trusts saved Resources or configuration.

const VERSION := 4
const STATE_FIELDS := ["phase", "encounter", "health", "energy", "guard", "enemy_health", "enemy_guard", "turn", "used", "messages", "reward", "reactions", "route", "event"]
const MAX_NUMBER := 9007199254740991
var error := ""

static func encode(state: Dictionary, model: InventoryModel, history: Array) -> String:
	var values: Dictionary = {}
	for field in STATE_FIELDS: values[field] = state[field].duplicate(true) if state[field] is Array or state[field] is Dictionary else state[field]
	var past: Array = []
	for layout: Dictionary in history: past.append(_encode_items(layout))
	var payload := JSON.stringify({"version": VERSION, "content_hash": model.content_hash, "state": values,
		"items": _encode_items(state.inventory_items), "history": past}, "", true)
	return JSON.stringify({"payload": payload, "checksum": payload.sha256_text()}, "", true) + "\n"

static func _encode_items(items: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for uid: String in items:
		var item: Dictionary = items[uid]
		var origin: Vector2i = item.origin
		result.append({"uid": uid, "definition": str(item.definition), "origin": [origin.x, origin.y], "rotation": item.rotation})
	return result

func decode(text: String, model: InventoryModel) -> Dictionary:
	error = ""
	var parser := JSON.new()
	if parser.parse(text) != OK: return _fail("Invalid save-file JSON.")
	var envelope: Variant = parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String or not envelope.get("checksum") is String:
		return _fail("Invalid save-file format.")
	if envelope.payload.sha256_text() != envelope.checksum:
		return _fail("Save-file integrity check failed.")
	parser = JSON.new()
	if parser.parse(envelope.payload) != OK: return _fail("Invalid JSON in save contents.")
	var doc: Variant = parser.data
	if not doc is Dictionary or not _int_ok(doc.get("version"), 0, MAX_NUMBER) or not doc.get("content_hash") is String:
		return _fail("Save-file version is missing.")
	if int(doc.version) == 1: return _migrate_v1(doc, model)
	if int(doc.version) == 2: return _migrate_v2(doc, model)
	if int(doc.version) == 3: return _migrate_v3(doc, model)
	if int(doc.version) != VERSION:
		return {"status": "incompatible", "error": "Unsupported save version. The existing file was preserved."}
	if doc.content_hash != model.content_hash:
		return {"status": "incompatible", "error": "The saved content differs from the current data. The existing file was preserved."}
	var state: Variant = doc.get("state")
	if not state is Dictionary: return _fail("Battle state is missing.")
	for field in STATE_FIELDS:
		if not state.has(field): return _fail("Missing battle-state field: " + field)
	if not state.phase is String or state.phase not in ["packing", "battle", "reward", "victory", "route", "event", "event_result", "defeat", "complete"]:
		return _fail("Invalid battle phase.")
	var config := model.config
	var limits := {"encounter": config.encounters.size() - 1, "health": config.max_health,
		"energy": config.energy_per_turn, "guard": MAX_NUMBER, "enemy_guard": MAX_NUMBER,
		"turn": MAX_NUMBER, "enemy_health": MAX_NUMBER}
	for field: String in limits:
		var minimum := 1 if field == "turn" else 0
		if not _int_ok(state[field], minimum, limits[field]): return _fail("Invalid value: " + field)
		state[field] = int(state[field])
	state.config = config.duplicate(true)
	var route_error := _validate_route(state)
	if not route_error.is_empty(): return _fail(route_error)
	if state.enemy_health > config.encounters[state.encounter].hp: return _fail("Enemy HP is out of range.")
	if (state.phase == "defeat") != (state.health == 0): return _fail("Player HP does not match the phase.")
	if state.phase in ["reward", "victory", "route", "event", "event_result", "complete"] and state.enemy_health != 0: return _fail("Invalid enemy HP in victory state.")
	if state.phase in ["packing", "battle"] and state.enemy_health == 0: return _fail("Invalid enemy HP in an active battle.")
	if not state.used is Dictionary or state.used.size() > 10000: return _fail("Invalid uses format.")
	for uid: Variant in state.used:
		if not uid is String or uid.is_empty() or uid.length() > 128 or not _int_ok(state.used[uid], 1, 128): return _fail("Invalid uses entry.")
		state.used[uid] = int(state.used[uid])
	if not state.messages is Array or state.messages.size() > 30: return _fail("Invalid battle-log format.")
	for message: Variant in state.messages:
		if not message is String or message.length() > 4096: return _fail("Invalid battle-log entry.")
	if not state.reactions is Array or not state.reactions.is_empty(): return _fail("Unsupported reaction state.")
	var initial_items := model.authored_items
	var event_error := _validate_event(state)
	if not event_error.is_empty(): return _fail(event_error)
	if state.phase == "complete" and not RouteRules.last(state):
		var entry := EventRules.definition(state)
		if EventRules.resolution(state).is_empty() or entry.is_empty() or state.event.get("status", "") != "resolved" or RouteRules.step(state) != int(entry.step) + 1: return _fail("Invalid completed encounter.")
	var allowed_rewards := _allowed_rewards(state)
	if not state.event.is_empty() and state.event.selected == "take":
		var entry := EventRules.definition(state)
		allowed_rewards[state.event.uid] = [entry.item_id]
	var current := _decode_items(doc.get("items"), model, initial_items, allowed_rewards)
	if not error.is_empty(): return _fail(error)
	var history: Variant = doc.get("history")
	if not history is Array or history.size() > 30: return _fail("Invalid placement undo history.")
	var restored_history: Array[Dictionary] = []
	for old: Variant in history:
		var previous := _decode_items(old, model, initial_items, allowed_rewards)
		if not error.is_empty(): return _fail(error)
		if previous.size() != current.size(): return _fail("Placement history item count does not match.")
		for uid: String in current:
			if not previous.has(uid) or previous[uid].definition != current[uid].definition: return _fail("Placement history does not match current items.")
		restored_history.append(previous)
	if not state.event.is_empty():
		var has_item: bool = current.has(state.event.uid)
		if has_item != (state.event.selected == "take"): return _fail("Event keepsake does not match the choice.")
		if state.event.status == "carried" and state.phase == "route" and current[state.event.uid].origin == InventoryModel.STASH and not EventRules.resolution(state).get("allow_stash", false): return _fail("The confirmed keepsake must be in the bag.")
		if state.event.get("method", "") == "resolution" and (not has_item or current[state.event.uid].origin == InventoryModel.STASH): return _fail("The keepsake required for the ending is missing.")
	var reward_error := _validate_reward(state, current, config)
	if not reward_error.is_empty(): return _fail(reward_error)
	state.inventory_items = current
	var restored_model := model.copy_for_transaction()
	restored_model.items = current.duplicate(true)
	restored_model.history = restored_history
	state.packed_items = restored_model.combat_snapshot()
	return {"status": "ok", "error": "", "state": state, "items": current, "history": restored_history}

func _decode_items(raw: Variant, model: InventoryModel, initial: Dictionary, allowed_rewards: Dictionary) -> Dictionary:
	if not raw is Array or raw.size() > 10000:
		error = "Invalid item list."
		return {}
	var restored := model.copy_for_transaction()
	restored.items.clear()
	restored.history.clear()
	restored.locked = false
	var locations: Dictionary = {}
	for value: Variant in raw:
		if not value is Dictionary:
			error = "Invalid item instance."
			return {}
		var item: Dictionary = value
		var uid: Variant = item.get("uid")
		if not uid is String or uid.is_empty() or uid.length() > 128 or restored.items.has(uid):
			error = "Invalid or duplicate item instance."
			return {}
		var definition: Variant = item.get("definition")
		var origin: Variant = item.get("origin")
		if not definition is String or not model.definitions.has(definition) or not origin is Array or origin.size() != 2 or not _int_ok(item.get("rotation"), 0, 3):
			error = "Invalid item definition or placement: " + uid
			return {}
		if initial.has(uid):
			if str(initial[uid].definition) != definition:
				error = "Starting item definition does not match: " + uid
				return {}
		elif not allowed_rewards.has(uid) or definition not in allowed_rewards[uid]:
			error = "Unknown item instance: " + uid
			return {}
		if not _int_ok(origin[0], -1, 63) or not _int_ok(origin[1], -1, 63):
			error = "Invalid item coordinates: " + uid
			return {}
		var position := Vector2i(int(origin[0]), int(origin[1]))
		if (position.x == -1) != (position.y == -1):
			error = "Invalid storage coordinates: " + uid
			return {}
		restored.items[uid] = {"definition": definition, "origin": InventoryModel.STASH, "rotation": int(item.rotation)}
		locations[uid] = position
	for uid: String in restored.items:
		if locations[uid] == InventoryModel.STASH: continue
		if not restored.place(uid, locations[uid], restored.items[uid].rotation):
			error = "Item overlaps or is outside the bag: " + uid
			return {}
	return restored.items.duplicate(true)

func _validate_reward(state: Dictionary, items: Dictionary, config: Dictionary) -> String:
	if not state.reward is Dictionary: return "Invalid reward-state format."
	var offer := RouteRules.offer(state)
	var expects: bool = state.phase in ["reward", "victory", "event_result"] and not offer.is_empty()
	if state.phase == "event_result" and state.event.get("method", "") == "resolution": expects = false
	if not expects:
		return "Reward data remains in the current phase." if not state.reward.is_empty() else ""
	var reward: Dictionary = state.reward
	for field in ["offer_id", "candidates", "selected", "uid", "status"]:
		if not reward.has(field): return "Missing reward-state field: " + field
	if reward.offer_id != offer.id or reward.uid != "reward/" + str(offer.id) or reward.candidates != offer.item_ids:
		return "Reward choices do not match the current encounter."
	if not reward.selected is String or reward.selected not in ([""] + offer.item_ids): return "Invalid selected reward."
	if (state.phase in ["reward", "event_result"] and reward.status != "pending") or (state.phase == "victory" and reward.status not in ["claimed", "skipped"]): return "Reward status does not match the phase."
	if reward.status == "claimed" and reward.selected.is_empty(): return "Confirmed reward is missing."
	if reward.status == "skipped" and not reward.selected.is_empty(): return "A skipped reward still has a selection."
	if reward.selected.is_empty():
		if items.has(reward.uid): return "Unselected reward instance exists."
	elif not items.has(reward.uid) or str(items[reward.uid].definition) != reward.selected:
		return "Reward instance does not match the selection."
	return ""

func _validate_route(state: Dictionary) -> String:
	if not state.route is Dictionary or not state.route.get("choice") is String or not _int_ok(state.route.get("step"), 0, state.config.encounters.size() - 1): return "Invalid route data."
	state.route.step = int(state.route.step)
	if not RouteRules.enabled(state):
		return "Route state exists for content without routes." if state.phase == "route" or not state.route.choice.is_empty() or state.route.step != 0 else ""
	if state.route.choice.is_empty():
		if state.route.step != 0 or state.encounter != 0: return "Invalid encounter before route selection."
	else:
		var route := RouteRules.find(state.config, state.route.choice)
		if route.is_empty() or state.route.step == 0 or route.encounters[state.route.step] != state.encounter: return "The selected route and encounter do not match."
	if state.phase == "route" and (not state.route.choice.is_empty() or state.route.step != 0): return "Invalid route-selection phase."
	return ""

func _allowed_rewards(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if RouteRules.enabled(state):
		var route := RouteRules.current(state)
		var last: int = state.route.step if state.phase in ["reward", "victory", "route", "event", "event_result"] else state.route.step - 1
		if state.phase == "event_result" and state.event.get("method", "") == "resolution": last -= 1
		for i in range(mini(last + 1, route.rewards.size())):
			var offer: Dictionary = state.config.reward_definitions[route.rewards[i]]
			result["reward/" + str(offer.id)] = offer.item_ids
	else:
		var last: int = state.encounter if state.phase in ["reward", "victory"] else state.encounter - 1
		for i in range(last + 1):
			var offer: Dictionary = state.config.reward_offers.get(state.config.encounters[i].id, {})
			if not offer.is_empty(): result["reward/" + str(offer.id)] = offer.item_ids
	return result

func _validate_event(state: Dictionary) -> String:
	if not state.event is Dictionary: return "Invalid event-state format."
	if state.event.is_empty(): return "No event exists in the current phase." if state.phase in ["event", "event_result"] else ""
	var event: Dictionary = state.event
	for key: Variant in event:
		if key not in ["id", "uid", "selected", "status", "outcome", "method"]: return "Unknown event-state field."
	for field in ["id", "uid", "selected", "status", "outcome"]:
		if not event.get(field) is String: return "Invalid event-state field."
	var entry := EventRules.definition(state)
	if entry.is_empty() or event.uid != "event/" + str(entry.id): return "Invalid event reference."
	var step := RouteRules.step(state)
	if event.has("method"):
		if event.method != "resolution" or EventRules.resolution(state).is_empty() or event.status != "resolved" or event.selected != "take" or event.outcome != "take" or step != int(entry.step) + 1 or state.phase not in ["event_result", "complete"]: return "Ending method does not match event state."
	if event.status == "pending":
		if state.phase != "event" or step != entry.step or event.selected not in ["", "take"] or not event.outcome.is_empty(): return "Invalid event-selection phase."
	elif event.status in ["carried", "left"]:
		if event.selected != ("take" if event.status == "carried" else "leave") or not event.outcome.is_empty(): return "Invalid event choice outcome."
		if not ((step == entry.step and state.phase == "route") or (step == entry.step + 1 and state.phase in ["packing", "battle", "defeat"])): return "Invalid encounter before event resolution."
	elif event.status == "resolved":
		if event.selected not in ["take", "leave"] or event.outcome not in ["take", "leave"] or (event.selected == "leave" and event.outcome != "leave"): return "Invalid event follow-up outcome."
		if step < entry.step + 1 or state.phase == "event" or (state.phase == "event_result" and step != entry.step + 1): return "Invalid event follow-up encounter."
	else: return "Invalid event resolution state."
	return ""

func _migrate_v3(doc: Dictionary, model: InventoryModel) -> Dictionary:
	if doc.content_hash != model.content_hash:
		return {"status":"incompatible", "error":"Old save content differs from current data and cannot be migrated. The file was preserved."}
	if not doc.get("state") is Dictionary or not doc.state.get("event") is Dictionary or doc.state.event.has("method"): return _fail("Invalid event state in previous save.")
	var migrated := doc.duplicate(true)
	migrated.version = VERSION
	var result := SaveCodec.new().decode(_wrap(migrated), model)
	if result.status == "ok": result.migrated = true
	return result

func _migrate_v2(doc: Dictionary, model: InventoryModel) -> Dictionary:
	if doc.content_hash != model.previous_content_hash:
		return {"status":"incompatible", "error":"Old save content differs from current data and cannot be migrated. The file was preserved."}
	if not doc.get("state") is Dictionary: return _fail("Previous save has no battle state.")
	var old_model := model.copy_for_transaction()
	old_model.content_hash = model.previous_content_hash
	old_model.config = model.config.duplicate(true)
	old_model.config.events = []
	var checked_doc := doc.duplicate(true)
	checked_doc.version = VERSION
	checked_doc.state.event = {}
	var checked := SaveCodec.new().decode(_wrap(checked_doc), old_model)
	if checked.status != "ok": return checked
	checked_doc.content_hash = model.content_hash
	var result := SaveCodec.new().decode(_wrap(checked_doc), model)
	if result.status == "ok": result.migrated = true
	return result

func _migrate_v1(doc: Dictionary, model: InventoryModel) -> Dictionary:
	if doc.content_hash != model.legacy_content_hash:
		return {"status":"incompatible", "error":"Old save content differs from current data and cannot be migrated. The file was preserved."}
	if not doc.get("state") is Dictionary: return _fail("Previous save has no battle state.")
	var old_model := model.copy_for_transaction()
	old_model.content_hash = model.legacy_content_hash
	old_model.config = model.config.duplicate(true)
	old_model.config.routes = []
	old_model.config.events = []
	var legacy := doc.duplicate(true)
	legacy.version = VERSION
	legacy.state.route = {"choice":"", "step":0}
	legacy.state.event = {}
	var checked := SaveCodec.new().decode(_wrap(legacy), old_model)
	if checked.status != "ok": return checked
	var migrated := doc.duplicate(true)
	migrated.version = VERSION
	migrated.content_hash = model.content_hash
	var encounter: int = checked.state.encounter
	var route_id := ""
	if encounter > 0 and not model.config.routes.is_empty():
		var expected: Array = []
		for i in model.config.encounters.size(): expected.append(i)
		for route: Dictionary in model.config.routes:
			if route.encounters == expected:
				route_id = route.id
				break
		if route_id.is_empty(): return {"status":"incompatible", "error":"No route matches the previous encounter order; automatic migration is unavailable."}
	migrated.state.route = {"choice": route_id, "step": encounter if not model.config.routes.is_empty() else 0}
	migrated.state.event = {}
	var result := SaveCodec.new().decode(_wrap(migrated), model)
	if result.status == "ok": result.migrated = true
	return result

static func _wrap(doc: Dictionary) -> String:
	var payload := JSON.stringify(doc, "", true)
	return JSON.stringify({"payload":payload, "checksum":payload.sha256_text()}, "", true) + "\n"

static func _int_ok(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value) and value >= minimum and value <= maximum

static func _fail(message: String) -> Dictionary:
	return {"status": "corrupt", "error": message}
