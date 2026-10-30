class_name SaveService
extends RefCounted
## Slot IO; caller decides when a successful write becomes gameplay state.

const DEFAULT_PATH := "user://saves/run.json"
const MAX_BYTES := 8 * 1024 * 1024
var path: String
var _backup: String
var _lock_path: String
var _observed_exists := false
var _observed_hash := ""
var _last_good := ""
var _initialized := false
var _recovered_primary := false
var _observed_backup_exists := false
var _observed_backup_hash := ""
var _can_archive := false

func _init(slot_path := DEFAULT_PATH) -> void:
	path = ProjectSettings.globalize_path(slot_path)
	_backup = path + ".bak"
	_lock_path = path + ".lock"

func load_slot(model: InventoryModel) -> Dictionary:
	_initialized = false
	_can_archive = false
	var lock_error := _lock()
	if not lock_error.is_empty(): return {"status":"error", "error":lock_error}
	var result := _load_locked(model)
	_unlock()
	return result

func _load_locked(model: InventoryModel) -> Dictionary:
	_observed_exists = FileAccess.file_exists(path)
	_observed_hash = FileAccess.get_sha256(path) if _observed_exists else ""
	_observed_backup_exists = FileAccess.file_exists(_backup)
	_observed_backup_hash = FileAccess.get_sha256(_backup) if _observed_backup_exists else ""
	if _observed_exists and _observed_hash.is_empty(): return {"status":"error", "error":"Cannot read the save file. The existing file was preserved."}
	if _observed_backup_exists and _observed_backup_hash.is_empty(): return {"status":"error", "error":"Cannot read the backup. The existing file was preserved."}
	if not _observed_exists and not _observed_backup_exists:
		_initialized = true
		_last_good = ""
		return {"status":"missing", "error":""}
	var primary := _read(path, model) if _observed_exists else {"status":"corrupt", "error":"Primary save is missing."}
	_can_archive = true
	if primary.status == "ok":
		_can_archive = false
		_recovered_primary = false
		_last_good = primary.text
		_initialized = true
		return primary
	# Never silently replace a save made for a different version or content.
	if primary.status == "incompatible": return primary
	if _observed_backup_exists:
		var backup := _read(_backup, model)
		if backup.status == "ok":
			_can_archive = false
			_recovered_primary = _observed_exists
			_last_good = backup.text
			_initialized = true
			backup.recovered = true
			return backup
		if backup.status == "incompatible": return backup
	return {"status":"error", "error":"Cannot read the save or backup. Existing files were preserved. " + str(primary.error)}

func can_archive() -> bool:
	return _can_archive

