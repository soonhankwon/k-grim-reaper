class_name CombatSimulator
extends RefCounted
## No scene tree, signals, callbacks, clocks, animation, or shared mutable input.
## One request resolves a bounded FIFO cascade, then returns an atomic result.

const MAX_EFFECTS := 128
const MAX_DEPTH := 32
var _processed := 0
var _state: Dictionary
var _events: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _trigger_counts: Dictionary = {}
var _failure := ""

static func initial_state(config: Dictionary) -> Dictionary:
	return {"phase": "packing", "encounter": 0, "config": config.duplicate(true), "health": config.max_health, "energy": config.energy_per_turn,
		"guard": 0, "enemy_health": config.encounters[0].hp, "enemy_guard": 0, "turn": 1, "used": {},
		"messages": ["첫 인도에 앞서 보따리를 꾸려 보세요."], "reactions": [],
		"packed_items": {}, "inventory_items": {}}

static func enemy(state: Dictionary) -> Dictionary:
	return state.config.encounters[state.encounter].duplicate(true)

static func intent(state: Dictionary) -> Dictionary:
	var sequence: Array = state.config.encounters[state.encounter].intents
	return sequence[(int(state.turn) - 1) % sequence.size()].duplicate(true)

static func use_error(state: Dictionary, uid: String) -> String:
	if state.phase != "battle": return "보따리를 정리한 뒤 전투를 시작하세요."
	if not state.packed_items.has(uid): return "보따리에 넣은 물건만 사용할 수 있습니다."
	var item: Dictionary = state.packed_items[uid]
	if not EffectApplier.has_trigger(item, "use"): return "자동으로 효과가 적용되는 물건입니다."
	if int(state.used.get(uid, 0)) >= int(item.uses_per_turn): return "이번 턴에 이미 사용했습니다."
	if state.energy < item.cost: return "기력이 부족합니다."
	return ""

static func resolve(before: Dictionary, request: Dictionary) -> CombatResolution:
	var simulation := CombatSimulator.new()
	simulation._state = before.duplicate(true)
	simulation._resolve_request(request.duplicate(true))
	if not simulation._failure.is_empty():
		# Reject the entire transaction, including costs/consumption, on a bad cascade.
		return CombatResolution.new(before, before, [], simulation._failure)
	return CombatResolution.new(before, simulation._state, simulation._events)

func _resolve_request(request: Dictionary) -> void:
	if not EffectApplier.within_budget(_state.packed_items):
		_failure = "보따리 효과 계획의 처리 한도를 초과했습니다."
		return
	_failure = _validate_reactions()
	if not _failure.is_empty(): return
	_state.reactions.sort_custom(_reaction_precedes)
	match request.get("type", ""):
		"start": _start()
		"use_item": _use(str(request.get("uid", "")))
		"end_turn": _end_turn()
		"advance": _advance()
		_: _failure = "알 수 없는 전투 명령입니다."

func _start() -> void:
	if _state.phase != "packing":
		_failure = "지금은 전투를 시작할 수 없습니다."
		return
	var has_attack := false
	for item: Dictionary in _state.packed_items.values():
		for unit: Dictionary in item.effects:
			has_attack = has_attack or (unit.trigger == "use" and unit.operation == "damage" and unit.target == "opponent")
	if not has_attack:
		_failure = "공격 도구를 하나 이상 보따리에 넣어 주세요."
		return
	_state.phase = "battle"
	_state.enemy_health = enemy(_state).hp
	_state.enemy_guard = 0
	_state.energy = _state.config.energy_per_turn
	_state.guard = 0
	_state.turn = 1
	_state.used.clear()
	_record("battle_started", "%s — 인도를 방해하는 응어리를 걷어내세요." % enemy(_state).name)

