extends SceneTree
## Four original 16x16 pixel clusters in a transparent 64x64 shared atlas.
func _initialize() -> void:
	var atlas := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	# Ink shard — dark outside with a muted blue-gray interior.
	for block in [[4,3,6,10,"111b22"],[2,6,10,5,"111b22"],[6,2,3,12,"111b22"],[5,5,4,6,"627783"],[4,7,7,2,"627783"],[6,4,2,2,"b5c8c4"]]:
		atlas.fill_rect(Rect2i(block[0], block[1], block[2], block[3]), Color(block[4]))
	# Ice crystal.
	for block in [[22,2,3,12,"6d9eab"],[18,6,11,3,"6d9eab"],[20,4,7,7,"6d9eab"],[23,3,1,10,"e2f6ed"],[19,7,9,1,"e2f6ed"],[21,5,5,5,"b5d8d3"]]:
		atlas.fill_rect(Rect2i(block[0], block[1], block[2], block[3]), Color(block[4]))
	# Goblin-fire spark.
	for block in [[38,2,3,12,"514434"],[35,5,9,7,"514434"],[38,3,3,9,"e19846"],[36,7,7,3,"e19846"],[39,5,2,5,"ffe0a0"]]:
		atlas.fill_rect(Rect2i(block[0], block[1], block[2], block[3]), Color(block[4]))
	# Brass coin fragment with a square hole.
	for block in [[52,3,8,10,"3b2b23"],[50,5,12,6,"3b2b23"],[53,4,6,8,"d4a558"],[51,6,10,4,"d4a558"],[55,6,2,3,"3b2b23"],[53,4,5,1,"f1d18c"]]:
		atlas.fill_rect(Rect2i(block[0], block[1], block[2], block[3]), Color(block[4]))
	var error := atlas.save_png("res://assets/visuals/vfx-particles-v1.png")
	if error != OK:
		push_error("VFX atlas save failed: " + str(error))
		quit(1)
	else:
		print("VFX ATLAS: PASS")
		quit(0)