func archive_and_start(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if not _can_archive: return "Recheck the save to archive. Please reopen the game."
	var lock_error := _lock()
	if not lock_error.is_empty(): return lock_error
	var result := _archive_and_start_locked(state, model, history)
	_unlock()
	return result

func _archive_and_start_locked(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if FileAccess.file_exists(path) != _observed_exists or (_observed_exists and FileAccess.get_sha256(path) != _observed_hash):
		return "The existing save changed. Reopen the game to check it."
	if FileAccess.file_exists(_backup) != _observed_backup_exists or (_observed_backup_exists and FileAccess.get_sha256(_backup) != _observed_backup_hash):
		return "The backup changed. Reopen the game to check it."
	var text := SaveCodec.encode(state, model, history)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "The new save exceeds the size limit."
	var verified := SaveCodec.new().decode(text, model)
	if verified.status != "ok": return "New save validation failed: " + str(verified.error)
	var archive_dir := path.get_base_dir().path_join("archive")
	if DirAccess.make_dir_recursive_absolute(archive_dir) != OK: return "Cannot create the save archive folder."
	for entry in [[path, _observed_exists, _observed_hash], [_backup, _observed_backup_exists, _observed_backup_hash]]:
		if not entry[1]: continue
		var archive := archive_dir.path_join(path.get_file() + "." + str(entry[2]) + ".json")
		var error := _archive_copy(entry[0], archive, entry[2])
		if not error.is_empty(): return error
	# Seed a same-state backup; any incompatible originals are already retained in archive/.
	_initialized = true
	_last_good = text
	_recovered_primary = false
	var error := _write_locked(state, model, history)
	if not error.is_empty():
		_initialized = false
		_can_archive = false
		return error + " Archived files were preserved. Reopen the game to check them."
	_can_archive = false
	return ""

func _read(filename: String, model: InventoryModel) -> Dictionary:
	var file := FileAccess.open(filename, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {"status":"corrupt", "error":"Cannot open the file, or it exceeds the size limit."}
	var text := file.get_as_text()
	file.close()
	var result := SaveCodec.new().decode(text, model)
	if result.status == "ok": result.text = text
	return result

func write_slot(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if not _initialized: return "Check the save file first."
	var lock_error := _lock()
	if not lock_error.is_empty(): return lock_error
	var result := _write_locked(state, model, history)
	_unlock()
	return result

func _write_locked(state: Dictionary, model: InventoryModel, history: Array) -> String:
	var exists := FileAccess.file_exists(path)
	if exists != _observed_exists or (exists and FileAccess.get_sha256(path) != _observed_hash):
		return "Another game instance changed the save. Reopen the game."
	var text := SaveCodec.encode(state, model, history)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "The state to save exceeds the size limit."
	var verified := SaveCodec.new().decode(text, model)
	if verified.status != "ok": return "Save-state validation failed: " + str(verified.error)
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	var write_error := _write_text(temporary, text)
	if not write_error.is_empty(): return write_error
	if not _last_good.is_empty():
		var backup_temp := _backup + ".%d.tmp" % OS.get_process_id()
		write_error = _write_text(backup_temp, _last_good)
		if not write_error.is_empty(): return write_error
		if _replace_file(backup_temp, _backup) != OK: return "Could not preserve the previous save."
	if _recovered_primary:
		var archive_error := _archive_damaged_primary()
		if not archive_error.is_empty(): return archive_error
	if _replace_file(temporary, path) != OK: return "Could not replace the save file. The existing save was preserved."
	_last_good = text
	_recovered_primary = false
	_observed_exists = true
	_observed_hash = text.sha256_text()
	return ""

func _replace_file(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(from, to)

func _archive_damaged_primary() -> String:
	var archive := path + ".damaged-" + _observed_hash
	return _archive_copy(path, archive, _observed_hash)

func _archive_copy(source: String, archive: String, expected_hash: String) -> String:
	if FileAccess.file_exists(archive):
		return "" if FileAccess.get_sha256(archive) == expected_hash else "Cannot verify the archived save."
	var temporary := archive + ".%d.tmp" % OS.get_process_id()
	if DirAccess.copy_absolute(source, temporary) != OK or FileAccess.get_sha256(temporary) != expected_hash:
		return "Could not archive the save. The original file was preserved."
	if _replace_file(temporary, archive) != OK: return "Could not archive the save. The original file was preserved."
	return ""

func _write_text(filename: String, text: String) -> String:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file == null: return "Cannot write the save. Check disk space and permissions."
	file.store_string(text)
	file.flush()
	var status := file.get_error()
	file.close()
	return "" if status == OK else "Failed to write the save file."

func _lock() -> String:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return "Cannot create the save folder."
	if DirAccess.make_dir_absolute(_lock_path) != OK:
		if DirAccess.dir_exists_absolute(_lock_path): return "The save is locked. Close other game instances and check the lock folder: " + _lock_path
		return "Cannot create a save lock. Check save-folder permissions."
	return ""

func _unlock() -> void:
	if DirAccess.remove_absolute(_lock_path) != OK:
		push_warning("Cannot remove the save lock folder: " + _lock_path)