func _use(uid: String) -> void:
	_failure = use_error(_state, uid)
	if not _failure.is_empty(): return
	var item: Dictionary = _state.packed_items[uid]
	_state.energy -= item.cost
	_state.used[uid] = int(_state.used.get(uid, 0)) + 1
	var root_id := _record("action_started", "%s 사용 · 기력 %d" % [item.name, item.cost], {"source": uid})
	for plan in EffectApplier.plan(_state.packed_items, uid, "use"):
		plan.cause_id = root_id
		plan.depth = 0
		_pending.append(plan)
	_drain_effects()
	if not _failure.is_empty(): return
	if item.consumable:
		_state.packed_items.erase(uid)
		_state.inventory_items.erase(uid)
		_record("consumed", "%s 소모" % item.name, {"source": uid, "cause_id": root_id})
	_settle_outcome()

func _end_turn() -> void:
	if _state.phase != "battle":
		_failure = "지금은 턴을 종료할 수 없습니다."
		return
	var plans: Array[Dictionary] = []
	for uid: String in _state.packed_items:
		for plan in EffectApplier.plan(_state.packed_items, uid, "turn_end"):
			if plan.amount > 0 or plan.kind == "set_guard": plans.append(plan)
	plans.sort_custom(_plan_precedes)
	_pending.append_array(plans)
	_pending.append(EffectApplier.actor_plan(intent(_state), "enemy", enemy(_state).name))
	_drain_effects()
	if not _failure.is_empty(): return
	_settle_outcome()
	if _state.phase == "battle":
		_state.guard = 0
		_state.turn += 1
		_state.energy = _state.config.energy_per_turn
		_state.used.clear()
		_record("turn_started", "%d턴 · 기력 회복" % _state.turn)

func _advance() -> void:
	if _state.phase != "victory":
		_failure = "전투를 마친 뒤 다음 길목으로 이동하세요."
		return
	if _state.encounter == _state.config.encounters.size() - 1:
		_state.phase = "complete"
		_record("practice_completed", "모든 길목을 통과했습니다. 인도 연습 완료!")
	else:
		_state.encounter += 1
		_state.phase = "packing"
		_state.enemy_health = enemy(_state).hp
		_state.enemy_guard = 0
		_state.used.clear()
		_state.energy = _state.config.energy_per_turn
		_state.guard = 0
		_state.turn = 1
		# Explicit test reactions are encounter-scoped; authored reactions come from config.
		_state.reactions.clear()
		_record("encounter_prepared", "다음 길목에 맞게 보따리를 정리하세요.")

func _drain_effects() -> void:
	while not _pending.is_empty():
		var effect: Dictionary = _pending.pop_front()
		_processed += 1
		if _processed > MAX_EFFECTS or int(effect.get("depth", 0)) > MAX_DEPTH:
			_failure = "연쇄 효과 한도를 초과했습니다. 이번 행동을 적용하지 않았습니다."
			return
		var cause := int(effect.get("cause_id", 0))
		for bonus: Dictionary in effect.get("bonuses", []):
			cause = _record("adjacency_bonus", "%s → %s +%d" % [bonus.name, effect.label, bonus.amount],
				{"source": bonus.source, "target": effect.source, "effect_id": bonus.effect_id, "amount": bonus.amount, "cause_id": cause})
			if not _failure.is_empty(): return
		effect.cause_id = cause
		_apply_effect(effect)
		if not _failure.is_empty(): return

func _apply_effect(effect: Dictionary) -> void:
	var result := EffectApplier.evaluate(_state, effect)
	if result.get("skip", false): return
	if result.has("error"):
		_failure = result.error
		return
	_state.merge(result.changes, true)
	effect.merge(result.details, true)
	var event_id := _record(effect.kind, result.message, effect)
	if result.damage > 0:
		_enqueue_reactions(effect.target, event_id, int(effect.get("depth", 0)) + 1)

