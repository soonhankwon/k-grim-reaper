class_name EventRules
extends RefCounted
## Pure value transaction for a staged keepsake choice and its later consequence.

static func definition(state: Dictionary) -> Dictionary:
	var id: String = state.get("event", {}).get("id", "")
	for entry: Dictionary in state.config.get("events", []):
		if entry.id == id: return entry
	return {}

static func resolution(state: Dictionary) -> Dictionary:
	var id: String = state.get("event", {}).get("id", "")
	for entry: Dictionary in state.config.get("resolutions", []):
		if entry.event_id == id: return entry
	return {}

static func due(state: Dictionary) -> Dictionary:
	if not state.get("event", {}).is_empty(): return {}
	for entry: Dictionary in state.config.get("events", []):
		if RouteRules.step(state) == entry.step: return entry
	return {}

static func open(state: Dictionary, entry: Dictionary) -> void:
	state.phase = "event"
	state.event = {"id": entry.id, "uid": "event/" + str(entry.id), "selected": "", "status": "pending", "outcome": ""}

static func resolve(before: Dictionary, request: Dictionary) -> CombatResolution:
	var state := before.duplicate(true)
	var event: Dictionary = state.get("event", {})
	var entry := definition(state)
	if entry.is_empty() or request.get("event_id", "") != event.get("id", ""):
		return _reject(before, "This event is no longer available or does not exist.")
	var message := ""
	match request.get("type", ""):
		"event_take":
			if state.phase != "event" or event.status != "pending" or not event.selected.is_empty(): return _reject(before, "You cannot choose a keepsake now.")
			event.selected = "take"
			state.inventory_items[event.uid] = {"definition": entry.item_id, "origin": Vector2i(-1,-1), "rotation": 0}
			message = "The keepsake is in storage. You can confirm it there." if resolution(state).get("allow_stash", false) else "The keepsake is in storage. Put it in your bag to confirm."
		"event_leave":
			if state.phase != "event" or event.status != "pending": return _reject(before, "You cannot choose this event now.")
			state.inventory_items.erase(event.uid)
			state.packed_items.erase(event.uid)
			event.selected = "leave"
			event.status = "left"
			state.phase = "route"
			message = "You leave the keepsake and head to the crossroads."
		"event_confirm":
			var allow_stash: bool = resolution(state).get("allow_stash", false)
			if state.phase != "event" or event.status != "pending" or event.selected != "take" or (not allow_stash and not state.packed_items.has(event.uid)): return _reject(before, "Place the keepsake in your bag before confirming.")
			event.status = "carried"
			state.phase = "route"
			message = "Keepsake collected. Choose the next path."
		"event_continue":
			if state.phase != "event_result" or event.status != "resolved": return _reject(before, "You cannot continue this event now.")
			if not resolution(state).is_empty():
				state.reward = {}
				state.phase = "complete"
			else: state.phase = "reward" if not state.reward.is_empty() else "victory"
			message = "The event is over. Continue on your way."
		_: return _reject(before, "Unknown event choice.")
	state.messages.append(message)
	if state.messages.size() > 30: state.messages.pop_front()
	var record := {"id": 1, "cause_id": 0, "kind": request.type, "source": event.uid, "message": message, "after": state.duplicate(true)}
	return CombatResolution.new(before, state, [record])

static func _reject(before: Dictionary, message: String) -> CombatResolution:
	return CombatResolution.new(before, before, [], message)
