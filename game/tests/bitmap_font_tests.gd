extends SceneTree

const SOURCE = preload("res://assets/fonts/Galmuri11-Bold.ttf")
const BITMAP = preload("res://assets/fonts/Galmuri11-ui-bitmap.res")
const SIZES := [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 25, 32, 56]
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	check(BITMAP.data.is_empty(), "UI font contains no dynamic outline data")
	for n in SIZES:
		var size := Vector2i(n, 0)
		check(size in BITMAP.get_size_cache_list(0) and BITMAP.get_texture_count(0, size) > 0, "bitmap atlas exists at %d px" % n)
		for line in ["Reaper's Bundle", "HP hit → Attack 2 · × 2", "Résumé — Story…"]:
			var a: Vector2 = SOURCE.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, n)
			var b: Vector2 = BITMAP.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, n)
			check(a.y == b.y and absf(a.x - b.x) <= maxf(5.0, a.x * 0.04), "bitmap preserves text metrics at %d px: %s" % [n, line])
	for cp in [0x0041, 0x007a, 0x00e9, 0x00b7, 0x00d7, 0x2026, 0x2014, 0x2192, 0x25cb]:
		check(BITMAP.has_char(cp), "bitmap contains UI glyph U+%04X" % cp)
	var atlas: Image = BITMAP.get_texture_image(0, Vector2i(14, 0), 0)
	check(atlas != null and not atlas.is_empty(), "bitmap atlas is embedded in the resource")
	print("BITMAP FONT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
