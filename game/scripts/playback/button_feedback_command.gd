class_name ButtonFeedbackCommand
extends ActionCommand
## Owns only the button's temporary presentation scale.

var _target: WeakRef
var _hovered: bool
var _tween: Tween

func _init(target: Control, hovered: bool) -> void:
	_target = weakref(target)
	_hovered = hovered

func execute() -> void:
	if is_settled(): return
	var target = _target.get_ref()
	if not is_instance_valid(target) or not target.is_inside_tree():
		finish()
		return
	_tween = target.create_tween()
	if _hovered:
		_tween.tween_property(target, "scale", Vector2(1.015, 0.98), 0.08)
		_tween.tween_property(target, "scale", Vector2(1.01, 1.01), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(target, "scale", Vector2.ONE, 0.12)
	_tween.tween_callback(finish)

func cancel() -> void:
	super.cancel()
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null
