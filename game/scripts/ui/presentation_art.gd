class_name PresentationArt
extends RefCounted
## Presentation-only atlas lookup; gameplay content remains independent of artwork.

const BACKGROUND: Texture2D = preload("res://assets/visuals/afterlife-retro-v1.png")
const ACTORS: Texture2D = preload("res://assets/visuals/actors-retro-v1.png")
const ITEMS: Texture2D = preload("res://assets/visuals/items-retro-v1.png")
const INDEX := "res://data/presentation/retro-art.json"
static var _entries: Dictionary = {}
static var _loaded := false

static func actor_region(id: String) -> Rect2:
	return _region("actors", id, ACTORS)

static func item_region(id: String) -> Rect2:
	return _region("items", id, ITEMS)

static func _region(group: String, id: String, texture: Texture2D) -> Rect2:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(INDEX):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
			if data is Dictionary: _entries = data
	var table: Variant = _entries.get(group, {})
	if not table is Dictionary: return Rect2()
	var coords: Variant = table.get(id, [])
	if not coords is Array or coords.size() != 4: return Rect2()
	for value in coords:
		if not value is int and not value is float: return Rect2()
	var rect := Rect2(float(coords[0]), float(coords[1]), float(coords[2]), float(coords[3]))
	if not rect.has_area() or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > texture.get_width() or rect.end.y > texture.get_height(): return Rect2()
	return rect
