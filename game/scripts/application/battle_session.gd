class_name BattleSession
extends Node
## The single gameplay mutation boundary: validate -> simulate -> commit -> play.

signal presented
signal event_started(event: Dictionary)
signal playback_recovered(reason: String)
var playback: CombatPlayback
var _resolver: CombatResolver
var _submitting := false

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
	inventory.locked = _resolver.phase in ["battle", "defeat", "complete"]
	playback.reset(_resolver.snapshot())
	_submitting = false
	presented.emit()

func is_busy() -> bool:
	return _submitting or playback.is_busy()

func submit(request: Dictionary) -> String:
	if is_busy(): return "연출이 끝난 뒤 행동하세요."
	_submitting = true
	var result := _resolver.submit(request)
	if not result.error.is_empty():
		_submitting = false
		return result.error
	_resolver.inventory.locked = true
	playback.play(result)
	_submitting = false
	return ""

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
	_resolver.inventory.locked = _resolver.phase in ["battle", "defeat", "complete"]
