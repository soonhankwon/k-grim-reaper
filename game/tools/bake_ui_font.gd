extends SceneTree
## Rebuild the Latin UI bitmap font from the licensed Galmuri source.
## Run with Godot --headless --path game --script tools/bake_ui_font.gd.

const SOURCE := "res://assets/fonts/Galmuri11-Bold.ttf"
const OUTPUT := "res://assets/fonts/Galmuri11-ui-bitmap.res"
const SIZES := [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 25, 32, 56]
const SYMBOLS := [0x2192, 0x25cb]

func _initialize() -> void:
	var source: FontFile = load(SOURCE)
	var bitmap := FontFile.new()
	var chars: Array[int] = []
	for cp in range(32, 0x0250): chars.append(cp)
	for cp in range(0x2000, 0x2070): chars.append(cp)
	chars.append_array(SYMBOLS)
	for font_size in SIZES:
		var cache_size := Vector2i(font_size, 0)
		for cp in chars:
			var glyph := source.get_glyph_index(font_size, cp, 0)
			if glyph != 0: source.render_glyph(0, cache_size, glyph)
		bitmap.set_cache_ascent(0, font_size, source.get_cache_ascent(0, font_size))
		bitmap.set_cache_descent(0, font_size, source.get_cache_descent(0, font_size))
		bitmap.set_cache_underline_position(0, font_size, source.get_cache_underline_position(0, font_size))
		bitmap.set_cache_underline_thickness(0, font_size, source.get_cache_underline_thickness(0, font_size))
		for index in source.get_texture_count(0, cache_size):
			bitmap.set_texture_image(0, cache_size, index, source.get_texture_image(0, cache_size, index))
			bitmap.set_texture_offsets(0, cache_size, index, source.get_texture_offsets(0, cache_size, index))
		for cp in chars:
			var glyph := source.get_glyph_index(font_size, cp, 0)
			if glyph == 0: continue
			bitmap.set_glyph_advance(0, font_size, cp, source.get_glyph_advance(0, font_size, glyph))
			bitmap.set_glyph_offset(0, cache_size, cp, source.get_glyph_offset(0, cache_size, glyph))
			bitmap.set_glyph_size(0, cache_size, cp, source.get_glyph_size(0, cache_size, glyph))
			bitmap.set_glyph_uv_rect(0, cache_size, cp, source.get_glyph_uv_rect(0, cache_size, glyph))
			bitmap.set_glyph_texture_idx(0, cache_size, cp, source.get_glyph_texture_idx(0, cache_size, glyph))
	var error := ResourceSaver.save(bitmap, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not write UI bitmap font: %s" % error)
		quit(1)
	else:
		print("BITMAP FONT: generated %d sizes" % SIZES.size())
		quit()
