extends Control
## Connects the isolated chapter-one demo to the unsaved stage-two prototype.

const Arang = preload("res://tests/arang_experiment_setup.gd")
const Yagwang = preload("res://tests/yagwang_experiment_setup.gd")
var save_slot := ""
var skip_intro := false
var arang: Control
var preview: Control
var intro: LaunchIntro

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	DisplayServer.window_set_title("Reaper's Bundle — First Delivery")
	if skip_intro:
		_start_arang()
		return
	intro = LaunchIntro.new()
	var has_save := not save_slot.is_empty() and (FileAccess.file_exists(save_slot) or FileAccess.file_exists(save_slot + ".bak"))
	intro.action_text = "Continue Delivery" if has_save else "Begin Delivery"
	intro.note = "Continue your saved Arang demo." if has_save else "Prepare your bag before your first encounter."
	intro.accepted.connect(_start_arang)
	add_child(intro)

func _start_arang() -> void:
	if arang != null: return
	var loaded := Arang.create(self, save_slot)
	if loaded == null:
		if intro != null: intro.note_label.text = "Could not load the Arang demo. Your save was preserved."
		push_error("Could not load the Arang demo.")
		return
	arang = loaded
	arang.session.presented.connect(_refresh_completion)
	_refresh_completion()
	if intro != null:
		intro.queue_free()
		intro = null

func _refresh_completion() -> void:
	if not is_instance_valid(arang): return
	var complete: bool = arang.session.display_snapshot().get("phase", "") == "complete" and not arang.session.is_busy()
	if complete:
		if arang.primary.pressed.is_connected(arang._primary_action): arang.primary.pressed.disconnect(arang._primary_action)
		if not arang.primary.pressed.is_connected(_show_preview_intro): arang.primary.pressed.connect(_show_preview_intro)
		arang.primary.text = "Next: Stage 2 Preview"
	else:
		if arang.primary.pressed.is_connected(_show_preview_intro): arang.primary.pressed.disconnect(_show_preview_intro)
		if not arang.primary.pressed.is_connected(arang._primary_action): arang.primary.pressed.connect(arang._primary_action)

func _show_preview_intro() -> void:
	if intro != null or preview != null or arang.session.is_busy(): return
	arang.set_process_unhandled_key_input(false)
	intro = LaunchIntro.new()
	intro.heading = "THE SHOE THIEF"
	intro.chapter = "ARANG COMPLETE · STAGE 2 PREVIEW"
	intro.description = "Your next encounter is Yagwanggwi, the spirit who steals shoes on New Year's Eve."
	intro.instructions = "Hide shoes above the bottom row.\nMake room for the sieve to delay the spirit.\nSurvive until dawn or defeat the spirit."
	intro.note = "Separate starting bag · Preview progress is not saved."
	intro.action_text = "Play Stage 2 Preview"
	intro.cancel_text = "Back to Arang"
	intro.accepted.connect(_start_preview)
	intro.cancelled.connect(_close_preview_intro)
	add_child(intro)

func _close_preview_intro() -> void:
	if intro == null: return
	intro.queue_free()
	intro = null
	if is_instance_valid(arang): arang.set_process_unhandled_key_input(true)

func _start_preview() -> void:
	if preview != null: return
	var loaded := Yagwang.create(self)
	if loaded == null:
		if intro != null: intro.note_label.text = "Could not load this preview. Your Arang progress is unchanged."
		push_error("Could not load the stage-two preview.")
		return
	preview = loaded
	arang.hide()
	arang.set_process_unhandled_key_input(false)
	_close_preview_intro()
	arang.set_process_unhandled_key_input(false)
	preview.layout.buttons.story.hide()
	var back := Button.new()
	back.text = "Exit"
	back.tooltip_text = "Exit the unsaved preview and return to Arang."
	back.accessibility_name = "Exit the unsaved preview and return to Arang"
	back.position = Vector2(934, 8)
	back.size = Vector2(100, 32)
	back.add_theme_font_size_override("font_size", 16)
	preview.layout.add_child(back)
	back.pressed.connect(_return_to_arang)

func _return_to_arang() -> void:
	if preview == null: return
	preview.queue_free()
	preview = null
	arang.show()
	arang.set_process_unhandled_key_input(true)
	_refresh_completion()
