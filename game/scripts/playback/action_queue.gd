class_name ActionQueue
extends Node
## Serial, frame-driven command pump. There is no await/signal-wait race or recursion.

signal drained
signal failed(reason: String)
var timeout_seconds := 4.0
var _busy := false
var _pending: Array[ActionCommand] = []
var _current: ActionCommand
var _completion: Callable
var _epoch := 0
var _elapsed := 0.0

func _ready() -> void:
	set_process(false)

func is_busy() -> bool:
	return _busy

func start(commands: Array[ActionCommand]) -> bool:
	if _busy: return false
	var seen: Dictionary = {}
	for command in commands:
		if command == null or command.is_settled() or seen.has(command): return false
		seen[command] = true
	_epoch += 1
	_pending = commands.duplicate()
	_busy = true
	set_process(true)
	return true

func _process(delta: float) -> void:
	if not _busy: return
	if _current != null:
		_elapsed += delta
		if _elapsed >= timeout_seconds:
			cancel()
			failed.emit("연출 응답 시간이 초과되어 확정된 결과를 표시합니다.")
		return
	if _pending.is_empty():
		_busy = false
		set_process(false)
		drained.emit()
		return
	_current = _pending.pop_front()
	_elapsed = 0.0
	_completion = _on_completed.bind(_epoch, _current)
	# Connect BEFORE execute: even a command that completes synchronously is safe.
	_current.completed.connect(_completion)
	_current.execute()

func _on_completed(epoch: int, command: ActionCommand) -> void:
	if epoch != _epoch or command != _current: return
	_disconnect_current()
	_current = null
	# Start the next command on a later frame, never inside a completion callback.

func _disconnect_current() -> void:
	if _current != null and _current.completed.is_connected(_completion):
		_current.completed.disconnect(_completion)

func cancel() -> void:
	_epoch += 1
	_disconnect_current()
	if _current != null: _current.cancel()
	for command in _pending: command.cancel()
	_current = null
	_pending.clear()
	_busy = false
	set_process(false)

func _exit_tree() -> void:
	cancel()
