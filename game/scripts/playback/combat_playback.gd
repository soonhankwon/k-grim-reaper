class_name CombatPlayback
extends Node
## Read-only event tape -> presentation snapshots. No combat or inventory mutations.

signal presented
signal event_started(event: Dictionary)
signal settled
signal recovered(reason: String)
var seconds_per_step := 0.16
var queue: ActionQueue
var _view: Dictionary = {}
var _final: Dictionary = {}
var _feedback: WeakRef
var _epoch := 0

func _ready() -> void:
	queue = ActionQueue.new()
	add_child(queue)
	queue.drained.connect(_finish)
	queue.failed.connect(_recover)

func bind_feedback(target: CanvasItem) -> void:
	_feedback = weakref(target)

func snapshot() -> Dictionary:
	return _view.duplicate(true)

func is_busy() -> bool:
	return queue != null and queue.is_busy()

func play(result: CombatResolution) -> void:
	_final = result.after()
	_view = result.before()
	var commands: Array[ActionCommand] = []
	for event: Dictionary in result.events():
		commands.append(CombatEventCommand.new(self, event))
	if not queue.start(commands):
		_recover("연출을 시작하지 못해 확정된 결과를 표시합니다.")
		return
	presented.emit()

func reset(state: Dictionary) -> void:
	_epoch += 1
	queue.cancel()
	_final = state.duplicate(true)
	_view = state.duplicate(true)
	_clear_feedback()
	presented.emit()

func skip() -> void:
	if not is_busy(): return
	_epoch += 1
	queue.cancel()
	_finish()

func animate_event(event: Dictionary) -> Tween:
	var epoch := _epoch
	event_started.emit(event.duplicate(true))
	if epoch != _epoch: return null
	if seconds_per_step <= 0.0: return null
	var tween := create_tween()
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target):
		target.modulate = Color("e9997b") if event.kind == "damage" else Color("88cbb7")
		tween.tween_property(target, "modulate", Color.WHITE, seconds_per_step)
	else:
		tween.tween_interval(seconds_per_step)
	return tween

func present(event: Dictionary) -> void:
	_view = event.after.duplicate(true)
	presented.emit()

func _finish() -> void:
	_view = _final.duplicate(true)
	_clear_feedback()
	# Let the session restore its input lock before the final UI refresh.
	settled.emit()
	presented.emit()

func _recover(reason: String) -> void:
	_epoch += 1
	queue.cancel()
	_finish()
	recovered.emit(reason)

func _clear_feedback() -> void:
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target): target.modulate = Color.WHITE
