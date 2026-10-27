class_name CombatResolver
extends RefCounted
## Authoritative transaction store. Only BattleSession submits requests in the game.
## Pure simulation returns a complete result before any canonical state is changed.

var inventory: InventoryModel
var _state: Dictionary
var phase: String:
	get: return _state.phase
var encounter: int:
	get: return _state.encounter
var health: int:
	get: return _state.health
var energy: int:
	get: return _state.energy
var guard: int:
	get: return _state.guard
var enemy_health: int:
	get: return _state.enemy_health
var enemy_guard: int:
	get: return _state.enemy_guard
var turn: int:
	get: return _state.turn
var used: Dictionary:
	get: return _state.used.duplicate(true)

func _init(model: InventoryModel, initial: Dictionary = {}) -> void:
	inventory = model
	_state = CombatSimulator.initial_state(model.config) if initial.is_empty() else initial.duplicate(true)

func snapshot() -> Dictionary:
	var result := _state.duplicate(true)
	result.packed_items = inventory.combat_snapshot()
	result.inventory_items = inventory.items.duplicate(true)
	return result

func submit(request: Dictionary) -> CombatResolution:
	var result := simulate(request)
	if result.error.is_empty(): commit(result, request)
	return result

func simulate(request: Dictionary) -> CombatResolution:
	var is_reward: bool = str(request.get("type", "")).begins_with("reward_")
	if is_reward: return RewardRules.resolve(snapshot(), request)
	if str(request.get("type", "")).begins_with("event_"): return EventRules.resolve(snapshot(), request)
	return CombatSimulator.resolve(snapshot(), request)

func clears_history(result: CombatResolution, request: Dictionary) -> bool:
	return request.get("type", "") == "start" or str(request.get("type", "")).begins_with("reward_") or str(request.get("type", "")).begins_with("event_") or inventory.items.size() != result.after().inventory_items.size()

func commit(result: CombatResolution, request: Dictionary) -> void:
	_state = result.after()
	# No per-item signals here: observers must never see a partially committed result.
	var clear_history := clears_history(result, request)
	inventory.items = _state.inventory_items.duplicate(true)
	inventory.locked = phase in ["battle", "route", "event_result", "defeat", "complete"]
	if clear_history: inventory.history.clear()

func enemy() -> Dictionary:
	return CombatSimulator.enemy(_state)

func intent() -> Dictionary:
	return CombatSimulator.intent(_state)

func use_error(uid: String) -> String:
	return CombatSimulator.use_error(snapshot(), uid)

# Synchronous helpers for headless rule tests; gameplay goes through BattleSession.
func start_battle() -> String:
	return submit({"type": "start"}).error

func use_item(uid: String) -> String:
	return submit({"type": "use_item", "uid": uid}).error

func end_turn() -> void:
	submit({"type": "end_turn"})

func advance() -> void:
	submit({"type": "advance"})
