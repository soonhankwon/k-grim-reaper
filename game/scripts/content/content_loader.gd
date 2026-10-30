class_name ContentLoader
extends RefCounted
## The only content IO boundary. CSV and JSON share validation and resource construction.

const SCHEMA_PATH := "res://data/content/schema.json"
const MAX_BYTES := 16 * 1024 * 1024
const MAX_ROWS := 10000
var error := ""
var _schema: Dictionary = {}

func load_json(path: String) -> Dictionary:
	error = ""
	var raw: Variant = _read_json(path)
	if not error.is_empty(): return {"error": error}
	return validate(raw)

func load_csv_directory(path: String) -> Dictionary:
	error = ""
	_schema = _read_schema()
	if not error.is_empty(): return {"error": error}
	var raw := {"schema_version": _schema.schema_version}
	for table: String in _schema.tables:
		raw[table] = _read_csv(path.path_join(table + ".csv"), _schema.tables[table])
		if not error.is_empty(): return {"error": error}
	raw.art = _read_json(path.path_join("art.json"))
	if not error.is_empty(): return {"error": error}
	return validate(raw)

func _read_schema() -> Dictionary:
	var value: Variant = _read_json(SCHEMA_PATH)
	if not value is Dictionary or not value.get("tables") is Dictionary or not value.has("schema_version"):
		if error.is_empty(): error = "schema.json: Invalid schema format"
		return {}
	return value

func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "%s: Cannot open file." % path
		return null
	if file.get_length() > MAX_BYTES:
		error = "%s: File exceeds the size limit." % path
		return null
	var parser := JSON.new()
	var code := parser.parse(file.get_as_text().trim_prefix("\ufeff"))
	if code != OK:
		error = "%s:%d: %s" % [path, parser.get_error_line() + 1, parser.get_error_message()]
		return null
	return parser.data

func _read_csv(path: String, fields: Dictionary) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		error = "%s: File missing or exceeds the size limit." % path
		return []
	# Skip a UTF-8 BOM before the CSV parser sees a quoted first field.
	if file.get_buffer(3) != PackedByteArray([239, 187, 191]): file.seek(0)
	var headers := file.get_csv_line()
	var seen: Dictionary = {}
	for column in headers:
		if seen.has(column) or (not fields.has(column) and not column.begins_with("_")):
			error = "%s: Duplicate or unknown column '%s'" % [path, column]
			return []
		seen[column] = true
	for field: String in fields:
		if not seen.has(field):
			error = "%s: Required column '%s' missing" % [path, field]
			return []
	var rows: Array = []
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() == 1 and values[0].strip_edges().is_empty(): continue
		if values.size() != headers.size():
			error = "%s: Record %d has the wrong number of columns" % [path, rows.size() + 2]
			return []
		var row: Dictionary = {}
		var populated := false
		for i in headers.size():
			if headers[i].begins_with("_"): continue
			row[headers[i]] = values[i]
			populated = populated or not values[i].strip_edges().is_empty()
		if not populated: continue
		rows.append(row)
		if rows.size() > MAX_ROWS:
			error = "%s: Too many rows" % path
			return []
	return rows

func validate(input: Variant) -> Dictionary:
	error = ""
	_schema = _read_schema()
	if not error.is_empty(): return {"error": error}
	if not input is Dictionary or input.get("schema_version") != _schema.schema_version:
		return {"error": "schema_version: Unsupported content format."}
	var raw: Dictionary = input.duplicate(true)
	for key: String in raw:
		if key not in ["schema_version", "art"] and not _schema.tables.has(key):
			return {"error": "Unknown content table: " + key}
	for table: String in _schema.tables:
		if table in ["resolutions", "hazards"] and not raw.has(table): continue
		if not raw.get(table) is Array or raw[table].size() > MAX_ROWS:
			return {"error": table + ": Array missing or too many rows."}
		var ids: Dictionary = {}
		for i in raw[table].size():
			var row: Variant = raw[table][i]
			var location := "%s[%d]" % [table, i + 2]
			if not row is Dictionary: return {"error": location + ": Invalid row format"}
			for key: String in row:
				if not _schema.tables[table].has(key): return {"error": location + ": Unknown column " + key}
			for field: String in _schema.tables[table]:
				if not row.has(field): return {"error": location + ": Missing required column " + field}
				row[field] = _value(row[field], _schema.tables[table][field], location + "." + field)
				if not error.is_empty(): return {"error": error}
			if ids.has(row.id): return {"error": location + ": Duplicate ID " + row.id}
			ids[row.id] = true
	if raw.get("resolutions", []).is_empty(): raw.erase("resolutions")
	if raw.get("hazards", []).is_empty(): raw.erase("hazards")
	var problem := _references(raw)
	if not problem.is_empty(): return {"error": problem}
	return {"error": "", "raw": raw}

