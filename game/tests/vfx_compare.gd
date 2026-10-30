extends SceneTree
func _initialize() -> void:
	for name in ["frost", "embers", "gilded"]:
		var a := Image.load_from_file(ProjectSettings.globalize_path("res://../build/vfx-" + name + ".png"))
		var b := Image.load_from_file(ProjectSettings.globalize_path("res://../build/vfx-" + name + "-without.png"))
		var count := 0
		for y in a.get_height():
			for x in a.get_width():
				if a.get_pixel(x, y) != b.get_pixel(x, y): count += 1
		print(name, " changed pixels: ", count)
	quit()
