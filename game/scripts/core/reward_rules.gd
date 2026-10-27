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
		return _reject(before, "지금은 보상을 선택할 수 없습니다.")
	if request.get("offer_id", "") != reward.offer_id:
		return _reject(before, "이미 지난 보상 요청입니다.")
	var uid: String = reward.uid
	var message := ""
	match request.get("type", ""):
		"reward_select":
			var item_id: Variant = request.get("item_id", "")
			if item_id not in reward.candidates:
				return _reject(before, "제시된 후보에서 선택하세요.")
			if item_id == reward.selected:
				return _reject(before, "이미 선택한 후보입니다. 보따리에 배치해 보세요.")
			state.packed_items.erase(uid)
			state.inventory_items[uid] = {"definition": item_id, "origin": Vector2i(-1, -1), "rotation": 0}
			reward.selected = item_id
			message = "보상 후보를 선택했습니다. 보관대의 물건을 보따리에 넣어 보세요."
		"reward_confirm":
			if reward.selected.is_empty() or not state.inventory_items.has(uid) or not state.packed_items.has(uid):
				return _reject(before, "선택한 보상을 보따리에 넣은 뒤 확정하세요.")
			if state.inventory_items[uid].definition != reward.selected:
				return _reject(before, "보상 배치가 선택한 후보와 일치하지 않습니다.")
			reward.status = "claimed"
			state.phase = "victory"
			message = "보상을 받았습니다. 정리를 마치고 다음 길목으로 이동하세요."
		"reward_skip":
			state.inventory_items.erase(uid)
			state.packed_items.erase(uid)
			reward.selected = ""
			reward.status = "skipped"
			state.phase = "victory"
			message = "보상을 받지 않고 길을 이어갑니다."
		_: return _reject(before, "알 수 없는 보상 명령입니다.")
	state.messages.append(message)
	if state.messages.size() > 30: state.messages.pop_front()
	var event := {"id": 1, "cause_id": 0, "kind": request.type, "source": uid,
		"message": message, "after": state.duplicate(true)}
	return CombatResolution.new(before, state, [event])

static func _reject(before: Dictionary, message: String) -> CombatResolution:
	return CombatResolution.new(before, before, [], message)
