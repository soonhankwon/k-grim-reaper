extends SceneTree

var failed := false
var content_path: String
var slot_path: String

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func make_main(path: String) -> Control:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.content_path = content_path
	main.save_path = path
	root.add_child(main)
	return main

func act(main: Control, uid: String) -> void:
	main._activate_item(uid)
	main.session.skip_playback()

func _run() -> void:
	root.size = Vector2i(1280,720)
	var parent := ProjectSettings.globalize_path("res://../build/save-ui-tests")
	DirAccess.make_dir_recursive_absolute(parent)
	var serial := 0
	var folder := parent.path_join("%d-%d" % [OS.get_process_id(), serial])
	while DirAccess.dir_exists_absolute(folder):
		serial += 1
		folder = parent.path_join("%d-%d" % [OS.get_process_id(), serial])
	DirAccess.make_dir_absolute(folder)
	content_path = folder.path_join("fixture.json")
	slot_path = folder.path_join("run.json")
	var raw: Dictionary = ContentLoader.new().load_json("res://tests/fixtures/baseline.json").raw
	raw.rewards = [{"id":"ui_offer", "encounter_id":"gate_1", "item_ids":"rope|mirror|coin"}]
	var file := FileAccess.open(content_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var main := make_main(slot_path)
	await process_frame
	verify(FileAccess.file_exists(slot_path) and not main._save_blocked, "new run creates a save in its isolated slot")
	main._select("seal")
	main._place("seal", Vector2i(2,1), 0)
	main._primary_action()
	main.session.skip_playback()
	act(main, "sword")
	act(main, "bell")
	act(main, "hat")
	main._primary_action()
	main.session.skip_playback()
	act(main, "sword")
	verify(main.session.display_snapshot().phase == "reward", "UI reaches saved reward")
	main.layout.rewards.choices[0].pressed.emit()
	main.session.skip_playback()
	var uid: String = main.session.display_snapshot().reward.uid
	main._select("hat")
	main._stash_selected()
	main._select(uid)
	main._place(uid, Vector2i(1,2), 1)
	var expected: Dictionary = main.session.state_snapshot()
	var history: Array = main.inventory.history.duplicate(true)
	verify(main.inventory.items[uid].rotation == 1 and not main.primary.disabled, "rotated reward is ready to confirm")
	main.queue_free()
	await process_frame
	main = make_main(slot_path)
	await process_frame
	verify(main.session.display_snapshot() == expected and main.inventory.history == history, "scene reopening restores reward, layout, and undo history")
	verify(main.layout.rewards.visible and main.selected == uid and main.board.pending_rotation == 1 and not main.primary.disabled, "restored reward remains selected with its rotation")
	main._undo()
	verify(not main.inventory.is_packed(uid) and main.primary.disabled, "restored undo changes confirm eligibility")
	main._select(uid)
	main._place(uid, Vector2i(1,2), 1)
	main._primary_action()
	main.session.skip_playback()
	verify(main.session.display_snapshot().reward.status == "claimed", "restored reward can be claimed")
	main._primary_action()
	main.session.skip_playback()
	expected = main.session.state_snapshot()
	main.queue_free()
	await process_frame
	main = make_main(slot_path)
	await process_frame
	verify(main.session.display_snapshot() == expected and main.inventory.is_packed(uid), "next encounter and claimed reward resume together")
	main.queue_free()
	await process_frame
	file = FileAccess.open(slot_path, FileAccess.WRITE)
	file.store_string("{damaged")
	file.close()
	main = make_main(slot_path)
	await process_frame
	var recovery_visible := false
	for child in main.get_children():
		if child is AcceptDialog and child.title == "이전 저장에서 복구" and child.visible: recovery_visible = true
	verify(not main._save_blocked and recovery_visible and "누락" in main.labels.notice.text, "backup recovery warns that recent progress may be missing")
	main.queue_free()
	await process_frame
	# Both broken copies are preserved and the UI cannot overwrite them.
	var bad := folder.path_join("broken.json")
	file = FileAccess.open(bad, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	main = make_main(bad)
	await process_frame
	verify(main._save_blocked and main.primary.disabled and not main.layout.buttons.restart.disabled and main.recovery_dialog != null, "unreadable save locks gameplay and offers explicit archive")
	verify(main.layout.guide.heading.text == "저장 확인", "guide reflects blocked save instead of normal gameplay")
	verify(main.layout.buttons.story.disabled and not main.layout.buttons.story_teaser.visible, "blocked save cannot show a fictitious story state")
	main._reset_run()
	verify(FileAccess.get_file_as_string(bad) == "{broken", "blocked restart preserves original file")
	var damaged_hash := FileAccess.get_sha256(bad)
	main.recovery_dialog.confirmed.emit()
	verify(not main._save_blocked and not main.primary.disabled and main.session.display_snapshot().phase == "packing", "explicit archive starts a fresh run")
	var archived := folder.path_join("archive").path_join("broken.json." + damaged_hash + ".json")
	verify(FileAccess.get_file_as_string(archived) == "{broken" and FileAccess.get_file_as_string(bad) != "{broken", "archive keeps original file before fresh save")
	main.queue_free()
	await process_frame
	print("SAVE UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
