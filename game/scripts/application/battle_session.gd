class_name BattleSession
extends Node
## The single gameplay mutation boundary: validate -> simulate -> commit -> play.

signal presented
signal event_started(event: Dictionary)
signal event_presented(event: Dictionary)
signal playback_recovered(reason: String)
var playback: CombatPlayback
var _resolver: CombatResolver
var _submitting := false
var save_service: SaveService
var _ruleset: RefCounted

func _ready() -> void:
	playback = CombatPlayback.new()
	add_child(playback)
	playback.presented.connect(func(): presented.emit())
	playback.event_started.connect(func(event: Dictionary): event_started.emit(event))
	playback.event_presented.connect(func(event: Dictionary): event_presented.emit(event))
	playback.settled.connect(_on_settled)
	playback.recovered.connect(func(reason: String): playback_recovered.emit(reason))

func install_unsaved_ruleset(ruleset: RefCounted) -> bool:
	if save_service != null or is_busy() or _ruleset != null or ruleset == null: return false
	if not ruleset.has_method("resolve") or not ruleset.has_method("use_error"): return false
	if _resolver != null and _resolver.phase != "packing": return false
	_ruleset = ruleset
	if _resolver != null: _resolver.ruleset = ruleset
	return true

func reset(inventory: InventoryModel, initial: Dictionary = {}) -> void:
	_submitting = true
	_resolver = CombatResolver.new(inventory, initial, _ruleset)
	inventory.locked = _resolver.phase in ["battle", "route", "event_result", "defeat", "complete"]
	playback.reset(_resolver.snapshot())
	_submitting = false
	presented.emit()

func is_busy() -> bool:
	return _submitting or playback.is_busy()

func prepare_new(inventory: InventoryModel) -> String:
	if _ruleset != null and save_service != null: return "Saving is unavailable with experimental rules."
	if _submitting: return "Wait for the current action before restarting."
	if save_service == null: return ""
	_submitting = true
	var next := CombatResolver.new(inventory)
	var error := save_service.write_slot(next.snapshot(), inventory, [])
	_submitting = false
	return error

func prepare_archived_new(inventory: InventoryModel) -> String:
	if _ruleset != null: return "Saving is unavailable with experimental rules."
	if _submitting or save_service == null: return "Please check the save file again."
	_submitting = true
	var next := CombatResolver.new(inventory)
	var error := save_service.archive_and_start(next.snapshot(), inventory, [])
	_submitting = false
	return error

func submit(request: Dictionary) -> String:
	if _ruleset != null and save_service != null: return "Saving is unavailable with experimental rules."
	if is_busy(): return "Wait for the animation to finish."
	_submitting = true
	var result := _resolver.simulate(request)
	if not result.error.is_empty():
		_submitting = false
		return result.error
	if save_service != null:
		var history: Array = [] if _resolver.clears_history(result, request) else _resolver.inventory.history
		var error := save_service.write_slot(result.after(), _resolver.inventory, history)
		if not error.is_empty():
			_submitting = false
			return "Save failed · action not applied: " + error
	_resolver.commit(result, request)
	_resolver.inventory.locked = true
	playback.play(result)
	_submitting = false
	return ""

func place(uid: String, origin: Vector2i, rotation: int) -> String:
	return _layout_transaction("place", uid, origin, rotation)

func stash(uid: String) -> String:
	return _layout_transaction("stash", uid, Vector2i.ZERO, 0)

func undo_layout() -> String:
	return _layout_transaction("undo", "", Vector2i.ZERO, 0)

func _layout_transaction(kind: String, uid: String, origin: Vector2i, rotation: int) -> String:
	if _ruleset != null and save_service != null: return "Saving is unavailable with experimental rules."
	if is_busy(): return "Wait for the animation before rearranging your bag."
	_submitting = true
	var model := _resolver.inventory
	var candidate := model.copy_for_transaction()
	var error := ""
	match kind:
		"place":
			error = candidate.placement_error(uid, origin, rotation)
			if error.is_empty(): candidate.place(uid, origin, rotation)
		"stash":
			if not candidate.move_to_stash(uid): error = "Select an item in the bag."
		"undo":
			if not candidate.undo(): error = "No placement to undo."
		_: error = "Unknown placement command."
	if error.is_empty() and (candidate.items != model.items or candidate.history != model.history):
		var after := _resolver.snapshot()
		after.inventory_items = candidate.items.duplicate(true)
		after.packed_items = candidate.combat_snapshot()
		if save_service != null: error = save_service.write_slot(after, candidate, candidate.history)
		if error.is_empty():
			model.items = candidate.items
			model.history = candidate.history
			model.changed.emit()
		else: error = "Save failed · placement not applied: " + error
	_submitting = false
	if error.is_empty(): refresh_layout()
	return error

func use_error(uid: String) -> String:
	return "Animation in progress." if is_busy() else _resolver.use_error(uid)

func display_snapshot() -> Dictionary:
	return playback.snapshot()

func preview_end_turn() -> CombatResolution:
	# Preview is based exclusively on the displayed state and never commits or saves.
	var view := display_snapshot()
	if is_busy(): return CombatResolution.new(view, view, [], "Wait for the animation to finish.")
	return CombatSimulator.resolve(view, {"type": "end_turn"}) if _ruleset == null else _ruleset.resolve(view, {"type": "end_turn"})

func state_snapshot() -> Dictionary:
	# For persistence/debug/tests only; rendering must use display_snapshot().
	return _resolver.snapshot()

func refresh_layout() -> void:
	if not is_busy(): playback.reset(_resolver.snapshot())

func skip_playback() -> void:
	if not _submitting: playback.skip()

func _on_settled() -> void:
	_resolver.inventory.locked = _resolver.phase in ["battle", "route", "event_result", "defeat", "complete"]