func _value(value: Variant, spec: Dictionary, location: String) -> Variant:
	var valid := true
	match spec.type:
		"int":
			if value is String:
				var number := RegEx.create_from_string("^-?[0-9]+(?:\\.0+)?$")
				valid = number.search(value) != null
			elif value is not int and value is not float: valid = false
			if valid:
				var numeric := float(value)
				valid = is_finite(numeric) and numeric == floor(numeric) and numeric >= spec.min and numeric <= spec.max
				if valid: value = int(numeric)
		"bool":
			if value is String and value.to_lower() in ["true", "false"]: value = value.to_lower() == "true"
			valid = value is bool
		_:
			valid = value is String and value.length() <= 4096
			if valid:
				match spec.type:
					"id": valid = _id(value)
					"optional_id": valid = value.is_empty() or _id(value)
					"enum": valid = value in spec["values"]
					"list":
						var seen: Dictionary = {}
						for id in split_ids(value):
							valid = valid and _id(id) and not seen.has(id)
							seen[id] = true
					"cells": valid = not parse_cells(value).is_empty()
	if not valid: error = "%s: Invalid %s value: %s" % [location, spec.type, str(value)]
	return value

static func _id(value: String) -> bool:
	return value.length() <= 64 and RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(value) != null

static func split_ids(value: String) -> PackedStringArray:
	return PackedStringArray() if value.is_empty() else value.split("|", true)

