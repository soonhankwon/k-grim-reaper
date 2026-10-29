class_name InventoryBoard
extends Control

signal picked(uid: String)
signal hovered(uid: String)
signal placement_requested(uid: String, origin: Vector2i, rotation: int)
signal cancelled
signal preview_changed(origin: Vector2i)
signal synergy_changed

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
var presentation_busy := false
var _synergy_key: Dictionary = {}
var _synergy_cache: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(412, 324)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func():
		hovered.emit("")
		if not dragging:
			hover_cell = Vector2i(-100, -100)
			synergy_changed.emit()
			queue_redraw()
	)

func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - PAD.x) / cell_size), floori((point.y - PAD.y) / cell_size))

func preview_origin() -> Vector2i:
	if not dragging and model != null and model.is_packed(selected) and model.item_at(hover_cell) == selected:
		return model.items[selected].origin
	return hover_cell - grab_offset if dragging else hover_cell

func _preview_active() -> bool:
	if model == null or selected.is_empty() or not model.items.has(selected) or model.locked: return false
	if hover_cell.x < 0 or hover_cell.y < 0 or hover_cell.x >= model.dimensions.x or hover_cell.y >= model.dimensions.y: return false
	var hovered := model.item_at(hover_cell)
	return dragging or hovered.is_empty() or (hovered == selected and pending_rotation != int(model.items[selected].rotation))

func select(uid: String, turn: int) -> void:
	selected = uid
	pending_rotation = turn
	synergy_changed.emit()
	queue_redraw()

func cancel_motion() -> void:
	pressed_uid = ""
	dragging = false
	grab_offset = Vector2i.ZERO
	synergy_changed.emit()
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
		synergy_changed.emit()
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
			synergy_changed.emit()
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging:
			var destination := cell_at(get_global_transform_with_canvas().affine_inverse() * event.position) - grab_offset
			placement_requested.emit(selected, destination, pending_rotation)
			get_viewport().set_input_as_handled()
		cancel_motion()

func synergy_view() -> Dictionary:
	if model == null or selected.is_empty() or not model.items.has(selected): return {"mode":"empty", "links":[], "items":{}}
	if presentation_busy: return {"mode":"busy", "links":[], "items":{}}
	var state := model.items.duplicate(true)
	var mode := "current" if model.is_packed(selected) else "empty"
	if dragging and (hover_cell.x < 0 or hover_cell.y < 0 or hover_cell.x >= model.dimensions.x or hover_cell.y >= model.dimensions.y):
		return {"mode":"invalid", "links":[], "items":{}}
	if _preview_active():
		var origin := preview_origin()
		if not model.placement_error(selected, origin, pending_rotation).is_empty():
			return {"mode":"invalid", "links":[], "items":{}}
		if state[selected].origin != origin or state[selected].rotation != pending_rotation:
			state[selected].origin = origin
			state[selected].rotation = pending_rotation
			mode = "preview"
	if mode == "empty": return {"mode": mode, "links":[], "items":{}}
	var key := {"model":model.get_instance_id(), "state":state, "focus":selected, "mode":mode}
	if key == _synergy_key: return _synergy_cache
	var snapshot := model.combat_snapshot(state)
	var result := InventoryRules.synergy_links(snapshot, selected)
	_synergy_key = key
	_synergy_cache = {"mode":"error" if not result.error.is_empty() else mode, "error":result.error, "links":result.links, "items":snapshot}
	return _synergy_cache

func _closest_cells(first: Array, second: Array, range_mode: String) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var distance := 2147483647
	for a: Vector2i in first:
		for b: Vector2i in second:
			var delta := a - b
			if not GridRules.in_range({"cells":[a]}, {"cells":[b]}, range_mode): continue
			var next := delta.x * delta.x + delta.y * delta.y
			if next < distance:
				distance = next
				best = [a, b]
	return best

