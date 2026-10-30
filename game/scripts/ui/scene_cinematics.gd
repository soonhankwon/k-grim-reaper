class_name SceneCinematics
extends Control
## Receives immutable presentation events; timing belongs to CombatEventCommand.
const PATH := "res://data/presentation/cinematics.json"
var entries: Dictionary = {}
var story_dialogue_enabled := false
var mode := ""
var data: Dictionary = {}
var visual: Dictionary = {}
var progress := 0.0
var sound: PresentationSound
var skip_button: Button
var _stamp_played := false
var duration_seconds := 2.4
var wipe: ColorRect
const WIPE = preload("res://shaders/ink_wipe.gdshader")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1280, 720)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary: entries = parsed
	wipe = ColorRect.new()
	wipe.size = Vector2(1280, 720)
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wipe_material := ShaderMaterial.new()
	wipe_material.shader = WIPE
	wipe.material = wipe_material
	add_child(wipe)
	skip_button = Button.new()
	skip_button.text = "Skip Animation"
	skip_button.position = Vector2(1070, 645)
	skip_button.size = Vector2(170, 36)
	add_child(skip_button)
	hide()

func begin_event(event: Dictionary) -> bool:
	clear()
	if event.get("kind", "") == "turn_started":
		mode = "turn"
		duration_seconds = 0.25
		progress = 0.0
		wipe.hide()
		skip_button.hide()
		show()
		if sound != null: sound.cue("stamp")
		queue_redraw()
		return true
	duration_seconds = 2.4
	wipe.show()
	skip_button.show()
	var after: Dictionary = event.get("after", {})
	var config: Dictionary = after.get("config", {})
	var encounters: Array = config.get("encounters", [])
	var index := int(after.get("encounter", -1))
	if index < 0 or index >= encounters.size(): return false
	visual = encounters[index].get("visual", {}).duplicate(true)
	var id := str(visual.get("presentation_id", ""))
	var table: Dictionary = {}
	var dialogue_table: Dictionary = entries.get("dialogue", {})
	var actor_dialogue: Variant = dialogue_table.get(id, {})
	var moment: Variant = actor_dialogue.get(str(event.get("kind", "")), {}) if actor_dialogue is Dictionary else {}
	if story_dialogue_enabled and moment is Dictionary and moment.get("speaker") is String and moment.get("text") is String and not moment.speaker.is_empty() and not moment.text.is_empty():
		mode = "dialogue"
		data = moment.duplicate(true)
		duration_seconds = 3.2
		progress = 0.0
		wipe.hide()
		show()
		queue_redraw()
		return true
	if event.get("kind", "") == "battle_started":
		mode = "intro"
		table = entries.get("boss_intros", {})
	elif event.get("kind", "") == "event_continue" and after.get("phase", "") == "complete":
		mode = "memory"
		table = entries.get("memories", {})
	else: return false
	if not table.get(id) is Dictionary:
		mode = ""
		return false
	data = table[id].duplicate(true)
	if mode == "memory" and PresentationArt.visual_texture(str(data.get("image", ""))) == null:
		mode = ""
		return false
	_stamp_played = false
	progress = 0.0
	(wipe.material as ShaderMaterial).set_shader_parameter("coverage", 1.55)
	show()
	queue_redraw()
	if mode == "memory" and sound != null: sound.cue("wind")
	return true

func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	if mode in ["intro", "memory"]:
		var coverage := (1.0 - progress / 0.14) * 1.55 if progress < 0.14 else ((progress - 0.88) / 0.12 * 1.55 if progress > 0.88 else 0.0)
		(wipe.material as ShaderMaterial).set_shader_parameter("coverage", coverage)
	if mode == "intro" and progress >= 0.77 and not _stamp_played:
		_stamp_played = true
		if sound != null: sound.cue("stamp")
	queue_redraw()

func clear() -> void:
	mode = ""
	data = {}
	visual = {}
	progress = 0.0
	_stamp_played = false
	hide()
	queue_redraw()

