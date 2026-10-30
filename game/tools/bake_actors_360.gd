extends SceneTree
## Match existing actor silhouettes to the 75x66 logical combat sprite area.

const OUTPUT := "res://assets/visuals/actors-360-v1.png"
const INDEX := "res://data/presentation/pixel-actors-360.json"
const REGION := Vector2i(75, 66)
const BLOCK := Vector2i(80, 72)

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PresentationArt.INDEX))
	var ids: Array = data.get("actors", {}).keys()
	ids.sort()
	var atlas := Image.create(BLOCK.x * 2, BLOCK.y * ceili(ids.size() / 2.0), false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var regions := {}
	for i in ids.size():
		var id: String = ids[i]
		var texture := PresentationArt.source_actor_texture(id)
		var rect := Rect2i(PresentationArt.source_actor_region(id))
		if texture == null or not rect.has_area():
			push_error("Missing actor source: " + id)
			quit(1)
			return
		var source := texture.get_image().get_region(rect)
		var scale := minf(float(REGION.x - 4) / source.get_width(), float(REGION.y - 4) / source.get_height())
		var target := Vector2i(maxi(1, floori(source.get_width() * scale)), maxi(1, floori(source.get_height() * scale)))
		source.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
		var pos := Vector2i(i % 2, i / 2) * BLOCK + (BLOCK - REGION) / 2
		atlas.blit_rect(source, Rect2i(Vector2i.ZERO, target), pos + Vector2i((REGION.x - target.x) / 2, REGION.y - target.y - 2))
		regions[id] = [pos.x, pos.y, REGION.x, REGION.y]
	if atlas.save_png(OUTPUT) != OK:
		push_error("Could not save pixel actor atlas")
		quit(1)
		return
	var file := FileAccess.open(INDEX, FileAccess.WRITE)
	if file == null:
		push_error("Could not save pixel actor regions")
		quit(1)
		return
	file.store_string(JSON.stringify(regions, "\t") + "\n")
	print("PIXEL ACTORS: %d existing characters" % regions.size())
	quit()
