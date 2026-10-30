class_name PresentationLocale
extends RefCounted
## Optional display-only strings for a validated catalog. Rules and content hash stay intact.

const FIELDS := {
	"items": ["display_name", "description"],
	"encounters": ["name"],
	"routes": ["name", "description"],
	"events": ["title", "description", "take_label", "leave_label", "take_result", "leave_result"],
	"resolutions": ["message", "result", "button", "unavailable", "completion_title"],
	"tags": ["label"]
}

static func apply(model: InventoryModel, path: String) -> String:
	if path.is_empty(): return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 262144: return "Cannot open the presentation text pack."
	var doc: Variant = JSON.parse_string(file.get_as_text())
	if not doc is Dictionary or doc.size() != FIELDS.size(): return "Invalid presentation text pack."
	var targets := {"items": model.definitions, "tags": model.config.tag_labels}
	for table in ["encounters", "routes", "events", "resolutions"]:
		var rows := {}
		for entry: Dictionary in model.config.get(table, []): rows[entry.id] = entry
		targets[table] = rows
	# Check every key and field before applying anything, so a bad pack cannot mix languages.
	for table: String in FIELDS:
		if not doc.get(table) is Dictionary or doc[table].size() != targets[table].size(): return "Incomplete presentation text: " + table
		for id in targets[table]:
			var entry: Variant = doc[table].get(id)
			if not entry is Dictionary or entry.size() != FIELDS[table].size(): return "Invalid presentation entry: " + str(id)
			for field: String in FIELDS[table]:
				var value: Variant = entry.get(field)
				if not value is String or value.strip_edges().is_empty() or value.length() > 1000 or contains_hangul(value): return "Invalid English text: " + str(id) + "." + field
	for table: String in FIELDS:
		for id in targets[table]:
			var entry: Dictionary = doc[table][id]
			if table == "items":
				targets[table][id].display_name = entry.display_name
				targets[table][id].description = entry.description
			elif table == "tags": model.config.tag_labels[id] = entry.label
			else:
				for field: String in FIELDS[table]: targets[table][id][field] = entry[field]
	return ""

static func contains_hangul(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		if (code >= 0x1100 and code <= 0x11ff) or (code >= 0x3130 and code <= 0x318f) or (code >= 0xac00 and code <= 0xd7af): return true
	return false

static func message(value: String) -> String:
	return "[Previous message unavailable in English.]" if contains_hangul(value) else value
