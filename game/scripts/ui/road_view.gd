class_name RoadView
extends Control
## Receives actor art and transient feedback through the displayed event snapshot.

class FeedbackOverlay extends Control:
	var source: Control
	func _draw() -> void:
		if source == null or not source.feedback_impact or source.feedback_text.is_empty() or source.feedback_target not in ["player", "enemy"]: return
		var anchor := Vector2(192, 86) if source.feedback_target == "player" else Vector2(882, 88)
		anchor.y -= roundf(maxf(0.0, source.feedback_progress - 0.5) * 24.0 / 2.0) * 2.0
		var color := Color("ffb09a") if source.feedback_kind == "damage" and source.feedback_damage > 0 else Color("a6e8c4")
		var font := get_theme_default_font()
		if font != null:
			draw_string_outline(font, anchor, source.feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 120, 24, 4, Color("17232a"))
			draw_string(font, anchor, source.feedback_text, HORIZONTAL_ALIGNMENT_CENTER, 120, 24, color)

var player_visual: Dictionary = {}
var enemy_visual: Dictionary = {}
var defeated := false
var enemy_lost := false
var feedback_lethal := false
var enemy_sprite: Sprite2D
var feedback_overlay: FeedbackOverlay
const INK_SHADER = preload("res://shaders/ink_dissolve.gdshader")
var feedback_target := ""
var feedback_kind := ""
var feedback_text := ""
var feedback_impact := false
var feedback_progress := 0.0
var feedback_damage := 0
var feedback_absorbed := 0
var feedback_guard_change := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_sprite = Sprite2D.new()
	enemy_sprite.centered = false
	enemy_sprite.region_enabled = true
	var shader := ShaderMaterial.new()
	shader.shader = INK_SHADER
	enemy_sprite.material = shader
	add_child(enemy_sprite)
	feedback_overlay = FeedbackOverlay.new()
	feedback_overlay.source = self
	feedback_overlay.size = Vector2(1280, 206)
	feedback_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback_overlay)

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
	var after_state: Dictionary = event.get("after", {})
	feedback_lethal = kind == "damage" and actor == "enemy" and int(event.get("health_damage", 0)) > 0 and int(before.get("enemy_health", 0)) > 0 and int(after_state.get("enemy_health", 1)) <= 0
	var after: Dictionary = event.get("after", {})
	match kind:
		"damage":
			var damage := int(event.get("health_damage", 0))
			var blocked := int(event.get("absorbed", 0))
			feedback_damage = damage
			feedback_absorbed = blocked
			feedback_text = "-%d" % damage if damage > 0 else ("Blocked %d" % blocked if blocked > 0 else "0")
		"guard":
			var key := "guard" if actor == "player" else "enemy_guard"
			feedback_guard_change = maxi(0, int(after.get(key, 0)) - int(before.get(key, 0)))
			feedback_text = "Block +%d" % feedback_guard_change
		"set_guard":
			var key := "guard" if actor == "player" else "enemy_guard"
			feedback_guard_change = maxi(0, int(after.get(key, 0)) - int(before.get(key, 0)))
			feedback_text = "Block %d" % int(after.get(key, 0))
		"heal", "event_followup":
			var key := "health" if actor == "player" else "enemy_health"
			var recovered := maxi(0, int(after.get(key, 0)) - int(before.get(key, 0)))
			feedback_text = "+%d" % recovered if recovered > 0 else ""
	queue_redraw()

func set_feedback_progress(value: float) -> void:
	feedback_progress = clampf(value, 0.0, 1.0)
	if feedback_overlay != null: feedback_overlay.queue_redraw()
	queue_redraw()

func impact_feedback() -> void:
	feedback_impact = true
	if feedback_overlay != null: feedback_overlay.queue_redraw()
	queue_redraw()

func clear_feedback() -> void:
	feedback_target = ""
	feedback_kind = ""
	feedback_lethal = false
	feedback_text = ""
	feedback_impact = false
	feedback_progress = 0.0
	feedback_damage = 0
	feedback_absorbed = 0
	feedback_guard_change = 0
	if feedback_overlay != null: feedback_overlay.queue_redraw()
	queue_redraw()

func _draw_impact(center: Vector2) -> void:
	var phase := clampf((feedback_progress - 0.5) * 2.0, 0.0, 1.0)
	var strength := 1.0 - phase
	if feedback_kind == "damage" and feedback_damage > 0:
		var slash_start := center + Vector2(-88, 50)
		var slash_end := center + Vector2(90, -53)
		draw_line(slash_start, slash_end, Color(Color("151a1e"), strength), 14)
		draw_line(slash_start + Vector2(5, -4), slash_end + Vector2(0, -4), Color(Color("e5d6b4"), strength), 5)
		draw_line(center + Vector2(-43, -55), center + Vector2(51, 53), Color(Color("c66c49"), strength * 0.85), 4)
		for i in 6:
			var x := float([-72, -54, -24, 32, 65, 82][i]) * (1.0 + phase * 0.25)
			var y := float([-26, 35, -62, 49, -35, 17][i]) * (1.0 + phase * 0.25)
			draw_rect(Rect2(center + Vector2(x, y), Vector2(4, 4)), Color(Color("ebc78f"), strength))
	if feedback_absorbed > 0 or feedback_guard_change > 0:
		var radius := 48.0 + phase * 12.0
		var shield := PackedVector2Array([center + Vector2(-radius, -radius * 0.65), center + Vector2(0, -radius), center + Vector2(radius, -radius * 0.65), center + Vector2(radius * 0.82, radius * 0.48), center + Vector2(0, radius), center + Vector2(-radius * 0.82, radius * 0.48), center + Vector2(-radius, -radius * 0.65)])
		draw_polyline(shield, Color(Color("1d3333"), strength * 0.8), 7)
		draw_polyline(shield, Color(Color("a9ead9"), strength), 3)
		draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), Color(Color("e5f6df"), strength), 3)

