class_name ItemCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/content/catalog.json"
static var last_error := ""

static func create_inventory(path := DEFAULT_PATH, csv_directory := false) -> InventoryModel:
	var loader := ContentLoader.new()
	var loaded := loader.load_csv_directory(path) if csv_directory else loader.load_json(path)
	last_error = loaded.error
	if not last_error.is_empty(): return null
	return from_validated(loaded.raw)

static func from_validated(raw: Dictionary) -> InventoryModel:
	var catalog := ContentLoader.materialize(raw)
	var inventory := InventoryModel.new()
	inventory.content_hash = JSON.stringify(raw, "", true).sha256_text()
	var previous := raw.duplicate(true)
	previous.erase("events")
	previous.schema_version = 3
	inventory.previous_content_hash = JSON.stringify(previous, "", true).sha256_text()
	var legacy := previous.duplicate(true)
	legacy.erase("routes")
	legacy.schema_version = 2
	inventory.legacy_content_hash = JSON.stringify(legacy, "", true).sha256_text()
	inventory.config = catalog.config
	inventory.dimensions = Vector2i(catalog.config.grid_width, catalog.config.grid_height)
	inventory.definitions = catalog.definitions
	for row: Dictionary in catalog.loadout:
		if not inventory.add_item(row.id, catalog.definitions[row.item_id], Vector2i(row.x, row.y), row.rotation):
			last_error = "검증된 초기 배치를 생성하지 못했습니다: " + row.id
			return null
	inventory.authored_items = inventory.items.duplicate(true)
	inventory.history.clear()
	return inventory
