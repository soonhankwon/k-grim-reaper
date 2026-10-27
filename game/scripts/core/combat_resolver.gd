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
	var result := CombatSimulator.resolve(snapshot(), request)
	if not result.error.is_empty():
		return result
	_state = result.after()
	# No per-item signals here: observers must never see a partially committed result.
	var consumed: bool = inventory.items.size() != _state.inventory_items.size()
	inventory.items = _state.inventory_items.duplicate(true)
	inventory.locked = phase in ["battle", "defeat", "complete"]
	if request.type == "start" or consumed:
		inventory.history.clear()
	return result

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