func _enqueue_reactions(damaged_owner: String, cause: int, depth: int) -> void:
	var plans: Array[Dictionary] = []
	# Explicit encounter fixtures remain available to cascade tests.
	for reaction: Dictionary in _state.reactions:
		if reaction.owner != damaged_owner: continue
		plans.append({"kind": reaction.effect, "source": reaction.id, "effect_id": reaction.id,
			"label": reaction.name, "target": reaction.target, "amount": reaction.amount,
			"priority": reaction.get("priority", 0), "max_per_action": reaction.get("max_per_action", 1),
			"trigger_key": "fixture/" + str(reaction.id)})
	if damaged_owner == "player":
		for uid: String in _state.packed_items:
			for plan in EffectApplier.plan(_state.packed_items, uid, "damage_taken"):
				plan.trigger_key = "item/" + uid + "/" + str(plan.effect_id)
				plans.append(plan)
	else:
		for unit: Dictionary in enemy(_state).reactions:
			var plan := EffectApplier.actor_plan(unit, "enemy", enemy(_state).name)
			plan.trigger_key = "enemy/" + str(unit.id)
			plans.append(plan)
	plans.sort_custom(_plan_precedes)
	for plan in plans:
		var count: int = _trigger_counts.get(plan.trigger_key, 0)
		if count >= int(plan.max_per_action): continue
		if plan.amount <= 0 and plan.kind != "set_guard": continue
		_trigger_counts[plan.trigger_key] = count + 1
		plan.cause_id = cause
		plan.depth = depth
		_pending.append(plan)

static func _plan_precedes(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority: return a.priority < b.priority
	if a.source != b.source: return str(a.source) < str(b.source)
	return str(a.effect_id) < str(b.effect_id)

static func _reaction_precedes(a: Dictionary, b: Dictionary) -> bool:
	if a.get("priority", 0) != b.get("priority", 0): return a.get("priority", 0) < b.get("priority", 0)
	return str(a.id) < str(b.id)

func _validate_reactions() -> String:
	var ids: Dictionary = {}
	if _state.reactions.size() > MAX_EFFECTS: return "연쇄 효과 정의가 너무 많습니다."
	for reaction: Dictionary in _state.reactions:
		for field in ["id", "name", "owner", "effect", "target", "amount"]:
			if not reaction.has(field): return "연쇄 효과 정의에 %s가 없습니다." % field
		if str(reaction.id).is_empty() or ids.has(reaction.id): return "연쇄 효과 ID가 중복되거나 비어 있습니다."
		ids[reaction.id] = true
		if reaction.owner not in ["player", "enemy"] or reaction.target not in ["player", "enemy"]:
			return "연쇄 효과 대상이 올바르지 않습니다."
		if reaction.effect not in ["damage", "guard"] or int(reaction.amount) < 0:
			return "연쇄 효과 종류나 수치가 올바르지 않습니다."
		if int(reaction.get("max_per_action", 1)) < 1 or int(reaction.get("max_per_action", 1)) > MAX_EFFECTS:
			return "연쇄 효과의 행동당 횟수가 올바르지 않습니다."
	return ""

func _settle_outcome() -> void:
	# Resolve death only after reactions. Simultaneous death is defeat, never victory + heal.
	if _state.health <= 0:
		_state.phase = "defeat"
		_record("defeat", "선배 사자가 당신을 데리고 돌아갑니다. 다시 준비해 보세요.")
	elif _state.enemy_health <= 0:
		_state.phase = "victory"
		var recovered := mini(int(_state.config.victory_heal), maxi(0, int(_state.config.max_health) - int(_state.health)))
		_state.health += recovered
		_record("victory", "길이 열렸습니다. 체력 %d 회복 · 보따리를 다시 정리하세요." % recovered)

func _record(kind: String, message: String, details: Dictionary = {}) -> int:
	if _events.size() >= MAX_EFFECTS:
		_failure = "연쇄 이벤트 한도를 초과했습니다. 이번 행동을 적용하지 않았습니다."
		return 0
	_state.messages.append(message)
	if _state.messages.size() > 30: _state.messages.pop_front()
	var event := details.duplicate(true)
	event["id"] = _events.size() + 1
	event["cause_id"] = int(details.get("cause_id", 0))
	event["kind"] = kind
	event["message"] = message
	event["after"] = _state.duplicate(true)
	_events.append(event)
	return event.id
