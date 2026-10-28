class_name CombatPlayback
extends Node
## Read-only event tape -> presentation snapshots. No combat or inventory mutations.

signal presented
signal event_started(event: Dictionary)
signal event_presented(event: Dictionary)
signal settled
signal recovered(reason: String)
var seconds_per_step := 0.16
var queue: ActionQueue
var _view: Dictionary = {}
var _final: Dictionary = {}
var _feedback: WeakRef
var _epoch := 0
var _event_duration := 0.0

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
	clear_event_feedback()
	presented.emit()

func skip() -> void:
	if not is_busy(): return
	_epoch += 1
	queue.cancel()
	_finish()

func begin_event(event: Dictionary) -> bool:
	var epoch := _epoch
	event_started.emit(event.duplicate(true))
	if epoch != _epoch: return false
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("begin_feedback"):
		target.begin_feedback(event.duplicate(true), _view.duplicate(true))
	var multiplier := 2.75 if event.get("kind", "") == "damage" else (2.5 if event.get("kind", "") in ["guard", "set_guard", "heal", "event_followup"] else 1.0)
	_event_duration = maxf(0.0, seconds_per_step * multiplier)
	return _event_duration > 0.0

func animate_event(impact: Callable, completed: Callable) -> Tween:
	var tween := create_tween()
	tween.tween_method(_update_feedback_progress, 0.0, 0.5, _event_duration * 0.35)
	tween.tween_callback(impact)
	tween.tween_method(_update_feedback_progress, 0.5, 1.0, _event_duration * 0.65)
	tween.tween_callback(completed)
	return tween

func _update_feedback_progress(value: float) -> void:
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("set_feedback_progress"): target.set_feedback_progress(value)

func present(event: Dictionary) -> void:
	var epoch := _epoch
	_view = event.after.duplicate(true)
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("impact_feedback"): target.impact_feedback()
	presented.emit()
	if epoch == _epoch: event_presented.emit(event.duplicate(true))

func _finish() -> void:
	_view = _final.duplicate(true)
	clear_event_feedback()
	settled.emit()
	presented.emit()

func _recover(reason: String) -> void:
	_epoch += 1
	queue.cancel()
	_finish()
	recovered.emit(reason)

func clear_event_feedback() -> void:
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("clear_feedback"): target.clear_feedback()

func _exit_tree() -> void:
	clear_event_feedback()
