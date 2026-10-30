class_name LayoutFeedbackCommand
extends ActionCommand
## Owns the short, cancellable animation after a successful layout transaction.

var _target: WeakRef
var _tween: Tween

func _init(target: Node) -> void:
	_target = weakref(target)

func execute() -> void:
	if is_settled(): return
	var target = _target.get_ref()
	if not is_instance_valid(target) or not target.is_inside_tree():
		finish()
		return
	_tween = target.create_tween()
	_tween.tween_method(target.set_placement_feedback_progress, 0.0, 1.0, 0.32)
	_tween.tween_callback(_complete)

func _complete() -> void:
	if is_settled(): return
	var target = _target.get_ref()
	if is_instance_valid(target): target.clear_placement_feedback()
	_tween = null
	finish()

func cancel() -> void:
	super.cancel()
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
	var target = _target.get_ref()
	if is_instance_valid(target): target.clear_placement_feedback()
