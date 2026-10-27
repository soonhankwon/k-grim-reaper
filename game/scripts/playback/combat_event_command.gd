class_name CombatEventCommand
extends ActionCommand
## Owns its Tween and cancellation. Its only mutation target is a presentation model.

var _receiver: WeakRef
var _event: Dictionary
var _tween: Tween

func _init(receiver: Node, event: Dictionary) -> void:
	_receiver = weakref(receiver)
	_event = event.duplicate(true)

func execute() -> void:
	if is_settled(): return
	var receiver = _receiver.get_ref()
	if not is_instance_valid(receiver) or not receiver.is_inside_tree():
		finish()
		return
	_tween = receiver.animate_event(_event.duplicate(true))
	# A signal listener may reset/skip while animate_event is starting.
	if is_settled():
		if _tween != null and _tween.is_valid(): _tween.kill()
		_tween = null
		return
	if _tween == null:
		_present()
	else:
		_tween.tween_callback(_present)

func _present() -> void:
	if is_settled(): return
	var receiver = _receiver.get_ref()
	if is_instance_valid(receiver) and receiver.is_inside_tree():
		receiver.present(_event.duplicate(true))
	_tween = null
	finish()

func cancel() -> void:
	super.cancel()
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
