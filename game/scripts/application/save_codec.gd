class_name SaveCodec
extends RefCounted
## Versioned, checked value format. Never trusts saved Resources or configuration.

const VERSION := 3
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
	if parser.parse(text) != OK: return _fail("저장 파일의 JSON 형식이 올바르지 않습니다.")
	var envelope: Variant = parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String or not envelope.get("checksum") is String:
		return _fail("저장 파일의 형식이 올바르지 않습니다.")
	if envelope.payload.sha256_text() != envelope.checksum:
		return _fail("저장 파일의 무결성 검사가 실패했습니다.")
	parser = JSON.new()
	if parser.parse(envelope.payload) != OK: return _fail("저장 내용의 JSON 형식이 올바르지 않습니다.")
	var doc: Variant = parser.data
	if not doc is Dictionary or not _int_ok(doc.get("version"), 0, MAX_NUMBER) or not doc.get("content_hash") is String:
		return _fail("저장 파일의 버전 정보가 없습니다.")
	if int(doc.version) == 1: return _migrate_v1(doc, model)
	if int(doc.version) == 2: return _migrate_v2(doc, model)
	if int(doc.version) != VERSION:
		return {"status": "incompatible", "error": "지원하지 않는 저장 버전입니다. 기존 파일을 보존했습니다."}
	if doc.content_hash != model.content_hash:
		return {"status": "incompatible", "error": "저장 당시의 콘텐츠가 현재 데이터와 다릅니다. 기존 파일을 보존했습니다."}
	var state: Variant = doc.get("state")
	if not state is Dictionary: return _fail("전투 상태가 없습니다.")
	for field in STATE_FIELDS:
		if not state.has(field): return _fail("전투 상태 필드가 없습니다: " + field)
	if not state.phase is String or state.phase not in ["packing", "battle", "reward", "victory", "route", "event", "event_result", "defeat", "complete"]:
		return _fail("전투 단계가 올바르지 않습니다.")
	var config := model.config
	var limits := {"encounter": config.encounters.size() - 1, "health": config.max_health,
		"energy": config.energy_per_turn, "guard": MAX_NUMBER, "enemy_guard": MAX_NUMBER,
		"turn": MAX_NUMBER, "enemy_health": MAX_NUMBER}
	for field: String in limits:
		var minimum := 1 if field == "turn" else 0
		if not _int_ok(state[field], minimum, limits[field]): return _fail("잘못된 수치: " + field)
		state[field] = int(state[field])
	state.config = config.duplicate(true)
	var route_error := _validate_route(state)
	if not route_error.is_empty(): return _fail(route_error)
	if state.enemy_health > config.encounters[state.encounter].hp: return _fail("적 체력이 범위를 벗어났습니다.")
	if (state.phase == "defeat") != (state.health == 0): return _fail("단계와 플레이어 체력이 일치하지 않습니다.")
	if state.phase in ["reward", "victory", "route", "event", "event_result", "complete"] and state.enemy_health != 0: return _fail("승리 상태의 적 체력이 올바르지 않습니다.")
	if state.phase in ["packing", "battle"] and state.enemy_health == 0: return _fail("진행 중인 전투의 적 체력이 올바르지 않습니다.")
	if state.phase == "complete" and not RouteRules.last(state): return _fail("완료 길목이 올바르지 않습니다.")
	if not state.used is Dictionary or state.used.size() > 10000: return _fail("사용 횟수 형식이 올바르지 않습니다.")
	for uid: Variant in state.used:
		if not uid is String or uid.is_empty() or uid.length() > 128 or not _int_ok(state.used[uid], 1, 128): return _fail("사용 횟수 항목이 올바르지 않습니다.")
		state.used[uid] = int(state.used[uid])
	if not state.messages is Array or state.messages.size() > 30: return _fail("전투 기록 형식이 올바르지 않습니다.")
	for message: Variant in state.messages:
		if not message is String or message.length() > 4096: return _fail("전투 기록 항목이 올바르지 않습니다.")
	if not state.reactions is Array or not state.reactions.is_empty(): return _fail("지원하지 않는 반응 상태입니다.")
	var initial_items := model.authored_items
	var event_error := _validate_event(state)
	if not event_error.is_empty(): return _fail(event_error)
	var allowed_rewards := _allowed_rewards(state)
	if not state.event.is_empty() and state.event.selected == "take":
		var entry := EventRules.definition(state)
		allowed_rewards[state.event.uid] = [entry.item_id]
	var current := _decode_items(doc.get("items"), model, initial_items, allowed_rewards)
	if not error.is_empty(): return _fail(error)
	var history: Variant = doc.get("history")
	if not history is Array or history.size() > 30: return _fail("배치 되돌리기 이력이 올바르지 않습니다.")
	var restored_history: Array[Dictionary] = []
	for old: Variant in history:
		var previous := _decode_items(old, model, initial_items, allowed_rewards)
		if not error.is_empty(): return _fail(error)
		if previous.size() != current.size(): return _fail("배치 이력의 아이템 수가 일치하지 않습니다.")
		for uid: String in current:
			if not previous.has(uid) or previous[uid].definition != current[uid].definition: return _fail("배치 이력이 현재 아이템과 일치하지 않습니다.")
		restored_history.append(previous)
	if not state.event.is_empty():
		var has_item: bool = current.has(state.event.uid)
		if has_item != (state.event.selected == "take"): return _fail("사건 유품과 선택이 일치하지 않습니다.")
		if state.event.status == "carried" and state.phase == "route" and current[state.event.uid].origin == InventoryModel.STASH: return _fail("확정한 유품을 보따리에 넣어야 합니다.")
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
		error = "아이템 목록이 올바르지 않습니다."
		return {}
	var restored := model.copy_for_transaction()
	restored.items.clear()
	restored.history.clear()
	restored.locked = false
	var locations: Dictionary = {}
	for value: Variant in raw:
		if not value is Dictionary:
			error = "아이템 인스턴스가 올바르지 않습니다."
			return {}
		var item: Dictionary = value
		var uid: Variant = item.get("uid")
		if not uid is String or uid.is_empty() or uid.length() > 128 or restored.items.has(uid):
			error = "아이템 인스턴스가 중복되거나 올바르지 않습니다."
			return {}
		var definition: Variant = item.get("definition")
		var origin: Variant = item.get("origin")
		if not definition is String or not model.definitions.has(definition) or not origin is Array or origin.size() != 2 or not _int_ok(item.get("rotation"), 0, 3):
			error = "아이템 정의 또는 배치가 올바르지 않습니다: " + uid
			return {}
		if initial.has(uid):
			if str(initial[uid].definition) != definition:
				error = "초기 아이템 정의가 일치하지 않습니다: " + uid
				return {}
		elif not allowed_rewards.has(uid) or definition not in allowed_rewards[uid]:
			error = "알 수 없는 아이템 인스턴스입니다: " + uid
			return {}
		if not _int_ok(origin[0], -1, 63) or not _int_ok(origin[1], -1, 63):
			error = "아이템 좌표가 올바르지 않습니다: " + uid
			return {}
		var position := Vector2i(int(origin[0]), int(origin[1]))
		if (position.x == -1) != (position.y == -1):
			error = "보관대 좌표가 올바르지 않습니다: " + uid
			return {}
		restored.items[uid] = {"definition": definition, "origin": InventoryModel.STASH, "rotation": int(item.rotation)}
		locations[uid] = position
	for uid: String in restored.items:
		if locations[uid] == InventoryModel.STASH: continue
		if not restored.place(uid, locations[uid], restored.items[uid].rotation):
			error = "아이템이 겹치거나 보따리 범위를 벗어났습니다: " + uid
			return {}
	return restored.items.duplicate(true)

