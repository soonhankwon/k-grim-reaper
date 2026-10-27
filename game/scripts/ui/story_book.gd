class_name StoryBook
extends RefCounted
## Authored narrative is presentation-only and never changes the run.

const PATH := "res://data/presentation/story.json"

static func load_entries(path := PATH) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 262144: return []
	return validate(JSON.parse_string(file.get_as_text()))

static func validate(document: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not document is Dictionary or document.get("schema_version") != 1 or not document.get("entries") is Array: return []
	if document.entries.is_empty() or document.entries.size() > 100: return []
	var seen := {}
	var previous := -1
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]{0,63}$")
	for entry: Variant in document.entries:
		if not entry is Dictionary: return []
		var id: Variant = entry.get("id")
		var threshold: Variant = entry.get("min_completed")
		if not id is String or pattern.search(id) == null or seen.has(id): return []
		if (not threshold is int and not threshold is float) or not is_finite(threshold) or threshold != floor(threshold) or threshold < previous or threshold > 64: return []
		for spec in [["title", 48], ["teaser", 80], ["text", 1000]]:
			var value: Variant = entry.get(spec[0])
			if not value is String or value.strip_edges().is_empty() or value.length() > spec[1]: return []
		if result.is_empty() and threshold != 0: return []
		seen[id] = true
		previous = int(threshold)
		result.append(entry.duplicate(true))
	return result

static func unlocked(view: Dictionary, entries: Array[Dictionary]) -> Array[Dictionary]:
	var completed := RouteRules.step(view)
	if view.phase in ["reward", "victory", "route", "event", "event_result"]: completed = mini(completed + 1, view.config.encounters.size() - 1)
	if view.phase == "complete": completed = view.config.encounters.size()
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if int(entry.min_completed) <= completed: result.append(entry.duplicate(true))
	return result
