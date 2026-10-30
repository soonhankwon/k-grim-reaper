class_name WoodcutSkin
extends RefCounted
## Pixel-drawn nine-patch frames, shared by every presentation panel.

static var _boxes: Dictionary = {}

static func box(kind: String) -> StyleBoxTexture:
	if _boxes.has(kind): return _boxes[kind]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var ink := Color("171b1c")
	var wood := Color("624536")
	var light := Color("a87d56")
	var fill := Color("252a29")
	match kind:
		"button": fill = Color("49392e")
		"hover": fill = Color("67503a"); light = Color("d1a66b")
		"pressed": fill = Color("362a24"); light = Color("896a4e")
		"disabled": fill = Color("252a29"); wood = Color("393833"); light = Color("595448")
		"primary": fill = Color("713e32"); wood = Color("69432f"); light = Color("c8995b")
		"primary_hover": fill = Color("98513a"); wood = Color("805236"); light = Color("e0b878")
		"primary_pressed": fill = Color("552c29"); light = Color("ad8052")
		"bag": fill = Color("926e56"); wood = Color("633d32"); light = Color("c49b6c")
	for y in range(32):
		for x in range(32):
			var edge := mini(mini(x, 31 - x), mini(y, 31 - y))
			var color := fill
			if edge < 2: color = ink
			elif edge < 7:
				color = wood
				# Uneven grain and stepped joinery remain stable when the center tiles.
				if edge == 2 or (edge == 5 and (x + y) % 8 < 5): color = light
				if edge == 6: color = ink
			elif kind == "bag" and (x * 3 + y * 5) % 37 == 0:
				color = fill.lightened(0.05)
			elif kind in ["button", "hover", "pressed", "primary", "primary_hover", "primary_pressed"]:
				if y % 7 == 0 and x % 6 < 3: color = fill.lightened(0.06)
			image.set_pixel(x, y, color)
	# Square brass pegs suggest the joinery of a traditional lattice frame.
	for corner in [Vector2i(4, 4), Vector2i(27, 4), Vector2i(4, 27), Vector2i(27, 27)]:
		image.set_pixelv(corner, light)
	var result := StyleBoxTexture.new()
	result.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, 8)
	result.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	result.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	if kind == "detail":
		result.content_margin_left = 16
		result.content_margin_right = 16
		result.content_margin_top = 14
		result.content_margin_bottom = 14
	elif kind == "preview":
		result.set_content_margin_all(10)
	elif kind in ["button", "hover", "pressed", "disabled", "primary", "primary_hover", "primary_pressed"]:
		result.content_margin_top = 4
		result.content_margin_bottom = 4
	_boxes[kind] = result
	return result
