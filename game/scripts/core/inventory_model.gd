class_name InventoryModel
extends RefCounted
## Grid logic has no dependency on nodes, mouse coordinates, or rendering.

signal changed
const STASH := Vector2i(-1, -1)
var dimensions := Vector2i(5, 4)
var config: Dictionary = {}
var content_hash := ""
var legacy_content_hash := ""
var previous_content_hash := ""
var definitions: Dictionary = {}
var authored_items: Dictionary = {}
var items: Dictionary = {}
var history: Array[Dictionary] = []
var locked := false

func copy_for_transaction() -> InventoryModel:
	var copy := InventoryModel.new()
	copy.dimensions = dimensions
	copy.config = config
	copy.content_hash = content_hash
	copy.legacy_content_hash = legacy_content_hash
	copy.previous_content_hash = previous_content_hash
	copy.definitions = definitions
	copy.authored_items = authored_items
	copy.items = items.duplicate(true)
	copy.history = history.duplicate(true)
	copy.locked = locked
	return copy

func add_item(uid: String, definition: ItemData, origin := STASH, rotation := 0) -> bool:
	if locked or items.has(uid) or definition.footprint.is_empty():
		return false
	definitions[definition.id] = definition
	items[uid] = {"definition": str(definition.id), "origin": STASH, "rotation": posmod(rotation, 4)}
	if origin != STASH:
		if not placement_error(uid, origin, rotation).is_empty():
			items.erase(uid)
			return false
		items[uid].origin = origin
	changed.emit()
	return true

func definition(uid: String) -> ItemData:
	return definitions[items[uid].definition] as ItemData

func occupied_cells(uid: String, state: Variant = null) -> Array[Vector2i]:
	if state == null:
		state = items
	var result: Array[Vector2i] = []
	if not state.has(uid) or state[uid].origin == STASH:
		return result
	var data: Dictionary = state[uid]
	var item: ItemData = definitions[data.definition]
	for cell in GridRules.cells(item.footprint, data.rotation):
		result.append(data.origin + cell)
	return result

func item_at(cell: Vector2i) -> String:
	for uid: String in items:
		if occupied_cells(uid).has(cell):
			return uid
	return ""

func is_packed(uid: String) -> bool:
	return items.has(uid) and items[uid].origin != STASH

func placement_error(uid: String, origin: Vector2i, rotation: int) -> String:
	if not items.has(uid):
		return "물건을 먼저 선택하세요."
	if locked:
		return "전투 중에는 보따리를 정리할 수 없습니다."
	var active_units := definition(uid).effects.size()
	var active_items := 1
	for other: String in items:
		if other != uid and is_packed(other):
			active_units += definition(other).effects.size()
			active_items += 1
	if active_units > EffectApplier.MAX_ACTIVE_UNITS or active_items > EffectApplier.MAX_ACTIVE_ITEMS:
		return "동시에 장착할 수 있는 효과 수를 초과합니다."
	for cell in GridRules.cells(definition(uid).footprint, rotation):
		var target := origin + cell
		if target.x < 0 or target.y < 0 or target.x >= dimensions.x or target.y >= dimensions.y:
			return "보따리 밖으로 벗어납니다."
		var other := item_at(target)
		if not other.is_empty() and other != uid:
			return "다른 물건과 겹칩니다."
	return ""

func place(uid: String, origin: Vector2i, rotation: int) -> bool:
	if not placement_error(uid, origin, rotation).is_empty():
		return false
	if items[uid].origin == origin and items[uid].rotation == posmod(rotation, 4):
		return true
	_remember()
	items[uid].origin = origin
	items[uid].rotation = posmod(rotation, 4)
	changed.emit()
	return true

func move_to_stash(uid: String) -> bool:
	if locked or not is_packed(uid):
		return false
	_remember()
	items[uid].origin = STASH
	changed.emit()
	return true

func undo() -> bool:
	if locked or history.is_empty():
		return false
	items = history.pop_back()
	changed.emit()
	return true

func _remember() -> void:
	history.append(items.duplicate(true))
	if history.size() > 30:
		history.pop_front()

func adjacent(first: String, second: String, state: Variant = null) -> bool:
	if state == null:
		state = items
	if first == second:
		return false
	for a in occupied_cells(first, state):
		for b in occupied_cells(second, state):
			if absi(a.x - b.x) + absi(a.y - b.y) == 1:
				return true
	return false

func combat_snapshot(state: Variant = null) -> Dictionary:
	if state == null:
		state = items
	var snapshot: Dictionary = {}
	for uid: String in state:
		if state[uid].origin == STASH:
			continue
		var item: ItemData = definitions[state[uid].definition]
		snapshot[uid] = ItemCodec.item(item, occupied_cells(uid, state))
	return snapshot

func action_result(uid: String, state: Variant = null) -> Dictionary:
	return InventoryRules.action_result(combat_snapshot(state), uid)

func passive_guard(state: Variant = null) -> int:
	return InventoryRules.passive_guard(combat_snapshot(state))

func preview(uid: String, origin: Vector2i, rotation: int) -> Dictionary:
	var state := items.duplicate(true)
	state[uid].origin = origin
	state[uid].rotation = rotation
	var attacks: Dictionary = {}
	for other: String in state:
		var amount := 0
		for plan: Dictionary in action_result(other, state).effects:
			if plan.kind == "damage" and plan.target == "enemy": amount += int(plan.amount)
		if amount > 0: attacks[other] = amount
	return {"action": action_result(uid, state), "guard": passive_guard(state), "attacks": attacks, "snapshot": combat_snapshot(state)}

func used_cells() -> int:
	var count := 0
	for uid: String in items:
		count += occupied_cells(uid).size()
	return count
