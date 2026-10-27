class_name CombatResolution
extends RefCounted
## Value-only transaction output. Copies prevent consumers from modifying the tape.

var error: String:
	get: return _error
var _error: String
var _before: Dictionary
var _after: Dictionary
var _events: Array

func _init(before: Dictionary, after: Dictionary, events: Array, failure := "") -> void:
	_error = failure
	_before = before.duplicate(true)
	_after = after.duplicate(true)
	_events = events.duplicate(true)

func before() -> Dictionary:
	return _before.duplicate(true)

func after() -> Dictionary:
	return _after.duplicate(true)

func events() -> Array:
	return _events.duplicate(true)