func _draw() -> void:
	if mode.is_empty(): return
	var font := get_theme_default_font()
	if mode == "intro":
		draw_rect(Rect2(0,0,1280,720), Color("161e22"))
		draw_rect(Rect2(0,64,1280,592), Color("d7cbb1"))
		for x in range(0, 1280, 40): draw_line(Vector2(x, 65), Vector2(x + 180, 655), Color(Color("8b846f"), 0.12), 1)
		var id := str(visual.get("presentation_id", ""))
		var texture := PresentationArt.visual_texture(str(visual.get("texture_path", "")))
		var rect: Rect2
		if texture != null: rect = Rect2(Vector2.ZERO, texture.get_size())
		else:
			texture = PresentationArt.source_actor_texture(id)
			rect = PresentationArt.source_actor_region(id)
		if rect.has_area():
			var scale_factor := minf(530.0 / rect.size.x, 520.0 / rect.size.y)
			var art_size := rect.size * scale_factor
			var slide := 120.0 * (1.0 - smoothstep(0.04, 0.48, progress))
			draw_texture_rect_region(texture, Rect2(Vector2(720 + slide, 630 - art_size.y), art_size), rect)
		if font != null:
			var title := str(data.get("title", ""))
			var count := clampi(int((progress - 0.12) / 0.50 * title.length()), 0, title.length())
			draw_string(font, Vector2(120, 285), title.substr(0, count), HORIZONTAL_ALIGNMENT_LEFT, 600, 56, Color("181e20"))
			if progress >= 0.54:
				draw_string(font, Vector2(124, 333), str(data.get("epithet", "")), HORIZONTAL_ALIGNMENT_LEFT, 570, 26, Color("323532"))
			draw_string(font, Vector2(124, 370), str(data.get("subtitle", "")), HORIZONTAL_ALIGNMENT_LEFT, 500, 22, Color("4d4541"))
		if progress >= 0.77:
			var stamp := Rect2(133, 417, 72, 72)
			draw_rect(stamp, Color("9f302b"), false, 5)
			if font != null: draw_string(font, Vector2(138, 462), "SEAL", HORIZONTAL_ALIGNMENT_CENTER, 62, 20, Color("9f302b"))
	elif mode == "dialogue":
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.05, 0.06, 0.38))
		draw_rect(Rect2(56, 480, 1168, 155), Color("192225"))
		draw_rect(Rect2(56, 480, 1168, 155), Color("d0ab72"), false, 3)
		if font != null:
			draw_string(font, Vector2(82, 515), str(data.speaker), HORIZONTAL_ALIGNMENT_LEFT, 1000, 22, Color("e4bd7c"))
			draw_multiline_string(font, Vector2(82, 552), str(data.text), HORIZONTAL_ALIGNMENT_LEFT, 1080, 24, -1, Color("f3e8cf"))
	elif mode == "memory":
		var texture := PresentationArt.visual_texture(str(data.get("image", "")))
		if texture == null: return
		var scale_factor := 1.0 + 0.16 * progress
		var focus: Array = data.get("focus", [0.5, 0.5])
		var origin := -Vector2(float(focus[0]) * 1280, float(focus[1]) * 720) * (scale_factor - 1.0)
		draw_texture_rect(texture, Rect2(origin, Vector2(1280,720) * scale_factor), false)
		draw_rect(Rect2(0, 590, 1280, 130), Color(Color("111820"), 0.80))
		if font != null: draw_string(font, Vector2(80, 634), str(data.get("caption", "")), HORIZONTAL_ALIGNMENT_CENTER, 1120, 22, Color("ede1c8"))
	else:
		var fade := sin(progress * PI)
		var shake := 3.0 * sin(progress * PI * 8.0) * (1.0 - progress)
		var stamp := Rect2(Vector2(575 + shake, 300), Vector2(130, 130))
		draw_rect(stamp, Color(Color("9f302b"), fade * 0.75), false, 7)
		if font != null: draw_string(font, Vector2(581 + shake, 378), "TURN", HORIZONTAL_ALIGNMENT_CENTER, 118, 32, Color(Color("9f302b"), fade * 0.8))
	if mode != "turn":
		draw_rect(Rect2(0,0,1280,64), Color("111518"))
		draw_rect(Rect2(0,656,1280,64), Color("111518"))