func _validate_reward(state: Dictionary, items: Dictionary, config: Dictionary) -> String:
	if not state.reward is Dictionary: return "보상 상태 형식이 올바르지 않습니다."
	var offer := RouteRules.offer(state)
	var expects: bool = state.phase in ["reward", "victory", "event_result"] and not offer.is_empty()
	if not expects:
		return "현재 단계에 보상 정보가 남아 있습니다." if not state.reward.is_empty() else ""
	var reward: Dictionary = state.reward
	for field in ["offer_id", "candidates", "selected", "uid", "status"]:
		if not reward.has(field): return "보상 상태 필드가 없습니다: " + field
	if reward.offer_id != offer.id or reward.uid != "reward/" + str(offer.id) or reward.candidates != offer.item_ids:
		return "현재 길목의 보상 후보가 일치하지 않습니다."
	if not reward.selected is String or reward.selected not in ([""] + offer.item_ids): return "선택한 보상이 올바르지 않습니다."
	if (state.phase in ["reward", "event_result"] and reward.status != "pending") or (state.phase == "victory" and reward.status not in ["claimed", "skipped"]): return "보상 처리 단계가 일치하지 않습니다."
	if reward.status == "claimed" and reward.selected.is_empty(): return "확정한 보상이 없습니다."
	if reward.status == "skipped" and not reward.selected.is_empty(): return "건너뛴 보상에 선택이 남아 있습니다."
	if reward.selected.is_empty():
		if items.has(reward.uid): return "선택되지 않은 보상 인스턴스가 있습니다."
	elif not items.has(reward.uid) or str(items[reward.uid].definition) != reward.selected:
		return "보상 인스턴스가 선택한 후보와 다릅니다."
	return ""

