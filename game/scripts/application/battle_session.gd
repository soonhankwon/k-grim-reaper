class_name BattleSession
extends Node
## The single gameplay mutation boundary: validate -> simulate -> commit -> play.

signal presented
signal event_started(event: Dictionary)
signal playback_recovered(reason: String)
var playback: CombatPlayback
var _resolver: CombatResolver
var _submitting := false
var save_service: SaveService

func _ready() -> void:
	playback = CombatPlayback.new()
	add_child(playback)
	playback.presented.connect(func(): presented.emit())
	playback.event_started.connect(func(event: Dictionary): event_started.emit(event))
	playback.settled.connect(_on_settled)
	playback.recovered.connect(func(reason: String): playback_recovered.emit(reason))

func reset(inventory: InventoryModel, initial: Dictionary = {}) -> void:
	_submitting = true
	_resolver = CombatResolver.new(inventory, initial)
	inventory.locked = _resolver.phase in ["battle", "route", "event_result", "defeat", "complete"]
	playback.reset(_resolver.snapshot())
	_submitting = false
	presented.emit()

func is_busy() -> bool:
	return _submitting or playback.is_busy()

func prepare_new(inventory: InventoryModel) -> String:
	if _submitting: return "현재 요청이 끝난 뒤 다시 시작하세요."
	if save_service == null: return ""
	_submitting = true
	var next := CombatResolver.new(inventory)
	var error := save_service.write_slot(next.snapshot(), inventory, [])
	_submitting = false
	return error

func prepare_archived_new(inventory: InventoryModel) -> String:
	if _submitting or save_service == null: return "저장 파일을 다시 확인해 주세요."
	_submitting = true
	var next := CombatResolver.new(inventory)
	var error := save_service.archive_and_start(next.snapshot(), inventory, [])
	_submitting = false
	return error

func submit(request: Dictionary) -> String:
	if is_busy(): return "연출이 끝난 뒤 행동하세요."
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
			return "저장 실패 · 행동을 적용하지 않았습니다: " + error
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
	if is_busy(): return "연출이 끝난 뒤 보따리를 정리하세요."
	_submitting = true
	var model := _resolver.inventory
	var candidate := model.copy_for_transaction()
	var error := ""
	match kind:
		"place":
			error = candidate.placement_error(uid, origin, rotation)
			if error.is_empty(): candidate.place(uid, origin, rotation)
		"stash":
			if not candidate.move_to_stash(uid): error = "보따리 안의 물건을 선택하세요."
		"undo":
			if not candidate.undo(): error = "되돌릴 배치가 없습니다."
		_: error = "알 수 없는 배치 명령입니다."
	if error.is_empty() and (candidate.items != model.items or candidate.history != model.history):
		var after := _resolver.snapshot()
		after.inventory_items = candidate.items.duplicate(true)
		after.packed_items = candidate.combat_snapshot()
		if save_service != null: error = save_service.write_slot(after, candidate, candidate.history)
		if error.is_empty():
			model.items = candidate.items
			model.history = candidate.history
			model.changed.emit()
		else: error = "저장 실패 · 배치를 적용하지 않았습니다: " + error
	_submitting = false
	if error.is_empty(): refresh_layout()
	return error

func use_error(uid: String) -> String:
	return "연출 재생 중입니다." if is_busy() else _resolver.use_error(uid)

func display_snapshot() -> Dictionary:
	return playback.snapshot()

func state_snapshot() -> Dictionary:
	# For persistence/debug/tests only; rendering must use display_snapshot().
	return _resolver.snapshot()

func refresh_layout() -> void:
	if not is_busy(): playback.reset(_resolver.snapshot())

func skip_playback() -> void:
	if not _submitting: playback.skip()

func _on_settled() -> void:
	_resolver.inventory.locked = _resolver.phase in ["battle", "route", "event_result", "defeat", "complete"]
