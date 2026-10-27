class_name EventRules
extends RefCounted
## Pure value transaction for a staged keepsake choice and its later consequence.

static func definition(state: Dictionary) -> Dictionary:
	var id: String = state.get("event", {}).get("id", "")
	for entry: Dictionary in state.config.get("events", []):
		if entry.id == id: return entry
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
		return _reject(before, "이전 사건이거나 존재하지 않는 사건입니다.")
	var message := ""
	match request.get("type", ""):
		"event_take":
			if state.phase != "event" or event.status != "pending" or not event.selected.is_empty(): return _reject(before, "지금은 유품을 선택할 수 없습니다.")
			event.selected = "take"
			state.inventory_items[event.uid] = {"definition": entry.item_id, "origin": Vector2i(-1,-1), "rotation": 0}
			message = "유품을 보관대에 두었습니다. 보따리에 넣은 뒤 확정하세요."
		"event_leave":
			if state.phase != "event" or event.status != "pending": return _reject(before, "지금은 이 사건을 선택할 수 없습니다.")
			state.inventory_items.erase(event.uid)
			state.packed_items.erase(event.uid)
			event.selected = "leave"
			event.status = "left"
			state.phase = "route"
			message = "유품을 두고 갈림길로 향합니다."
		"event_confirm":
			if state.phase != "event" or event.status != "pending" or event.selected != "take" or not state.packed_items.has(event.uid): return _reject(before, "유품을 보따리에 넣은 뒤 확정하세요.")
			event.status = "carried"
			state.phase = "route"
			message = "유품을 챙겼습니다. 다음 길을 고르세요."
		"event_continue":
			if state.phase != "event_result" or event.status != "resolved": return _reject(before, "지금은 사건을 이어갈 수 없습니다.")
			state.phase = "reward" if not state.reward.is_empty() else "victory"
			message = "사건을 마치고 길을 이어갑니다."
		_: return _reject(before, "알 수 없는 사건 선택입니다.")
	state.messages.append(message)
	if state.messages.size() > 30: state.messages.pop_front()
	var record := {"id": 1, "cause_id": 0, "kind": request.type, "source": event.uid, "message": message, "after": state.duplicate(true)}
	return CombatResolution.new(before, state, [record])

static func _reject(before: Dictionary, message: String) -> CombatResolution:
	return CombatResolution.new(before, before, [], message)
