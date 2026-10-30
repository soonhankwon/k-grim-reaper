extends SceneTree
## Produce an editable 32px-per-cell atlas from the existing presentation art.
## No item rules or authored content are changed.

const SOURCE := "res://assets/visuals/items-minhwa-v2.png"
const OUTPUT := "res://assets/visuals/items-360-v1.png"
const INDEX := "res://data/presentation/pixel-items-360.json"
const BLOCK := 96
const CELL := 32

func _initialize() -> void:
	var original: Image = load(SOURCE).get_image()
	var model := ItemCatalog.create_inventory()
	var names: Array = model.definitions.keys()
	names.sort()
	var atlas := Image.create(BLOCK * 4, BLOCK * ceili(names.size() / 4.0), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var regions := {}
	for i in names.size():
		var item: ItemData = model.definitions[names[i]]
		var id := str(item.icon.get("presentation_id", ""))
		var source_rect := Rect2i(PresentationArt.source_item_region(id))
		if not source_rect.has_area():
			push_error("Missing source icon: " + id)
			quit(1)
			return
		var extent := Vector2i.ONE
		for cell: Vector2i in item.footprint: extent = extent.max(cell + Vector2i.ONE)
		var size := extent * CELL
		if size.x > BLOCK or size.y > BLOCK or regions.has(id):
			push_error("Unsupported icon dimensions or duplicate icon: " + id)
			quit(1)
			return
		var cell_pos := Vector2i(i % 4, i / 4) * BLOCK
		var pos := cell_pos + (Vector2i(BLOCK, BLOCK) - size) / 2
		var source := original.get_region(source_rect)
		var scale := minf(float(size.x - 4) / source.get_width(), float(size.y - 4) / source.get_height())
		var target := Vector2i(maxi(1, floori(source.get_width() * scale)), maxi(1, floori(source.get_height() * scale)))
		source.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(source, Rect2i(Vector2i.ZERO, target), pos + (size - target) / 2)
		regions[id] = [pos.x, pos.y, size.x, size.y]
	if atlas.save_png(OUTPUT) != OK:
		push_error("Could not save pixel item atlas")
		quit(1)
		return
	var file := FileAccess.open(INDEX, FileAccess.WRITE)
	if file == null:
		push_error("Could not save pixel item regions")
		quit(1)
		return
	file.store_string(JSON.stringify(regions, "\t") + "\n")
	print("PIXEL ITEMS: %d existing icons" % regions.size())
	quit()
