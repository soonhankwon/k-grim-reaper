extends SceneTree

var failed := false

func verify(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280,720)
	var folder := ProjectSettings.globalize_path("res://../build/guide-ui/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var slot := folder.path_join("run.json")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path = slot
	root.add_child(main)
	await process_frame
	await process_frame
	verify(main.layout.guide.visible and main.layout.guide.heading.text == "보따리 준비", "new run shows packing guide")
	var before: Dictionary = main.session.state_snapshot()
	var saved := FileAccess.get_sha256(slot)
	main.layout.buttons.guide.pressed.emit()
	verify(not main.layout.guide.visible, "guide can be hidden")
	main.layout.buttons.guide.pressed.emit()
	verify(main.layout.guide.visible and main.session.state_snapshot() == before and FileAccess.get_sha256(slot) == saved, "guide toggle never mutates gameplay or save")
	main._inspect("sword")
	verify(main.layout.details.visible and not main.layout.guide.visible, "item details take priority on hover")
	main.layout.buttons.guide.pressed.emit()
	verify(main.layout.guide.visible and not main.layout.details.visible, "guide can be opened over a selected item")
	main._inspect("seal")
	verify(main.layout.details.visible and not main.layout.guide.visible, "inspecting another item restores details")
	main._inspect("")
	verify(main.layout.guide.visible, "guide returns after hover ends")
	for window_size in [Vector2i(1024,576), Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		var guide: Rect2 = main.layout.guide.get_global_rect()
		verify(Rect2(Vector2.ZERO, main.size).encloses(guide), "guide fits window at " + str(window_size))
		verify(not guide.intersects(main.primary.get_global_rect()) and not guide.intersects(main.board.get_global_rect()), "guide leaves action and inventory accessible")
		verify(main.layout.guide.get_combined_minimum_size().y <= 250.0, "guide text fits its panel")
	root.size = Vector2i(1280,720)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/guide-screen.png"))
	main._primary_action()
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "전투 중", "combat guide follows displayed phase")
	await process_frame
	verify(main.layout.guide.get_combined_minimum_size().y <= 250.0, "combat guide text fits")
	var state: Dictionary = main.session.display_snapshot()
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	main._activate_item("sword")
	verify(main.session.state_snapshot().phase == "reward" and main.layout.guide.heading.text == "전투 중", "guide does not reveal victory before playback")
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "보상과 정리", "reward guide follows victory playback")
	await process_frame
	verify(main.layout.guide.get_combined_minimum_size().y <= 250.0, "reward guide text fits")
	main.layout.rewards.choices[0].pressed.emit()
	main.session.skip_playback()
	verify("자리가 부족하면" in main.layout.guide.body.text, "selected reward has placement guidance")
	main._reward_action("reward_skip")
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "길이 열렸습니다", "victory guidance follows reward")
	main._primary_action()
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "길가의 선택", "event guidance follows event display")
	main._event_action("event_leave")
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "갈림길", "route guidance follows route display")
	await process_frame
	verify(main.layout.guide.get_combined_minimum_size().y <= 250.0, "route guide text fits")
	before = main.session.state_snapshot()
	main._primary_action()
	verify(main.session.state_snapshot() == before, "direct primary action at route cannot reset progress")
	main.layout.routes.choices[1].pressed.emit()
	main.session.skip_playback()
	verify(main.layout.guide.heading.text == "보따리 준비" and main.session.display_snapshot().encounter == 2, "guide returns to preparation on selected path")
	before = main.session.display_snapshot()
	saved = FileAccess.get_sha256(slot)
	main.queue_free()
	await process_frame
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path = slot
	root.add_child(main)
	await process_frame
	verify(main.session.display_snapshot() == before and main.layout.guide.heading.text == "보따리 준비" and FileAccess.get_sha256(slot) == saved, "resume keeps save and shows current guide")
	main.queue_free()
	await process_frame
	print("GUIDE UI: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