static func parse_cells(value: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var minimum := Vector2i(999, 999)
	for pair in value.split("|", true):
		var numbers := pair.split(":", true)
		if numbers.size() != 2 or not numbers[0].is_valid_int() or not numbers[1].is_valid_int(): return []
		var cell := Vector2i(int(numbers[0]), int(numbers[1]))
		if cell.x < 0 or cell.y < 0 or cell.x >= 64 or cell.y >= 64 or result.has(cell): return []
		minimum = minimum.min(cell)
		result.append(cell)
	if minimum != Vector2i.ZERO or result.size() > 64: return []
	return result

static func parse_grid_cells(value: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pair in value.split("|", true):
		var numbers := pair.split(":", true)
		if numbers.size() != 2 or not numbers[0].is_valid_int() or not numbers[1].is_valid_int(): return []
		var cell := Vector2i(int(numbers[0]), int(numbers[1]))
		if cell.x < 0 or cell.y < 0 or cell.x >= 64 or cell.y >= 64 or result.has(cell): return []
		result.append(cell)
	return result if result.size() <= 64 else []

static func index(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in rows: result[row.id] = row
	return result

func _references(raw: Dictionary) -> String:
	if raw.rules.size() != 1 or raw.items.is_empty() or raw.encounters.is_empty(): return "Rules require one row; items and encounters require at least one row."
	var art_error := _validate_art(raw.get("art"))
	if not art_error.is_empty(): return art_error
	var units := index(raw.effects)
	var items := index(raw.items)
	var tags := index(raw.tags)
	for unit: Dictionary in raw.effects:
		for tag in split_ids(unit.required_tags) + split_ids(unit.condition_tags):
			if not tags.has(tag): return "effects.%s: Unknown tag %s" % [unit.id, tag]
		if (unit.trigger == "modify") != (unit.operation in ["modify_power", "multiply_power"]): return "effects.%s: A modify trigger and modifier operation are required." % unit.id
		if unit.trigger == "modify":
			if unit.target not in ["self", "adjacent_items", "diagonal_items", "neighbor_items"] or unit.affects.is_empty(): return "effects.%s: Invalid modifier target or affects field" % unit.id
			if unit.operation == "multiply_power" and (unit.scale != "flat" or unit.amount < 1): return "effects.%s: Multipliers require an integer of at least 1 and flat scaling." % unit.id
		else:
			if unit.target not in ["self", "opponent"] or not unit.affects.is_empty() or not unit.required_tags.is_empty() or not unit.stack_group.is_empty(): return "effects.%s: Modifier-only fields are present on an active effect." % unit.id
		if unit.scale == "flat" and not unit.condition_tags.is_empty(): return "effects.%s: condition_tags requires adjacency-based scaling." % unit.id
	for item: Dictionary in raw.items:
		if item.display_name.strip_edges().is_empty(): return "items.%s: Name is empty." % item.id
		if split_ids(item.effect_ids).size() > 32: return "items.%s: An item may have at most 32 effects." % item.id
		if not raw.art.icons.has(item.icon_id): return "items.%s: Unknown icon_id" % item.id
		for tag in split_ids(item.tags):
			if not tags.has(tag): return "items.%s: Unknown tag %s" % [item.id, tag]
		for id in split_ids(item.effect_ids):
			if not units.has(id): return "items.%s: Unknown effect %s" % [item.id, id]
	var orders: Dictionary = {}
	for encounter: Dictionary in raw.encounters:
		if orders.has(encounter.order): return "encounters: Duplicate order"
		orders[encounter.order] = true
		if not raw.art.actors.has(encounter.visual_id): return "encounters.%s: Unknown visual_id" % encounter.id
		if encounter.name.strip_edges().is_empty() or encounter.intent_ids.is_empty(): return "encounters.%s: Name or intent missing" % encounter.id
		for column in ["intent_ids", "reaction_ids"]:
			for id in split_ids(encounter[column]):
				if not units.has(id): return "encounters.%s: Unknown effect %s" % [encounter.id, id]
				var unit: Dictionary = units[id]
				var trigger := "use" if column == "intent_ids" else "damage_taken"
				if unit.trigger != trigger or unit.scale != "flat": return "encounters.%s: Intents and reactions require flat effects with the matching trigger." % encounter.id
	var rule: Dictionary = raw.rules[0]
	var encounter_ids := index(raw.encounters)
	var rewarded: Dictionary = {}
	var last_order := -1
	for row: Dictionary in raw.encounters: last_order = maxi(last_order, row.order)
	for reward: Dictionary in raw.rewards:
		if not encounter_ids.has(reward.encounter_id) or rewarded.has(reward.encounter_id): return "rewards.%s: Unknown encounter or duplicate reward" % reward.id
		if encounter_ids[reward.encounter_id].order == last_order: return "rewards.%s: The final encounter cannot have a reward." % reward.id
		var candidates := split_ids(reward.item_ids)
		if candidates.is_empty() or candidates.size() > 3: return "rewards.%s: Rewards require 1–3 choices." % reward.id
		for id in candidates:
			if not items.has(id): return "rewards.%s: Unknown item %s" % [reward.id, id]
			var fits := false
			for rotation in 4:
				var bounds := Vector2i.ZERO
				for cell in GridRules.cells(parse_cells(items[id].footprint), rotation): bounds = bounds.max(cell + Vector2i.ONE)
				fits = fits or (bounds.x <= rule.grid_width and bounds.y <= rule.grid_height)
			if not fits: return "rewards.%s: Choice %s cannot fit in an empty bag" % [reward.id, id]
		rewarded[reward.encounter_id] = true
	if not raw.routes.is_empty():
		if raw.routes.size() < 2 or raw.routes.size() > 3 or raw.encounters.size() < 2 or raw.encounters.size() > 64: return "routes: Requires 2–3 routes and 2–64 encounters."
		var sorted_encounters: Array = raw.encounters.duplicate(true)
		sorted_encounters.sort_custom(func(a, b): return a.order < b.order)
		var first_id: String = sorted_encounters[0].id
		var first_reward := ""
		var sequences: Dictionary = {}
		var reward_ids := index(raw.rewards)
		for route: Dictionary in raw.routes:
			var encounters := split_ids(route.encounter_ids)
			var rewards := split_ids(route.reward_ids)
			if route.name.strip_edges().is_empty() or encounters.size() != raw.encounters.size() or encounters[0] != first_id: return "routes.%s: Invalid name or shared starting encounter" % route.id
			if rewards.size() != encounters.size() - 1: return "routes.%s: Each encounter except the last requires one reward." % route.id
			for id in encounters:
				if not encounter_ids.has(id): return "routes.%s: Unknown encounter %s" % [route.id, id]
			for id in rewards:
				if not reward_ids.has(id): return "routes.%s: Unknown reward %s" % [route.id, id]
			if first_reward.is_empty(): first_reward = rewards[0]
			elif first_reward != rewards[0]: return "routes: The first reward must be shared before route selection."
			if sequences.has(route.encounter_ids): return "routes: Duplicate encounter order."
			sequences[route.encounter_ids] = true
	if raw.events.size() > 1: return "events: At most one event is supported per run."
	var resolutions: Array = raw.get("resolutions", [])
	if resolutions.size() > 1: return "resolutions: At most one ending branch is supported per run."
	for resolution: Dictionary in resolutions:
		if raw.events.size() != 1 or resolution.event_id != raw.events[0].id: return "resolutions.%s: Invalid event reference." % resolution.id
		for field in ["message", "result", "button", "unavailable", "completion_title"]:
			if resolution[field].strip_edges().is_empty() or resolution[field].length() > 240: return "resolutions.%s: %s is empty or too long." % [resolution.id, field]
	var hazard_steps: Dictionary = {}
	for hazard: Dictionary in raw.get("hazards", []):
		if hazard.step >= raw.encounters.size() or hazard_steps.has(hazard.step): return "hazards.%s: Duplicate encounter or encounter out of range." % hazard.id
		hazard_steps[hazard.step] = true
		if hazard.label.strip_edges().is_empty() or hazard.label.length() > 32 or hazard.description.strip_edges().is_empty() or hazard.description.length() > 160: return "hazards.%s: Invalid display text." % hazard.id
		var cells := parse_grid_cells(hazard.cells)
		if cells.is_empty(): return "hazards.%s: Invalid cell list." % hazard.id
		for cell: Vector2i in cells:
			if cell.x >= rule.grid_width or cell.y >= rule.grid_height: return "hazards.%s: Cell is outside the bag." % hazard.id
		var required := split_ids(hazard.required_tags)
		if required.is_empty(): return "hazards.%s: A target tag is required." % hazard.id
		for tag in required:
			if not tags.has(tag): return "hazards.%s: Unknown target tag." % hazard.id
	for event: Dictionary in raw.events:
		if raw.routes.is_empty() or event.step != 0 or raw.encounters.size() < 3: return "events.%s: Only events after the first encounter on routes with at least three encounters are supported." % event.id
		if not items.has(event.item_id) or items[event.item_id].consumable: return "events.%s: A valid non-consumable item is required." % event.id
		for field in ["title", "description", "take_label", "leave_label", "take_result", "leave_result"]:
			if event[field].strip_edges().is_empty() or event[field].length() > 240: return "events.%s: %s is empty or too long." % [event.id, field]
		var fits := false
		for rotation in 4:
			var bounds := Vector2i.ZERO
			for cell in GridRules.cells(parse_cells(items[event.item_id].footprint), rotation): bounds = bounds.max(cell + Vector2i.ONE)
			fits = fits or (bounds.x <= rule.grid_width and bounds.y <= rule.grid_height)
		if not fits: return "events.%s: The keepsake cannot fit in an empty bag." % event.id
	if rule.grid_width * rule.grid_height > EffectApplier.MAX_ACTIVE_ITEMS: return "rules: The engine supports at most 64 grid cells."
	if not raw.art.actors.has(rule.player_visual): return "rules: player_visual missing"
	var occupied: Dictionary = {}
	var active_units := 0
	for row: Dictionary in raw.loadout:
		if not items.has(row.item_id): return "loadout.%s: Unknown item_id" % row.id
		if row.x == -1 and row.y == -1: continue
		active_units += split_ids(items[row.item_id].effect_ids).size()
		if active_units > EffectApplier.MAX_ACTIVE_UNITS: return "loadout: At most 256 effects can be equipped at once."
		for cell in GridRules.cells(parse_cells(items[row.item_id].footprint), row.rotation):
			var point := cell + Vector2i(row.x, row.y)
			if point.x < 0 or point.y < 0 or point.x >= rule.grid_width or point.y >= rule.grid_height or occupied.has(point): return "loadout.%s: Starting layout overlaps or is out of bounds" % row.id
			occupied[point] = true
	return ""

func _validate_art(art: Variant) -> String:
	if not art is Dictionary or not art.get("palette") is Array or not art.get("icons") is Dictionary or not art.get("actors") is Dictionary: return "art: Invalid palette/icons/actors format"
	if art.palette.is_empty() or art.palette.size() > 64: return "art: Invalid palette size"
	for color: Variant in art.palette:
		if not color is String or not Color.html_is_valid(color): return "art: Invalid color"
	for group in ["icons", "actors"]:
		for id: String in art[group]:
			var shape: Variant = art[group][id]
			if not _id(id) or not shape is Dictionary or not shape.get("parts") is Array or shape.parts.size() > 256: return "art.%s.%s: Invalid shape" % [group,id]
			if group == "icons" and shape.has("background_path"): return "art.%s: An icon cannot specify a background path." % id
			for key in ["texture_path", "background_path"]:
				if not shape.has(key): continue
				var path: Variant = shape[key]
				if not path is String or not path.begins_with("res://assets/visuals/") or ".." in path or not path.ends_with(".png") or not ResourceLoader.exists(path, "Texture2D"):
					return "art.%s.%s: Invalid PNG resource path." % [id, key]
			if group == "icons":
				if not shape.get("size") is Array or shape["size"].size() != 2: return "art.%s: Invalid size" % id
				for side: Variant in shape["size"]:
					if not (side is float or side is int) or not is_finite(side) or side < 1 or side > 1536: return "art.%s: Size out of bounds" % id
			for part: Variant in shape.parts:
				if not part is Array or part.size() != 5: return "art.%s: Invalid rectangle format" % id
				for i in 4:
					if not (part[i] is float or part[i] is int) or not is_finite(part[i]) or part[i] < 0 or part[i] > 1536: return "art.%s: Rectangle out of bounds" % id
				if part[2] == 0 or part[3] == 0: return "art.%s: Empty rectangle" % id
				if group == "icons":
					if not (part[4] is float or part[4] is int) or part[4] != floor(part[4]) or part[4] < 0 or part[4] >= art.palette.size(): return "art.%s: Invalid palette index" % id
					if part[0]+part[2] > shape["size"][0] or part[1]+part[3] > shape["size"][1]: return "art.%s: Icon exceeds size limit" % id
				elif not part[4] is String or not Color.html_is_valid(part[4]): return "art.%s: Invalid color" % id
	return ""

static func materialize(raw: Dictionary) -> Dictionary:
	# Called only on successfully validated data; never publishes a partial catalog.
	var effects: Dictionary = {}
	for row: Dictionary in raw.effects:
		var unit := EffectUnit.new()
		for field in ItemCodec.EFFECT_FIELDS:
			unit.set(field, split_ids(row[field]) if field in ["required_tags", "condition_tags"] else row[field])
		effects[row.id] = unit
	var definitions: Dictionary = {}
	for row: Dictionary in raw.items:
		var item := ItemData.new()
		for field in ["id", "display_name", "description", "cost", "uses_per_turn", "consumable"]: item.set(field, row[field])
		item.tags = split_ids(row.tags)
		item.footprint = parse_cells(row.footprint)
		for id in split_ids(row.effect_ids): item.effects.append(effects[id])
		item.icon = raw.art.icons[row.icon_id].duplicate(true)
		item.icon["presentation_id"] = row.icon_id
		item.icon["palette"] = raw.art.palette.duplicate()
		definitions[row.id] = item
	var config: Dictionary = raw.rules[0].duplicate(true)
	config.tag_labels = {}
	for row: Dictionary in raw.tags: config.tag_labels[row.id] = row.label
	var player_visual_id: String = config.player_visual
	config.player_visual = raw.art.actors[player_visual_id].duplicate(true)
	config.player_visual["presentation_id"] = player_visual_id
	config.encounters = []
	config.reward_offers = {}
	config.reward_definitions = {}
	for row: Dictionary in raw.rewards:
		config.reward_offers[row.encounter_id] = {"id": row.id, "item_ids": Array(split_ids(row.item_ids))}
		config.reward_definitions[row.id] = {"id": row.id, "item_ids": Array(split_ids(row.item_ids))}
	var encounters: Array = raw.encounters.duplicate(true)
	encounters.sort_custom(func(a, b): return a.order < b.order)
	for row: Dictionary in encounters:
		var enemy := {"id": row.id, "name": row.name, "hp": row.hp, "visual": raw.art.actors[row.visual_id].duplicate(true), "intents": [], "reactions": []}
		enemy.visual["presentation_id"] = row.visual_id
		for id in split_ids(row.intent_ids): enemy.intents.append(ItemCodec.effect(effects[id]))
		for id in split_ids(row.reaction_ids): enemy.reactions.append(ItemCodec.effect(effects[id]))
		config.encounters.append(enemy)
	config.events = raw.events.duplicate(true)
	config.resolutions = raw.get("resolutions", []).duplicate(true)
	config.hazards = []
	for row: Dictionary in raw.get("hazards", []):
		var hazard := row.duplicate(true)
		hazard.cells = parse_grid_cells(row.cells)
		hazard.required_tags = Array(split_ids(row.required_tags))
		config.hazards.append(hazard)
	config.routes = []
	var positions: Dictionary = {}
	for index in config.encounters.size(): positions[config.encounters[index].id] = index
	for row: Dictionary in raw.routes:
		var order: Array = []
		for id in split_ids(row.encounter_ids): order.append(positions[id])
		config.routes.append({"id": row.id, "name": row.name, "description": row.description,
			"encounters": order, "rewards": Array(split_ids(row.reward_ids))})
	return {"definitions": definitions, "config": config, "loadout": raw.loadout.duplicate(true)}
