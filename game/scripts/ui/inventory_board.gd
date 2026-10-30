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
const THREAD_COLORS := {"add":Color("e6b85a"), "multiply":Color("65c6e7"), "condition":Color("d86f62")}
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
var drag_pointer := Vector2.ZERO
var drag_anchor := Vector2.ZERO
var placement_queue: ActionQueue
var placement_uid := ""
var placement_from := Vector2.ZERO
var placement_progress := 0.0
var placement_new_link := false
var used: Dictionary = {}
var presentation_busy := false
var display_state: Dictionary = {}
var hazards: Array = []
var frost_progress := 1.0
# Optional presentation-only telegraphs supplied by the displayed view.
var threat_cells: Array[Vector2i] = []
var target_cells: Array[Vector2i] = []
var target_preview := false
var _synergy_key: Dictionary = {}
var _synergy_cache: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(412, 324)
	placement_queue = ActionQueue.new()
	add_child(placement_queue)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func():
		hovered.emit("")
		if not dragging:
			hover_cell = Vector2i(-100, -100)
			synergy_changed.emit()
			queue_redraw()
	)

func begin_frost_feedback(event: Dictionary, before: Dictionary) -> bool:
	if event.get("kind", "") != "encounter_prepared": return false
	var after: Dictionary = event.get("after", {})
	var next := InventoryRules.active_hazards(after)
	if next.is_empty() or next == InventoryRules.active_hazards(before): return false
	frost_progress = 0.0
	queue_redraw()
	return true

func set_frost_progress(value: float) -> void:
	frost_progress = clampf((value - 0.5) * 2.0, 0.0, 1.0)
	queue_redraw()

func clear_frost_feedback() -> void:
	frost_progress = 1.0
	queue_redraw()

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
	if uid != selected or turn != pending_rotation: stop_placement_feedback()
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
	stop_placement_feedback()
	pressed_uid = uid
	press_point = viewport_position
	grab_offset = Vector2i.ZERO
	drag_anchor = Vector2.ONE * cell_size * 0.5
	drag_pointer = get_global_transform_with_canvas().affine_inverse() * viewport_position

func start_placement_feedback(uid: String, previous_origin: Vector2i, new_link: bool) -> void:
	stop_placement_feedback()
	if model == null or not model.is_packed(uid): return
	placement_uid = uid
	placement_from = drag_pointer - drag_anchor * 1.1 if dragging else (PAD + Vector2(previous_origin) * cell_size if previous_origin.x >= 0 else PAD + Vector2(model.items[uid].origin) * cell_size)
	placement_progress = 0.0
	placement_new_link = new_link
	var commands: Array[ActionCommand] = [LayoutFeedbackCommand.new(self)]
	if not placement_queue.start(commands): clear_placement_feedback()
	queue_redraw()

func set_placement_feedback_progress(value: float) -> void:
	placement_progress = clampf(value, 0.0, 1.0)
	queue_redraw()

func clear_placement_feedback() -> void:
	placement_uid = ""
	placement_progress = 0.0
	placement_new_link = false
	queue_redraw()

func stop_placement_feedback() -> void:
	if placement_queue != null: placement_queue.cancel()
	clear_placement_feedback()

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
						stop_placement_feedback()
						pressed_uid = uid
						press_point = get_global_transform_with_canvas() * event.position
						grab_offset = cell - Vector2i(model.items[uid].origin)
						drag_anchor = event.position - PAD - Vector2(model.items[uid].origin) * cell_size
						drag_pointer = event.position
			elif not selected.is_empty() and not model.locked:
				placement_requested.emit(selected, cell, pending_rotation)
			accept_event()

func _input(event: InputEvent) -> void:
	if model == null or model.locked:
		return
	if event is InputEventMouseMotion and not pressed_uid.is_empty():
		drag_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.position.distance_to(press_point) > 6:
			dragging = true
		if dragging:
			hover_cell = cell_at(drag_pointer)
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

