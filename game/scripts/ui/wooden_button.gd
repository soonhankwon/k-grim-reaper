class_name WoodenButton
extends Button
## Hover and keyboard focus are presentation-only and never submit game actions.

var _feedback: ActionQueue

func _ready() -> void:
	_feedback = ActionQueue.new()
	add_child(_feedback)
	resized.connect(_update_pivot)
	mouse_entered.connect(_update_feedback)
	mouse_exited.connect(_update_feedback)
	focus_entered.connect(_update_feedback)
	focus_exited.connect(_update_feedback)
	visibility_changed.connect(_update_feedback)
	_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size / 2

func _update_feedback() -> void:
	if _feedback == null: return
	_feedback.cancel()
	if not is_visible_in_tree():
		scale = Vector2.ONE
		return
	var hovered := not disabled and (is_hovered() or has_focus())
	_feedback.start([ButtonFeedbackCommand.new(self, hovered)])
