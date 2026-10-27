class_name RoadView
extends Control
## Receives actor art through the displayed content snapshot.

var player_visual: Dictionary = {}
var enemy_visual: Dictionary = {}
var defeated := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _actor(visual: Dictionary, origin: Vector2, faded := false) -> void:
	draw_set_transform(origin, 0, Vector2.ONE * 4)
	for part: Array in visual.get("parts", []):
		var color := Color(part[4])
		draw_rect(Rect2(part[0], part[1], part[2], part[3]), color.darkened(0.55) if faded else color)
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	draw_rect(Rect2(171, 185, 136, 8), Color("1b2929"))
	draw_rect(Rect2(866, 185, 136, 8), Color("1b2929"))
	_actor(player_visual, Vector2(176, 58))
	_actor(enemy_visual, Vector2(866, 62), defeated)