func _draw_links(view: Dictionary) -> void:
	var groups: Dictionary = {}
	var highlighted: Dictionary = {}
	for link: Dictionary in view.links:
		highlighted[link.source] = true
		highlighted[link.target] = true
		var key := JSON.stringify([link.source, link.target, link.range, link.kind])
		if not groups.has(key): groups[key] = {"source":link.source, "target":link.target, "range":link.range, "kind":link.kind}
	var pulse := sin(placement_progress * PI) if placement_new_link and not placement_uid.is_empty() and view.mode == "current" else 0.0
	var outline := Color("82d8cb") if view.mode == "preview" else Color("f4d57d").lerp(Color("fff6cf"), pulse * 0.65)
	var outline_width := 2.0 + pulse * 2.0
	for uid: String in highlighted:
		var cells: Array = view.items[uid].cells
		for point: Vector2i in cells:
			var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
			var start := rect.position + Vector2(5,5)
			var end := rect.end - Vector2(5,5)
			if not cells.has(point + Vector2i.LEFT): draw_line(start, Vector2(start.x,end.y), outline, outline_width)
			if not cells.has(point + Vector2i.RIGHT): draw_line(Vector2(end.x,start.y), end, outline, outline_width)
			if not cells.has(point + Vector2i.UP): draw_line(start, Vector2(end.x,start.y), outline, outline_width)
			if not cells.has(point + Vector2i.DOWN): draw_line(Vector2(start.x,end.y), end, outline, outline_width)
	for group: Dictionary in groups.values():
		var color: Color = THREAD_COLORS[group.kind]
		if view.mode == "preview": color = color.lerp(Color("e4eee2"), 0.25)
		if group.source == group.target:
			var cells: Array = view.items[group.source].cells
			if cells.is_empty(): continue
			var knot_offset: float = {"add":0.0, "multiply":10.0, "condition":20.0}[group.kind]
			var knot := PAD + Vector2(cells[0]) * cell_size + Vector2(8 + knot_offset, cell_size - 10)
			draw_circle(knot, 5, Color("27201f"))
			draw_circle(knot, 3, color)
			continue
		var points := _closest_cells(view.items[group.source].cells, view.items[group.target].cells, group.range)
		if points.size() != 2: continue
		var a := PAD + (Vector2(points[0]) + Vector2(0.5, 0.5)) * cell_size
		var b := PAD + (Vector2(points[1]) + Vector2(0.5, 0.5)) * cell_size
		var direction := (b - a).normalized()
		var start := a + direction * cell_size * 0.35
		var finish := b - direction * cell_size * 0.35
		var normal := Vector2(-direction.y, direction.x)
		var curve := PackedVector2Array()
		var bend := -5.0 if hash(str(group.source) + str(group.target)) % 2 == 0 else 5.0
		var offset: float = {"add":-5.0, "multiply":5.0, "condition":0.0}[group.kind]
		for step in 9:
			var t := float(step) / 8.0
			curve.append(start.lerp(finish, t) + normal * (sin(t * PI) * bend + offset))
		draw_polyline(curve, Color("28201d"), 7)
		draw_polyline(curve, color, 3)
		# A small trailing thread and a larger knot indicate source and target.
		draw_circle(curve[0], 2, color.darkened(0.25))
		draw_circle(curve[curve.size() - 1], 4, Color("28201d"))
		draw_circle(curve[curve.size() - 1], 2, color)

