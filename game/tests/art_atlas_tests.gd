extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var content := ContentLoader.new().load_json(ItemCatalog.DEFAULT_PATH)
	check(content.error.is_empty(), "shipping content loads for visual validation")
	if content.error.is_empty():
		var items := PresentationArt.ITEMS.get_image()
		var model := ItemCatalog.create_inventory()
		for row: Dictionary in content.raw.items:
			_validate_region(items, PresentationArt.item_region(row.icon_id), "item " + row.icon_id)
			var definition: ItemData = model.definitions[row.id]
			check(PresentationArt.item_region(row.icon_id).size == ItemIcons.extent(definition) / 24.0 * 32.0, "item footprint uses 32px cells: " + row.icon_id)
		var actor_ids: Dictionary = {content.raw.rules[0].player_visual:true}
		for row: Dictionary in content.raw.encounters: actor_ids[row.visual_id] = true
		for id: String in actor_ids:
			_validate_region(PresentationArt.actor_texture(id).get_image(), PresentationArt.actor_region(id), "actor " + id)
			check(PresentationArt.actor_region(id).size == Vector2(75, 66), "actor fits logical combat sprite area: " + id)
	print("ART ATLAS TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _validate_region(image: Image, region: Rect2, name: String) -> void:
	check(region.has_area(), name + " has a valid atlas region")
	if not region.has_area(): return
	var rect := Rect2i(region)
	var opaque := 0
	var cut := false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a < 0.25: continue
			opaque += 1
			if x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1: cut = true
	check(opaque > 50, name + " contains visible pixels")
	check(not cut, name + " retains transparent margins and does not crop the sprite")
