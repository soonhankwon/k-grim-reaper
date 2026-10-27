class_name ActionCommand
extends RefCounted
## One-shot presentation command. Never receives the authoritative combat store.

signal completed
var _settled := false

func execute() -> void:
	finish()

func finish() -> void:
	if _settled: return
	_settled = true
	completed.emit()

func cancel() -> void:
	_settled = true

func is_settled() -> bool:
	return _settled
