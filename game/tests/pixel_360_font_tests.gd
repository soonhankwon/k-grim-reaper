extends SceneTree

const FONT = preload("res://assets/fonts/Galmuri11-ui-360.res")
const SIZES := [16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 48, 50, 56, 64, 112]
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	check(FONT.data.is_empty(), "360p font is a bitmap font")
	for size in SIZES:
		var cache_size := Vector2i(size, 0)
		check(cache_size in FONT.get_size_cache_list(0), "native-pixel cache exists at %d" % size)
		for cp in [65, 0x00b7, 0x00d7, 0x2026, 0x2192]:
			var texture_id := FONT.get_glyph_texture_idx(0, cache_size, cp)
			var uv := Rect2i(FONT.get_glyph_uv_rect(0, cache_size, cp))
			if texture_id < 0 or not uv.has_area():
				check(false, "glyph %d exists at %d" % [cp, size])
				continue
			var image := FONT.get_texture_image(0, cache_size, texture_id)
			var correct := uv.position.x % 2 == 0 and uv.position.y % 2 == 0 and uv.size.x % 2 == 0 and uv.size.y % 2 == 0
			for y in range(uv.position.y, uv.end.y, 2):
				for x in range(uv.position.x, uv.end.x, 2):
					var pixel := image.get_pixel(x, y)
					if pixel != image.get_pixel(x + 1, y) or pixel != image.get_pixel(x, y + 1) or pixel != image.get_pixel(x + 1, y + 1): correct = false
			check(correct, "glyph %d resolves to exact 360p pixels at %d" % [cp, size])
	print("PIXEL 360 FONT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