func _draw_links(view: Dictionary, font: Font) -> void:
	var groups: Dictionary = {}
	var highlighted: Dictionary = {}
	for link: Dictionary in view.links:
		highlighted[link.source] = true
		highlighted[link.target] = true
		var key := str(link.source) + "/" + str(link.target) + "/" + str(link.range)
		if not groups.has(key): groups[key] = {"source":link.source, "target":link.target, "range":link.range, "symbols":[]}
		var symbol: String = {"add":"+", "multiply":"×", "condition":"○"}[link.kind]
		if symbol not in groups[key].symbols: groups[key].symbols.append(symbol)
	var outline := Color("82d8cb") if view.mode == "preview" else Color("f4d57d")
	for uid: String in highlighted:
		var cells: Array = view.items[uid].cells
		for point: Vector2i in cells:
			var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
			var start := rect.position + Vector2(5,5)
			var end := rect.end - Vector2(5,5)
			if not cells.has(point + Vector2i.LEFT): draw_line(start, Vector2(start.x,end.y), outline, 2)
			if not cells.has(point + Vector2i.RIGHT): draw_line(Vector2(end.x,start.y), end, outline, 2)
			if not cells.has(point + Vector2i.UP): draw_line(start, Vector2(end.x,start.y), outline, 2)
			if not cells.has(point + Vector2i.DOWN): draw_line(Vector2(start.x,end.y), end, outline, 2)
	for group: Dictionary in groups.values():
		if group.source == group.target:
			var cells: Array = view.items[group.source].cells
			if cells.is_empty(): continue
			var anchor := PAD + Vector2(cells[0]) * cell_size + Vector2(4, cell_size - 22)
			var text := "".join(group.symbols)
			var width := maxf(20, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8)
			draw_rect(Rect2(anchor, Vector2(width, 18)), Color("202526"))
			draw_string(font, anchor + Vector2(0, 14), text, HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color("fff1c8"))
			continue
		var points := _closest_cells(view.items[group.source].cells, view.items[group.target].cells, group.range)
		if points.size() != 2: continue
		var a := PAD + (Vector2(points[0]) + Vector2(0.5, 0.5)) * cell_size
		var b := PAD + (Vector2(points[1]) + Vector2(0.5, 0.5)) * cell_size
		var direction := (b - a).normalized()
		var start := a + direction * cell_size * 0.35
		var finish := b - direction * cell_size * 0.35
		var color := Color("82d8cb") if view.mode == "preview" else Color("f4d57d")
		draw_line(start, finish, Color("202526"), 7)
		if view.mode == "preview":
			for step in range(0, 10, 2):
				draw_line(start.lerp(finish, float(step) / 10.0), start.lerp(finish, float(step + 1) / 10.0), color, 3)
		else: draw_line(start, finish, color, 3)
		var normal := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([finish, finish - direction * 8 + normal * 5, finish - direction * 8 - normal * 5]), color)
		var symbol_text := "".join(group.symbols)
		var middle := (start + finish) / 2
		var width := maxf(20, font.get_string_size(symbol_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8)
		draw_rect(Rect2(middle - Vector2(width / 2, 9), Vector2(width, 18)), Color("202526"))
		draw_string(font, middle + Vector2(-width / 2, 5), symbol_text, HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color("fff1c8"))

func _draw() -> void:
	if model == null:
		return
	var font := get_theme_default_font()
	for y in model.dimensions.y:
		for x in model.dimensions.x:
			var rect := Rect2(PAD + Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect.grow(-2), Color("c4b198"))
			draw_rect(rect.grow(-2), Color("675343"), false, 1)
	for uid: String in model.items:
		if not model.is_packed(uid):
			continue
		var item := model.definition(uid)
		var exhausted := int(used.get(uid, 0)) >= item.uses_per_turn
		var points := model.occupied_cells(uid)
		var fill := Color("af997d")
		var edge := Color("e0caa1")
		if uid == selected:
			fill = Color("bfaa87")
			edge = Color("fae6b4")
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
	var synergy := synergy_view()
	if synergy.mode in ["current", "preview"] and font != null: _draw_links(synergy, font)
	if _preview_active():
		var origin := preview_origin()
		var valid := model.placement_error(selected, origin, pending_rotation).is_empty()
		var tint := Color("8ce3c2") if valid else Color("ee886d")
		for point in GridRules.cells(model.definition(selected).footprint, pending_rotation):
			var target := point + origin
			if target.x >= 0 and target.y >= 0 and target.x < model.dimensions.x and target.y < model.dimensions.y:
				var rect := Rect2(PAD + Vector2(target) * cell_size, Vector2.ONE * cell_size)
				draw_rect(rect.grow(-4), Color(tint, 0.19))
				draw_rect(rect.grow(-4), tint, false, 2)
