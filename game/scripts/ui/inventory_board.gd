class_name InventoryBoard
extends Control

signal picked(uid: String)
signal hovered(uid: String)
signal placement_requested(uid: String, origin: Vector2i, rotation: int)
signal cancelled
signal preview_changed(origin: Vector2i)

const CELL := 76.0
const PAD := Vector2(16, 10)
var cell_size: float:
	get: return CELL if model == null else minf(380.0 / model.dimensions.x, 304.0 / model.dimensions.y)
var model: InventoryModel
var selected := ""
var pending_rotation := 0
var hover_cell := Vector2i(-100, -100)
var pressed_uid := ""
var press_point := Vector2.ZERO
var grab_offset := Vector2i.ZERO
var dragging := false
var used: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(412, 324)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func():
		hovered.emit("")
		if not dragging:
			hover_cell = Vector2i(-100, -100)
			queue_redraw()
	)

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - PAD.x) / cell_size), floori((point.y - PAD.y) / cell_size))

func preview_origin() -> Vector2i:
	return hover_cell - grab_offset if dragging else hover_cell

func select(uid: String, turn: int) -> void:
	selected = uid
	pending_rotation = turn
	queue_redraw()

func cancel_motion() -> void:
	pressed_uid = ""
	dragging = false
	grab_offset = Vector2i.ZERO
	queue_redraw()

func begin_external_drag(uid: String, viewport_position: Vector2) -> void:
	if model == null or model.locked: return
	pressed_uid = uid
	press_point = viewport_position
	grab_offset = Vector2i.ZERO

func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseMotion:
		hover_cell = cell_at(event.position)
		hovered.emit(model.item_at(hover_cell))
		preview_changed.emit(preview_origin())
		queue_redraw()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancelled.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(event.position)
			var uid := model.item_at(cell)
			if not uid.is_empty():
				if uid == selected and not model.locked and pending_rotation != int(model.items[uid].rotation):
					placement_requested.emit(uid, model.items[uid].origin, pending_rotation)
				else:
					picked.emit(uid)
					if not model.locked:
						pressed_uid = uid
						press_point = get_global_transform_with_canvas() * event.position
						grab_offset = cell - Vector2i(model.items[uid].origin)
			elif not selected.is_empty() and not model.locked:
				placement_requested.emit(selected, cell, pending_rotation)
			accept_event()

func _input(event: InputEvent) -> void:
	if model == null or model.locked:
		return
	if event is InputEventMouseMotion and not pressed_uid.is_empty():
		if event.position.distance_to(press_point) > 6:
			dragging = true
		if dragging:
			hover_cell = cell_at(get_global_transform_with_canvas().affine_inverse() * event.position)
			preview_changed.emit(preview_origin())
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging:
			var destination := cell_at(get_global_transform_with_canvas().affine_inverse() * event.position) - grab_offset
			placement_requested.emit(selected, destination, pending_rotation)
			get_viewport().set_input_as_handled()
		cancel_motion()

func _draw() -> void:
	if model == null:
		return
	var font := get_theme_default_font()
	for y in model.dimensions.y:
		for x in model.dimensions.x:
			var rect := Rect2(PAD + Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect.grow(-2), Color("a08b6b"))
			draw_rect(rect.grow(-2), Color("564a3e"), false, 1)
	for uid: String in model.items:
		if not model.is_packed(uid):
			continue
		var item := model.definition(uid)
		var exhausted := int(used.get(uid, 0)) >= item.uses_per_turn
		var points := model.occupied_cells(uid)
		var fill := Color("857252")
		var edge := Color("bca67b")
		if uid == selected:
			fill = Color("9b8056")
			edge = Color("f0ddb0")
		if exhausted:
			fill = fill.darkened(0.4)
			edge = edge.darkened(0.5)
		for point in points:
			var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect.grow(-3), fill)
			# Only the outer silhouette is accented; the cell lattice stays readable.
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if not points.has(point + direction):
					var from := rect.position + Vector2(3, 3)
					var to := rect.end - Vector2(3, 3)
					if direction == Vector2i.LEFT:
						draw_line(from, Vector2(from.x, to.y), edge, 2)
					elif direction == Vector2i.RIGHT:
						draw_line(Vector2(to.x, from.y), to, edge, 2)
					elif direction == Vector2i.UP:
						draw_line(from, Vector2(to.x, from.y), edge, 2)
					else:
						draw_line(Vector2(from.x, to.y), to, edge, 2)
		var origin := PAD + Vector2(model.items[uid].origin) * cell_size
		ItemIcons.draw_icon(self, item, origin, cell_size / 24.0, int(model.items[uid].rotation), exhausted)
		if EffectApplier.has_trigger(ItemCodec.item(item, []), "use") and not exhausted:
			draw_rect(Rect2(origin + Vector2(cell_size - 20, 4), Vector2(16, 18)), Color("313930"))
			draw_string(font, origin + Vector2(cell_size - 17, 18), str(item.cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("eed99b"))
		if exhausted:
			draw_string(font, origin + Vector2(7, cell_size - 8), "사용", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("b6bdb4"))
	if not selected.is_empty() and model.items.has(selected) and not model.locked and hover_cell.x > -50:
		var origin := preview_origin()
		var valid := model.placement_error(selected, origin, pending_rotation).is_empty()
		var tint := Color("8ce3c2") if valid else Color("ee886d")
		for point in GridRules.cells(model.definition(selected).footprint, pending_rotation):
			var target := point + origin
			if target.x >= 0 and target.y >= 0 and target.x < model.dimensions.x and target.y < model.dimensions.y:
				var rect := Rect2(PAD + Vector2(target) * cell_size, Vector2.ONE * cell_size)
				draw_rect(rect.grow(-4), Color(tint, 0.19))
				draw_rect(rect.grow(-4), tint, false, 2)