func _validate_route(state: Dictionary) -> String:
	if not state.route is Dictionary or not state.route.get("choice") is String or not _int_ok(state.route.get("step"), 0, state.config.encounters.size() - 1): return "경로 정보가 올바르지 않습니다."
	state.route.step = int(state.route.step)
	if not RouteRules.enabled(state):
		return "경로가 없는 콘텐츠에 경로 상태가 있습니다." if state.phase == "route" or not state.route.choice.is_empty() or state.route.step != 0 else ""
	if state.route.choice.is_empty():
		if state.route.step != 0 or state.encounter != 0: return "경로 선택 전 길목이 올바르지 않습니다."
	else:
		var route := RouteRules.find(state.config, state.route.choice)
		if route.is_empty() or state.route.step == 0 or route.encounters[state.route.step] != state.encounter: return "선택한 경로와 길목이 일치하지 않습니다."
	if state.phase == "route" and (not state.route.choice.is_empty() or state.route.step != 0): return "경로 선택 단계가 올바르지 않습니다."
	return ""

func _allowed_rewards(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if RouteRules.enabled(state):
		var route := RouteRules.current(state)
		var last: int = state.route.step if state.phase in ["reward", "victory", "route", "event", "event_result"] else state.route.step - 1
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
	if not state.event is Dictionary: return "사건 상태 형식이 올바르지 않습니다."
	if state.event.is_empty(): return "현재 단계에 사건이 없습니다." if state.phase in ["event", "event_result"] else ""
	var event: Dictionary = state.event
	for field in ["id", "uid", "selected", "status", "outcome"]:
		if not event.get(field) is String: return "사건 상태 필드가 올바르지 않습니다."
	var entry := EventRules.definition(state)
	if entry.is_empty() or event.uid != "event/" + str(entry.id): return "사건 참조가 올바르지 않습니다."
	var step := RouteRules.step(state)
	if event.status == "pending":
		if state.phase != "event" or step != entry.step or event.selected not in ["", "take"] or not event.outcome.is_empty(): return "사건 선택 단계가 올바르지 않습니다."
	elif event.status in ["carried", "left"]:
		if event.selected != ("take" if event.status == "carried" else "leave") or not event.outcome.is_empty(): return "사건 선택 결과가 올바르지 않습니다."
		if not ((step == entry.step and state.phase == "route") or (step == entry.step + 1 and state.phase in ["packing", "battle", "defeat"])): return "사건 처리 전 길목이 올바르지 않습니다."
	elif event.status == "resolved":
		if event.selected not in ["take", "leave"] or event.outcome not in ["take", "leave"] or (event.selected == "leave" and event.outcome != "leave"): return "사건 후속 결과가 올바르지 않습니다."
		if step < entry.step + 1 or state.phase == "event" or (state.phase == "event_result" and step != entry.step + 1): return "사건 후속 길목이 올바르지 않습니다."
	else: return "사건 처리 상태가 올바르지 않습니다."
	return ""

func _migrate_v2(doc: Dictionary, model: InventoryModel) -> Dictionary:
	if doc.content_hash != model.previous_content_hash:
		return {"status":"incompatible", "error":"기존 저장의 콘텐츠가 현재 데이터와 달라 이전할 수 없습니다. 기존 파일을 보존했습니다."}
	if not doc.get("state") is Dictionary: return _fail("이전 저장의 전투 상태가 없습니다.")
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
		return {"status":"incompatible", "error":"기존 저장의 콘텐츠가 현재 데이터와 달라 이전할 수 없습니다. 기존 파일을 보존했습니다."}
	if not doc.get("state") is Dictionary: return _fail("이전 저장의 전투 상태가 없습니다.")
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
		if route_id.is_empty(): return {"status":"incompatible", "error":"기존 길목 순서에 맞는 경로가 없어 자동 이전할 수 없습니다."}
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
