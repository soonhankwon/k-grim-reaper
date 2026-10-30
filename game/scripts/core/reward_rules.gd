class_name RewardRules
extends RefCounted
## Pure post-battle choice transaction. Candidates are authored, never rerolled by UI.

static func open(state: Dictionary) -> void:
	state.reward = {}
	var offer := RouteRules.offer(state)
	if offer.is_empty(): return
	state.phase = "reward"
	state.reward = {"offer_id": offer.id, "candidates": offer.item_ids.duplicate(),
		"selected": "", "uid": "reward/" + str(offer.id), "status": "pending"}

static func resolve(before: Dictionary, request: Dictionary) -> CombatResolution:
	var state := before.duplicate(true)
	var reward: Dictionary = state.get("reward", {})
	if state.phase != "reward" or reward.get("status", "") != "pending":
		return _reject(before, "You cannot choose a reward now.")
	if request.get("offer_id", "") != reward.offer_id:
		return _reject(before, "This reward is no longer available.")
	var uid: String = reward.uid
	var message := ""
	match request.get("type", ""):
		"reward_select":
			var item_id: Variant = request.get("item_id", "")
			if item_id not in reward.candidates:
				return _reject(before, "Choose one of the offered rewards.")
			if item_id == reward.selected:
				return _reject(before, "Already selected. Place it in your bag.")
			state.packed_items.erase(uid)
			state.inventory_items[uid] = {"definition": item_id, "origin": Vector2i(-1, -1), "rotation": 0}
			reward.selected = item_id
			message = "Reward selected. Place it in your bag from storage."
		"reward_confirm":
			if reward.selected.is_empty() or not state.inventory_items.has(uid) or not state.packed_items.has(uid):
				return _reject(before, "Place the selected reward in your bag before confirming.")
			if state.inventory_items[uid].definition != reward.selected:
				return _reject(before, "Placed reward does not match the selected item.")
			reward.status = "claimed"
			state.phase = "victory"
			message = "Reward claimed. Arrange your bag and continue."
		"reward_skip":
			state.inventory_items.erase(uid)
			state.packed_items.erase(uid)
			reward.selected = ""
			reward.status = "skipped"
			state.phase = "victory"
			message = "You continue without a reward."
		_: return _reject(before, "Unknown reward command.")
	state.messages.append(message)
	if state.messages.size() > 30: state.messages.pop_front()
	var event := {"id": 1, "cause_id": 0, "kind": request.type, "source": uid,
		"message": message, "after": state.duplicate(true)}
	return CombatResolution.new(before, state, [event])

static func _reject(before: Dictionary, message: String) -> CombatResolution:
	return CombatResolution.new(before, before, [], message)