func _actor(visual: Dictionary, origin: Vector2, faded := false, tint := Color.WHITE, mirrored := false) -> void:
	# The current atlas faces left. The left-side actor faces the opponent by mirroring.
	var box := Vector2(150, 132)
	var visual_id := str(visual.get("presentation_id", ""))
	var custom := PresentationArt.visual_texture(str(visual.get("texture_path", "")))
	var texture := custom if custom != null else PresentationArt.actor_texture(visual_id)
	var sprite := Rect2(Vector2.ZERO, texture.get_size()) if custom != null else PresentationArt.actor_region(visual_id)
	if sprite.has_area():
		var fit := minf(box.x / sprite.size.x, box.y / sprite.size.y)
		var sprite_size := sprite.size * fit
		var color := Color(0.45, 0.45, 0.45) * tint if faded else tint
		if mirrored:
			draw_set_transform(origin + Vector2(box.x, 0), 0, Vector2(-1, 1))
			draw_texture_rect_region(texture, Rect2(Vector2((box.x - sprite_size.x) / 2, box.y - sprite_size.y), sprite_size), sprite, color)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_texture_rect_region(texture, Rect2(origin + Vector2((box.x - sprite_size.x) / 2, box.y - sprite_size.y), sprite_size), sprite, color)
		return
	draw_set_transform(origin + Vector2(box.x if mirrored else 0, 0), 0, Vector2(-4 if mirrored else 4, 4))
	for part: Array in visual.get("parts", []):
		var color := Color(part[4])
		draw_rect(Rect2(part[0], part[1], part[2], part[3]), (color.darkened(0.55) if faded else color) * tint)
	draw_set_transform(Vector2.ZERO)

func _show_enemy(origin: Vector2, tint: Color) -> bool:
	if enemy_sprite == null: return false
	var id := str(enemy_visual.get("presentation_id", ""))
	var custom := PresentationArt.visual_texture(str(enemy_visual.get("texture_path", "")))
	var texture := custom if custom != null else PresentationArt.actor_texture(id)
	var region := Rect2(Vector2.ZERO, texture.get_size()) if custom != null else PresentationArt.actor_region(id)
	var showing_dissolve := feedback_lethal and feedback_impact
	if not region.has_area():
		enemy_sprite.hide()
		return false
	enemy_sprite.visible = not enemy_lost or showing_dissolve
	if not enemy_sprite.visible: return true
	var box := Vector2(150, 132)
	var fit := minf(box.x / region.size.x, box.y / region.size.y)
	var art_size := region.size * fit
	enemy_sprite.texture = texture
	enemy_sprite.region_rect = region
	enemy_sprite.position = origin + Vector2((box.x - art_size.x) / 2.0, box.y - art_size.y)
	enemy_sprite.scale = Vector2.ONE * fit
	enemy_sprite.modulate = (Color(0.45, 0.45, 0.45) * tint) if defeated else tint
	var amount := clampf((feedback_progress - 0.5) * 2.0, 0.0, 1.0) if showing_dissolve else 0.0
	(enemy_sprite.material as ShaderMaterial).set_shader_parameter("dissolve", amount)
	return true

func _draw() -> void:
	draw_rect(Rect2(171, 185, 136, 8), Color("1b2929"))
	draw_rect(Rect2(866, 185, 136, 8), Color("1b2929"))
	if feedback_impact and feedback_target in ["player", "enemy"]:
		_draw_impact(Vector2(251, 124) if feedback_target == "player" else Vector2(941, 128))
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
	_actor(player_visual, Vector2(176, 58) + player_offset, false, player_tint, true)
	if feedback_lethal and feedback_impact:
		var ink_alpha := 1.0 - clampf((feedback_progress - 0.5) * 1.8, 0.0, 1.0)
		draw_line(Vector2(824, 169), Vector2(1044, 65), Color(Color("14191e"), ink_alpha), 11)
		draw_line(Vector2(831, 162), Vector2(1040, 58), Color(Color("d8c7a3"), ink_alpha * 0.60), 2)

	if not _show_enemy(Vector2(866, 62) + enemy_offset, enemy_tint) and not enemy_lost:
		_actor(enemy_visual, Vector2(866, 62) + enemy_offset, defeated, enemy_tint)
