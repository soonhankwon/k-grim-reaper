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
var _cinematics: WeakRef
var _board: WeakRef
var _vfx: WeakRef
var _vfx_active := false
var _telegraph: WeakRef
var _thread := false
var _frost := false
var _sound: WeakRef
var _cinematic := false
var _lethal := false
var _impactful := false
var _epoch := 0
var _event_duration := 0.0

func _ready() -> void:
	queue = ActionQueue.new()
	add_child(queue)
	queue.drained.connect(_finish)
	queue.failed.connect(_recover)

func bind_feedback(target: CanvasItem) -> void:
	_feedback = weakref(target)

func bind_telegraph(target: CanvasItem) -> void:
	_telegraph = weakref(target)

func bind_board(target: CanvasItem) -> void:
	_board = weakref(target)

func bind_vfx(target: CanvasItem) -> void:
	_vfx = weakref(target)

func bind_cinematics(target: CanvasItem) -> void:
	_cinematics = weakref(target)

func bind_sound(target: Node) -> void:
	_sound = weakref(target)

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
		_recover("Animation could not start. Showing the confirmed result.")
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
	var after: Dictionary = event.get("after", {})
	_lethal = event.get("kind", "") == "damage" and event.get("target", "") == "enemy" and int(event.get("health_damage", 0)) > 0 and int(after.get("enemy_health", 1)) <= 0
	_impactful = event.get("kind", "") == "damage" and int(event.get("health_damage", 0)) > 0
	_cinematic = false
	var cinema = _cinematics.get_ref() if _cinematics != null else null
	if seconds_per_step > 0.0 and is_instance_valid(cinema): _cinematic = cinema.begin_event(event.duplicate(true))
	_thread = false
	var thread = _telegraph.get_ref() if _telegraph != null else null
	if seconds_per_step > 0.0 and is_instance_valid(thread): _thread = thread.begin_thread_feedback(event.duplicate(true))
	_frost = false
	var board = _board.get_ref() if _board != null else null
	if seconds_per_step > 0.0 and is_instance_valid(board): _frost = board.begin_frost_feedback(event.duplicate(true), _view.duplicate(true))
	_vfx_active = false
	var vfx = _vfx.get_ref() if _vfx != null else null
	if seconds_per_step > 0.0 and is_instance_valid(vfx): _vfx_active = vfx.begin_feedback(event.duplicate(true), _view.duplicate(true))
	var multiplier := 2.75 if event.get("kind", "") == "damage" else (2.5 if event.get("kind", "") in ["guard", "set_guard", "heal", "event_followup"] else 1.0)
	_event_duration = float(cinema.duration_seconds) if _cinematic else (0.65 if _frost else maxf(0.0, seconds_per_step * multiplier))
	if _vfx_active and not _cinematic: _event_duration = maxf(_event_duration, 0.38)
	return _event_duration > 0.0

func animate_event(impact: Callable, completed: Callable) -> Tween:
	var tween := create_tween()
	if _cinematic:
		tween.tween_method(_update_feedback_progress, 0.0, 1.0, _event_duration)
		tween.tween_callback(impact)
	else:
		tween.tween_method(_update_feedback_progress, 0.0, 0.5, _event_duration * 0.35)
		tween.tween_callback(impact)
		if _impactful: tween.tween_interval(0.06 if _lethal else 0.035)
		tween.tween_method(_update_feedback_progress, 0.5, 1.0, _event_duration * 0.65)
	tween.tween_callback(completed)
	return tween

func _update_feedback_progress(value: float) -> void:
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("set_feedback_progress"): target.set_feedback_progress(value)
	var cinema = _cinematics.get_ref() if _cinematics != null else null
	if _cinematic and is_instance_valid(cinema): cinema.set_progress(value)
	var board = _board.get_ref() if _board != null else null
	if _frost and is_instance_valid(board): board.set_frost_progress(value)
	var thread = _telegraph.get_ref() if _telegraph != null else null
	if _thread and is_instance_valid(thread): thread.set_thread_progress(value)
	var vfx = _vfx.get_ref() if _vfx != null else null
	if _vfx_active and is_instance_valid(vfx): vfx.set_feedback_progress(value)

func present(event: Dictionary) -> void:
	var epoch := _epoch
	var before := _view
	_view = event.after.duplicate(true)
	var target = _feedback.get_ref() if _feedback != null else null
	if is_instance_valid(target) and target.has_method("impact_feedback"): target.impact_feedback()
	var vfx = _vfx.get_ref() if _vfx != null else null
	if _vfx_active and is_instance_valid(vfx): vfx.impact_feedback()
	var audio = _sound.get_ref() if _sound != null else null
	if is_instance_valid(audio):
		if event.get("kind", "") == "damage":
			if int(event.get("health_damage", 0)) > 0: audio.cue("hit")
			elif int(event.get("absorbed", 0)) > 0: audio.cue("guard")
		elif event.get("kind", "") in ["guard", "set_guard"]:
			var key := "guard" if event.get("target", "") == "player" else "enemy_guard"
			if int(_view.get(key, 0)) > int(before.get(key, 0)): audio.cue("guard")
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
	var cinema = _cinematics.get_ref() if _cinematics != null else null
	if is_instance_valid(cinema): cinema.clear()
	var board = _board.get_ref() if _board != null else null
	if is_instance_valid(board): board.clear_frost_feedback()
	_frost = false
	var thread = _telegraph.get_ref() if _telegraph != null else null
	if is_instance_valid(thread): thread.clear_thread_feedback()
	_thread = false
	var vfx = _vfx.get_ref() if _vfx != null else null
	if is_instance_valid(vfx): vfx.clear_feedback()
	_vfx_active = false
	var audio = _sound.get_ref() if _sound != null else null
	if is_instance_valid(audio): audio.stop()
	_cinematic = false
	_lethal = false
	_impactful = false

func _exit_tree() -> void:
	clear_event_feedback()
