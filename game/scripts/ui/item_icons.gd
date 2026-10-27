class_name ItemIcons
extends RefCounted
## Shared renderer. No item IDs or icon shapes occur in code.

static func extent(item: ItemData) -> Vector2:
	var bounds := Vector2.ONE
	for cell in item.footprint: bounds = bounds.max(Vector2(cell) + Vector2.ONE)
	return bounds * 24.0

static func draw_icon(canvas: CanvasItem, item: ItemData, origin: Vector2, pixel_scale: float, rotation := 0, faded := false) -> void:
	if item.icon.is_empty(): return
	var bounds := extent(item)
	var turn := posmod(rotation, 4)
	var offset: Vector2 = [Vector2.ZERO, Vector2(bounds.y, 0), bounds, Vector2(0, bounds.x)][turn]
	canvas.draw_set_transform(origin + offset * pixel_scale, turn * PI / 2, Vector2.ONE * pixel_scale)
	var sprite := PresentationArt.item_region(str(item.icon.get("presentation_id", "")))
	if sprite.has_area():
		var sprite_fit := minf(bounds.x / sprite.size.x, bounds.y / sprite.size.y) * 0.9
		var sprite_size := sprite.size * sprite_fit
		canvas.draw_texture_rect_region(PresentationArt.ITEMS, Rect2((bounds - sprite_size) / 2, sprite_size), sprite, Color(0.45, 0.45, 0.45) if faded else Color.WHITE)
		canvas.draw_set_transform(Vector2.ZERO)
		return
	var native := Vector2(item.icon["size"][0], item.icon["size"][1])
	var fit := minf(bounds.x / native.x, bounds.y / native.y)
	var padding := (bounds - native * fit) / 2
	for part: Array in item.icon.parts:
		var color := Color(item.icon.palette[int(part[4])])
		canvas.draw_rect(Rect2(Vector2(part[0], part[1]) * fit + padding, Vector2(part[2], part[3]) * fit), color.darkened(0.55) if faded else color)
	canvas.draw_set_transform(Vector2.ZERO)
