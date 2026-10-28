class_name CombatEventCommand
extends ActionCommand
## Owns the Tween, impact callback and cancellation for one presentation event.

var _receiver: WeakRef
var _event: Dictionary
var _tween: Tween
var _did_impact := false

func _init(receiver: Node, event: Dictionary) -> void:
	_receiver = weakref(receiver)
	_event = event.duplicate(true)

func execute() -> void:
	if is_settled(): return
	var receiver = _receiver.get_ref()
	if not is_instance_valid(receiver) or not receiver.is_inside_tree():
		finish()
		return
	if not receiver.begin_event(_event.duplicate(true)) or is_settled():
		if not is_settled():
			_impact()
			_complete()
		return
	_tween = receiver.animate_event(_impact, _complete)
	if is_settled() and _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null

func _impact() -> void:
	if is_settled() or _did_impact: return
	_did_impact = true
	var receiver = _receiver.get_ref()
	if is_instance_valid(receiver) and receiver.is_inside_tree(): receiver.present(_event.duplicate(true))

func _complete() -> void:
	if is_settled(): return
	var receiver = _receiver.get_ref()
	if is_instance_valid(receiver) and receiver.is_inside_tree(): receiver.clear_event_feedback()
	_tween = null
	finish()

func cancel() -> void:
	super.cancel()
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
	var receiver = _receiver.get_ref()
	if is_instance_valid(receiver) and receiver.is_inside_tree(): receiver.clear_event_feedback()
