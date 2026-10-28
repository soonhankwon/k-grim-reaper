class_name RoadView
extends Control
## Receives actor art and transient feedback through the displayed event snapshot.

var player_visual: Dictionary = {}
var enemy_visual: Dictionary = {}
var defeated := false
var feedback_target := ""
var feedback_kind := ""
var feedback_text := ""
var feedback_impact := false
var feedback_progress := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func begin_feedback(event: Dictionary, before: Dictionary) -> void:
	clear_feedback()
	var kind := str(event.get("kind", ""))
	var actor := str(event.get("target", ""))
	if kind == "action_started": actor = "player"
	if kind == "event_followup": actor = "player"
	if actor not in ["player", "enemy"]: return
	if kind not in ["action_started", "damage", "guard", "set_guard", "heal", "event_followup"]: return
	feedback_target = actor
	feedback_kind = kind
	var after: Dictionary = event.get("after", {})
	match kind:
		"damage":
			var damage := int(event.get("health_damage", 0))
			var blocked := int(event.get("absorbed", 0))
			feedback_text = "-%d" % damage if damage > 0 else ("막음 %d" % blocked if blocked > 0 else "0")
		"guard":
			var key := "guard" if actor == "player" else "enemy_guard"
			feedback_text = "방어 +%d" % maxi(0, int(after.get(key, 0)) - int(before.get(key, 0)))
		"set_guard":
			var key := "guard" if actor == "player" else "enemy_guard"
			feedback_text = "방어 %d" % int(after.get(key, 0))
		"heal", "event_followup":
			var key := "health" if actor == "player" else "enemy_health"
			var recovered := maxi(0, int(after.get(key, 0)) - int(before.get(key, 0)))
			feedback_text = "+%d" % recovered if recovered > 0 else ""
	queue_redraw()

func set_feedback_progress(value: float) -> void:
	feedback_progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func impact_feedback() -> void:
	feedback_impact = true
	queue_redraw()

func clear_feedback() -> void:
	feedback_target = ""
	feedback_kind = ""
	feedback_text = ""
	feedback_impact = false
	feedback_progress = 0.0
	queue_redraw()

func _actor(visual: Dictionary, origin: Vector2, faded := false, tint := Color.WHITE) -> void:
	var sprite := PresentationArt.actor_region(str(visual.get("presentation_id", "")))
	if sprite.has_area():
		var box := Vector2(150, 132)
		var fit := minf(box.x / sprite.size.x, box.y / sprite.size.y)
		var sprite_size := sprite.size * fit
		var color := Color(0.45, 0.45, 0.45) * tint if faded else tint
		draw_texture_rect_region(PresentationArt.ACTORS, Rect2(origin + Vector2((box.x - sprite_size.x) / 2, box.y - sprite_size.y), sprite_size), sprite, color)
		return
	draw_set_transform(origin, 0, Vector2.ONE * 4)
	for part: Array in visual.get("parts", []):
		var color := Color(part[4])
		draw_rect(Rect2(part[0], part[1], part[2], part[3]), (color.darkened(0.55) if faded else color) * tint)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	draw_rect(Rect2(171, 185, 136, 8), Color("1b2929"))
	draw_rect(Rect2(866, 185, 136, 8), Color("1b2929"))
	var player_offset := Vector2.ZERO
	var enemy_offset := Vector2.ZERO
	var player_tint := Color.WHITE
	var enemy_tint := Color.WHITE
	if feedback_target in ["player", "enemy"]:
		var direction := -1.0 if feedback_target == "player" else 1.0
		var offset := Vector2.ZERO
		var tint := Color.WHITE
		if feedback_kind == "action_started" and not feedback_impact:
			offset.x = -direction * roundf(sin(feedback_progress * PI) * 8.0 / 2.0) * 2.0
		elif feedback_kind == "damage" and feedback_impact:
			var strength := maxf(0.0, 1.0 - (feedback_progress - 0.5) * 2.0)
			offset.x = direction * roundf(strength * 8.0 / 2.0) * 2.0
			tint = Color(1.0, 0.7 + 0.3 * (1.0 - strength), 0.7 + 0.3 * (1.0 - strength))
		elif feedback_kind in ["guard", "set_guard", "heal", "event_followup"] and feedback_impact:
			var strength := maxf(0.0, 1.0 - (feedback_progress - 0.5) * 2.0)
			tint = Color(0.72 + 0.28 * (1.0 - strength), 1.0, 0.86 + 0.14 * (1.0 - strength))
		if feedback_target == "player":
			player_offset = offset
			player_tint = tint
		else:
			enemy_offset = offset
			enemy_tint = tint
	_actor(player_visual, Vector2(176, 58) + player_offset, false, player_tint)
	_actor(enemy_visual, Vector2(866, 62) + enemy_offset, defeated, enemy_tint)
	if feedback_impact and not feedback_text.is_empty() and feedback_target in ["player", "enemy"]:
		var anchor := Vector2(192, 92) if feedback_target == "player" else Vector2(882, 96)
		anchor.y -= roundf(maxf(0.0, feedback_progress - 0.5) * 24.0 / 2.0) * 2.0
		var color := Color("ffb09a") if feedback_kind == "damage" else Color("a6e8c4")
		var font := get_theme_default_font()
		if font != null:
			draw_string_outline(font, anchor, feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 120, 21, 4, Color("17232a"))
			draw_string(font, anchor, feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 120, 21, color)
