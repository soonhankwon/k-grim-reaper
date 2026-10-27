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
	if _observed_exists and _observed_hash.is_empty(): return {"status":"error", "error":"저장 파일을 읽을 수 없습니다. 기존 파일을 보존했습니다."}
	if _observed_backup_exists and _observed_backup_hash.is_empty(): return {"status":"error", "error":"이전 정상본을 읽을 수 없습니다. 기존 파일을 보존했습니다."}
	if not _observed_exists and not _observed_backup_exists:
		_initialized = true
		_last_good = ""
		return {"status":"missing", "error":""}
	var primary := _read(path, model) if _observed_exists else {"status":"corrupt", "error":"주 저장이 없습니다."}
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
	return {"status":"error", "error":"저장 파일과 이전 정상본을 읽을 수 없습니다. 기존 파일을 보존했습니다. " + str(primary.error)}

func can_archive() -> bool:
	return _can_archive

func archive_and_start(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if not _can_archive: return "보관할 저장 파일을 다시 확인해야 합니다. 게임을 다시 열어 주세요."
	var lock_error := _lock()
	if not lock_error.is_empty(): return lock_error
	var result := _archive_and_start_locked(state, model, history)
	_unlock()
	return result

func _archive_and_start_locked(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if FileAccess.file_exists(path) != _observed_exists or (_observed_exists and FileAccess.get_sha256(path) != _observed_hash):
		return "기존 저장이 변경되었습니다. 게임을 다시 열어 확인하세요."
	if FileAccess.file_exists(_backup) != _observed_backup_exists or (_observed_backup_exists and FileAccess.get_sha256(_backup) != _observed_backup_hash):
		return "이전 정상본이 변경되었습니다. 게임을 다시 열어 확인하세요."
	var text := SaveCodec.encode(state, model, history)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "새 저장이 파일 크기 제한을 넘었습니다."
	var verified := SaveCodec.new().decode(text, model)
	if verified.status != "ok": return "새 저장 검증 실패: " + str(verified.error)
	var archive_dir := path.get_base_dir().path_join("archive")
	if DirAccess.make_dir_recursive_absolute(archive_dir) != OK: return "기존 저장 보관 폴더를 만들 수 없습니다."
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
		return error + " 보관한 파일은 남아 있습니다. 게임을 다시 열어 확인하세요."
	_can_archive = false
	return ""

func _read(filename: String, model: InventoryModel) -> Dictionary:
	var file := FileAccess.open(filename, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {"status":"corrupt", "error":"파일을 열 수 없거나 크기 제한을 넘었습니다."}
	var text := file.get_as_text()
	file.close()
	var result := SaveCodec.new().decode(text, model)
	if result.status == "ok": result.text = text
	return result

func write_slot(state: Dictionary, model: InventoryModel, history: Array) -> String:
	if not _initialized: return "저장 파일을 먼저 확인해야 합니다."
	var lock_error := _lock()
	if not lock_error.is_empty(): return lock_error
	var result := _write_locked(state, model, history)
	_unlock()
	return result

func _write_locked(state: Dictionary, model: InventoryModel, history: Array) -> String:
	var exists := FileAccess.file_exists(path)
	if exists != _observed_exists or (exists and FileAccess.get_sha256(path) != _observed_hash):
		return "저장 파일이 다른 실행에서 변경되었습니다. 게임을 다시 열어 확인하세요."
	var text := SaveCodec.encode(state, model, history)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "저장할 상태가 파일 크기 제한을 넘었습니다."
	var verified := SaveCodec.new().decode(text, model)
	if verified.status != "ok": return "저장 상태 검증 실패: " + str(verified.error)
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	var write_error := _write_text(temporary, text)
	if not write_error.is_empty(): return write_error
	if not _last_good.is_empty():
		var backup_temp := _backup + ".%d.tmp" % OS.get_process_id()
		write_error = _write_text(backup_temp, _last_good)
		if not write_error.is_empty(): return write_error
		if _replace_file(backup_temp, _backup) != OK: return "이전 정상 저장을 보관하지 못했습니다."
	if _recovered_primary:
		var archive_error := _archive_damaged_primary()
		if not archive_error.is_empty(): return archive_error
	if _replace_file(temporary, path) != OK: return "저장 파일 교체에 실패했습니다. 기존 저장을 유지합니다."
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
		return "" if FileAccess.get_sha256(archive) == expected_hash else "기존 저장의 보관 파일을 확인할 수 없습니다."
	var temporary := archive + ".%d.tmp" % OS.get_process_id()
	if DirAccess.copy_absolute(source, temporary) != OK or FileAccess.get_sha256(temporary) != expected_hash:
		return "기존 저장을 보관하지 못했습니다. 원본 파일을 유지합니다."
	if _replace_file(temporary, archive) != OK: return "기존 저장을 보관하지 못했습니다. 원본 파일을 유지합니다."
	return ""

func _write_text(filename: String, text: String) -> String:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file == null: return "저장 파일을 쓸 수 없습니다. 디스크 공간과 권한을 확인하세요."
	file.store_string(text)
	file.flush()
	var status := file.get_error()
	file.close()
	return "" if status == OK else "저장 파일 쓰기에 실패했습니다."

func _lock() -> String:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return "저장 폴더를 만들 수 없습니다."
	if DirAccess.make_dir_absolute(_lock_path) != OK:
		if DirAccess.dir_exists_absolute(_lock_path): return "저장 잠금이 있습니다. 다른 게임을 종료하고 남은 잠금 폴더를 확인하세요: " + _lock_path
		return "저장 잠금을 만들 수 없습니다. 저장 폴더의 권한을 확인하세요."
	return ""

func _unlock() -> void:
	if DirAccess.remove_absolute(_lock_path) != OK:
		push_warning("저장 잠금 폴더를 제거하지 못했습니다: " + _lock_path)
