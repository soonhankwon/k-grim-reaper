extends SceneTree
## Bake each logical 360p glyph at native size, then duplicate each pixel 2x.
## The existing 720-coordinate layout is scaled to 360p by BattleLayout.

const SOURCE := "res://assets/fonts/Galmuri11-Bold.ttf"
const OUTPUT := "res://assets/fonts/Galmuri11-ui-360.res"
const SIZES := [16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 48, 50, 56, 64, 112]
const SYMBOLS := [0x2192, 0x25cb]

func _initialize() -> void:
	var source: FontFile = load(SOURCE)
	var bitmap := FontFile.new()
	var chars: Array[int] = []
	for cp in range(32, 0x0250): chars.append(cp)
	for cp in range(0x2000, 0x2070): chars.append(cp)
	chars.append_array(SYMBOLS)
	for font_size in SIZES:
		var native_size: int = font_size / 2
		var cache_size := Vector2i(font_size, 0)
		var native_cache := Vector2i(native_size, 0)
		for cp in chars:
			var glyph := source.get_glyph_index(native_size, cp, 0)
			if glyph != 0: source.render_glyph(0, native_cache, glyph)
		bitmap.set_cache_ascent(0, font_size, source.get_cache_ascent(0, native_size) * 2)
		bitmap.set_cache_descent(0, font_size, source.get_cache_descent(0, native_size) * 2)
		bitmap.set_cache_underline_position(0, font_size, source.get_cache_underline_position(0, native_size) * 2)
		bitmap.set_cache_underline_thickness(0, font_size, source.get_cache_underline_thickness(0, native_size) * 2)
		for index in source.get_texture_count(0, native_cache):
			var image := source.get_texture_image(0, native_cache, index).duplicate() as Image
			image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
			bitmap.set_texture_image(0, cache_size, index, image)
			var offsets := source.get_texture_offsets(0, native_cache, index)
			for i in offsets.size(): offsets[i] *= 2
			bitmap.set_texture_offsets(0, cache_size, index, offsets)
		for cp in chars:
			var glyph := source.get_glyph_index(native_size, cp, 0)
			if glyph == 0: continue
			bitmap.set_glyph_advance(0, font_size, cp, source.get_glyph_advance(0, native_size, glyph) * 2)
			bitmap.set_glyph_offset(0, cache_size, cp, source.get_glyph_offset(0, native_cache, glyph) * 2)
			bitmap.set_glyph_size(0, cache_size, cp, source.get_glyph_size(0, native_cache, glyph) * 2)
			var uv := source.get_glyph_uv_rect(0, native_cache, glyph)
			bitmap.set_glyph_uv_rect(0, cache_size, cp, Rect2(uv.position * 2, uv.size * 2))
			bitmap.set_glyph_texture_idx(0, cache_size, cp, source.get_glyph_texture_idx(0, native_cache, glyph))
	var error := ResourceSaver.save(bitmap, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not write UI bitmap font: %s" % error)
		quit(1)
	else:
		print("BITMAP FONT: generated %d sizes" % SIZES.size())
		quit()