func _draw() -> void:
	if model == null:
		return
	var font := get_theme_default_font()
	for y in model.dimensions.y:
		for x in model.dimensions.x:
			var rect := Rect2(PAD + Vector2(x, y) * cell_size, Vector2.ONE * cell_size)
			var frost := false
			for hazard: Dictionary in hazards:
				if Vector2i(x, y) in hazard.cells: frost = true
			draw_rect(rect.grow(-2), Color("aebeb5") if frost else Color("c4b198"))
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
		if uid != placement_uid:
			ItemIcons.draw_icon(self, item, origin, cell_size / 24.0, int(model.items[uid].rotation), exhausted or (dragging and uid == selected))
		if EffectApplier.has_trigger(ItemCodec.item(item, []), "use") and not exhausted:
			var value: Dictionary = display_state.get("packed_items", {}).get(uid, ItemCodec.item(item, points))
			var cost := InventoryRules.action_cost(display_state, value) if not display_state.is_empty() else {"total":item.cost, "extra":0}
			var width := maxf(16, font.get_string_size(str(cost.total), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6)
			var anchor := origin + Vector2(cell_size - width - 4, 4)
			draw_rect(Rect2(anchor, Vector2(width, 18)), Color("313930"))
			draw_string(font, anchor + Vector2(0, 16), str(cost.total), HORIZONTAL_ALIGNMENT_CENTER, width, 16, Color("a8eaf4") if cost.extra > 0 else Color("eed99b"))
		if exhausted:
			draw_string(font, origin + Vector2(7, cell_size - 8), "Use", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("b6bdb4"))
	for point: Vector2i in threat_cells:
		if point.x < 0 or point.y < 0 or point.x >= model.dimensions.x or point.y >= model.dimensions.y: continue
		var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
		draw_line(rect.position + Vector2(6, cell_size - 6), rect.end - Vector2(6, 6), Color("df9073"), 2)
	for hazard: Dictionary in hazards:
		for point: Vector2i in hazard.cells:
			var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
			var edge := rect.grow(-4)
			var length := edge.size.x * frost_progress
			var ice := Color("9de1ee")
			draw_line(edge.position, edge.position + Vector2(length, 0), ice, 2)
			draw_line(edge.end, edge.end - Vector2(length, 0), ice, 2)
			draw_line(edge.position, edge.position + Vector2(0, edge.size.y * frost_progress), ice, 2)
			draw_line(edge.end, edge.end - Vector2(0, edge.size.y * frost_progress), ice, 2)
			for i in 4:
				var x := edge.position.x + 7.0 + i * 16.0
				if x > edge.position.x + length: continue
				var tip := Vector2(x, edge.position.y)
				draw_line(tip, tip + Vector2(3, 8 * frost_progress), Color("ddfaff"), 2)
				draw_line(tip + Vector2(2, 5 * frost_progress), tip + Vector2(7, 6 * frost_progress), ice, 1)
			var center := rect.position + Vector2(11, 12)
			draw_line(center + Vector2(-5,0) * frost_progress, center + Vector2(5,0) * frost_progress, Color("ddfaff"), 2)
			draw_line(center + Vector2(0,-5) * frost_progress, center + Vector2(0,5) * frost_progress, Color("ddfaff"), 2)
	var synergy := synergy_view()
	if synergy.mode in ["current", "preview"]: _draw_links(synergy)
	for point: Vector2i in target_cells:
		if point.x < 0 or point.y < 0 or point.x >= model.dimensions.x or point.y >= model.dimensions.y: continue
		var rect := Rect2(PAD + Vector2(point) * cell_size, Vector2.ONE * cell_size)
		var start := rect.position + Vector2(6, 6)
		var end := rect.end - Vector2(6, 6)
		var color := Color("f4b15b") if target_preview else Color("fa7d64")
		if not target_cells.has(point + Vector2i.LEFT): draw_line(start, Vector2(start.x, end.y), color, 3)
		if not target_cells.has(point + Vector2i.RIGHT): draw_line(Vector2(end.x, start.y), end, color, 3)
		if not target_cells.has(point + Vector2i.UP): draw_line(start, Vector2(end.x, start.y), color, 3)
		if not target_cells.has(point + Vector2i.DOWN): draw_line(Vector2(start.x, end.y), end, color, 3)
		if font != null and point == target_cells[0]:
			var badge := start + Vector2(2, 2)
			draw_rect(Rect2(badge, Vector2(20, 20)), Color("392426"))
			draw_string(font, badge + Vector2(0, 16), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 16, color)
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
	if dragging and model.items.has(selected):
		_draw_lifted(selected, drag_pointer - drag_anchor * 1.1, pending_rotation, 1.1)
	elif not placement_uid.is_empty() and model.items.has(placement_uid) and model.is_packed(placement_uid):
		var destination := PAD + Vector2(model.items[placement_uid].origin) * cell_size
		var eased := 1.0 - pow(1.0 - placement_progress, 3.0)
		_draw_lifted(placement_uid, placement_from.lerp(destination, eased), int(model.items[placement_uid].rotation), lerpf(1.1, 1.0, eased))

func _draw_lifted(uid: String, origin: Vector2, rotation: int, scale_factor: float) -> void:
	var item := model.definition(uid)
	for cell: Vector2i in GridRules.cells(item.footprint, rotation):
		var rect := Rect2(origin + Vector2(cell) * cell_size * scale_factor + Vector2(4, 6), Vector2.ONE * cell_size * scale_factor)
		draw_rect(rect.grow(-5), Color(0.07, 0.07, 0.08, 0.28))
	ItemIcons.draw_icon(self, item, origin, cell_size / 24.0 * scale_factor, rotation)
