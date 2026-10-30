class_name PresentationArt
extends RefCounted
## Presentation-only atlas lookup; gameplay content remains independent of artwork.

const BACKGROUND: Texture2D = preload("res://assets/visuals/afterlife-ink-v2.png")
const ACTORS: Texture2D = preload("res://assets/visuals/actors-woodcut-v2.png")
const PIXEL_ACTORS: Texture2D = preload("res://assets/visuals/actors-360-v1.png")
const SOURCE_ITEMS: Texture2D = preload("res://assets/visuals/items-minhwa-v2.png")
const ITEMS: Texture2D = preload("res://assets/visuals/items-360-v1.png")
const INDEX := "res://data/presentation/retro-art.json"
const PIXEL_ITEMS_INDEX := "res://data/presentation/pixel-items-360.json"
const PIXEL_ACTORS_INDEX := "res://data/presentation/pixel-actors-360.json"
static var _entries: Dictionary = {}
static var _loaded := false
static var _textures: Dictionary = {}
static var _pixel_items: Dictionary = {}
static var _pixel_actors: Dictionary = {}

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	if FileAccess.file_exists(INDEX):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if data is Dictionary: _entries = data
	if FileAccess.file_exists(PIXEL_ITEMS_INDEX):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIXEL_ITEMS_INDEX))
		if data is Dictionary: _pixel_items = data
	if FileAccess.file_exists(PIXEL_ACTORS_INDEX):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PIXEL_ACTORS_INDEX))
		if data is Dictionary: _pixel_actors = data

static func _texture(path: String, fallback: Texture2D) -> Texture2D:
	if not path.begins_with("res://assets/visuals/") or ".." in path or not path.ends_with(".png") or not ResourceLoader.exists(path, "Texture2D"): return fallback
	if not _textures.has(path): _textures[path] = load(path) as Texture2D
	return _textures[path] if _textures[path] != null else fallback

# Optional standalone sprites and scene backdrops come from visual data.
static func visual_texture(path: String) -> Texture2D:
	return _texture(path, null)

static func background_for_visual(visual: Dictionary) -> Texture2D:
	var custom := visual_texture(str(visual.get("background_path", "")))
	return custom if custom != null else background_for_actor(str(visual.get("presentation_id", "")))

static func actor_texture(id: String) -> Texture2D:
	_ensure_loaded()
	return PIXEL_ACTORS if _pixel_actors.has(id) else source_actor_texture(id)

static func source_actor_texture(id: String) -> Texture2D:
	_ensure_loaded()
	var overrides: Variant = _entries.get("actor_overrides", {})
	if not overrides is Dictionary or not overrides.get(id) is Dictionary: return ACTORS
	return _texture(str(overrides[id].get("texture", "")), ACTORS)

static func background_for_actor(id: String) -> Texture2D:
	_ensure_loaded()
	var backgrounds: Variant = _entries.get("backgrounds", {})
	if not backgrounds is Dictionary: return BACKGROUND
	return _texture(str(backgrounds.get(id, "")), BACKGROUND)

static func actor_region(id: String) -> Rect2:
	_ensure_loaded()
	return _rect(_pixel_actors[id], PIXEL_ACTORS) if _pixel_actors.has(id) else source_actor_region(id)

static func source_actor_region(id: String) -> Rect2:
	_ensure_loaded()
	var overrides: Variant = _entries.get("actor_overrides", {})
	if overrides is Dictionary and overrides.get(id) is Dictionary:
		return _rect(overrides[id].get("region", []), source_actor_texture(id))
	return _region("actors", id, ACTORS)

static func item_region(id: String) -> Rect2:
	_ensure_loaded()
	return _rect(_pixel_items.get(id, []), ITEMS)

static func source_item_region(id: String) -> Rect2:
	return _region("items", id, SOURCE_ITEMS)

static func _region(group: String, id: String, texture: Texture2D) -> Rect2:
	_ensure_loaded()
	var table: Variant = _entries.get(group, {})
	if not table is Dictionary: return Rect2()
	return _rect(table.get(id, []), texture)

static func _rect(coords: Variant, texture: Texture2D) -> Rect2:
	if not coords is Array or coords.size() != 4: return Rect2()
	for value in coords:
		if not value is int and not value is float: return Rect2()
	var rect := Rect2(float(coords[0]), float(coords[1]), float(coords[2]), float(coords[3]))
	if not rect.has_area() or rect.position.x < 0 or rect.position.y < 0 or rect.end.x > texture.get_width() or rect.end.y > texture.get_height(): return Rect2()
	return rect
