extends SceneTree
## Offline, atomic CSV/JSON compiler. No network access or formula execution.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		printerr("Usage: import_content.gd -- <CSV directory | JSON file> [--check]")
		quit(1)
		return
	var source := ProjectSettings.globalize_path(args[0])
	var loader := ContentLoader.new()
	var result := loader.load_csv_directory(source) if DirAccess.dir_exists_absolute(source) else loader.load_json(source)
	if not result.error.is_empty():
		printerr(result.error)
		quit(1)
		return
	var output := ProjectSettings.globalize_path(ItemCatalog.DEFAULT_PATH)
	if "--check" in args:
		var current := ContentLoader.new().load_json(output)
		if not current.error.is_empty() or current.raw != result.raw:
			printerr("CONTENT: catalog.json이 원본과 다릅니다. scripts/import-content.sh를 실행하세요.")
			quit(1)
			return
	else:
		var temporary := output + ".%d.tmp" % OS.get_process_id()
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write " + temporary)
			quit(1)
			return
		file.store_string(JSON.stringify(result.raw, "\t", true) + "\n")
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK or DirAccess.rename_absolute(temporary, output) != OK:
			printerr("콘텐츠 파일 교체 실패. 기존 파일을 유지합니다.")
			quit(1)
			return
	print("CONTENT: PASS — %d items, %d effects, %d encounters" % [result.raw.items.size(), result.raw.effects.size(), result.raw.encounters.size()])
	quit(0)
