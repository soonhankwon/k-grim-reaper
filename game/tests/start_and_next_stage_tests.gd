extends SceneTree

const DemoFlow = preload("res://tests/arang_demo_flow.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _submit(main: Control, command: Dictionary) -> bool:
	var error: String = main.session.submit(command)
	if error.is_empty(): main.session.skip_playback()
	return error.is_empty()

func _click(button: Control) -> void:
	var point := root.get_screen_transform() * button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, false)

func _english(node: Node) -> bool:
	if node is CanvasItem and not node.is_visible_in_tree(): return true
	if node is Label or node is Button:
		if PresentationLocale.contains_hangul(str(node.text)): return false
	for child in node.get_children():
		if not _english(child): return false
	return true

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var folder := ProjectSettings.globalize_path("res://../build/start-flow/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var main_slot := folder.path_join("main.json")
	var launcher := (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	launcher.save_path = main_slot
	root.add_child(launcher)
	await process_frame
	check(launcher.game == null and launcher.intro.action_button.text == "Begin Delivery" and not FileAccess.file_exists(main_slot), "title screen precedes gameplay and does not create a save")
	check(_english(launcher), "title screen is English")
	_click(launcher.intro.action_button)
	await process_frame
	check(launcher.game != null and launcher.game.session.display_snapshot().phase == "packing" and FileAccess.file_exists(main_slot), "begin opens preparation, not combat")
	var original := FileAccess.get_file_as_string(main_slot)
	launcher.queue_free()
	await process_frame
	launcher = (load("res://scenes/launch.tscn") as PackedScene).instantiate()
	launcher.save_path = main_slot
	root.add_child(launcher)
	await process_frame
	check(launcher.intro.action_button.text == "Continue Delivery" and FileAccess.get_file_as_string(main_slot) == original, "continue is offered without rewriting an existing save")
	_click(launcher.intro.action_button)
	await process_frame
	check(launcher.game.session.display_snapshot().phase == "packing" and FileAccess.get_file_as_string(main_slot) == original, "continue restores the existing state")
	launcher.queue_free()
	await process_frame
	var arang_slot := folder.path_join("arang.json")
	var flow := DemoFlow.new()
	flow.save_slot = arang_slot
	root.add_child(flow)
	await process_frame
	check(flow.arang == null and not FileAccess.file_exists(arang_slot), "Arang demo has its own intro before saving")
	_click(flow.intro.action_button)
	await process_frame
	var main: Control = flow.arang
	check(main != null and main.session.display_snapshot().phase == "packing", "Arang demo starts in preparation")
	check(_submit(main, {"type":"start"}), "first battle starts")
	for turn in 8:
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty(): _submit(main, {"type":"use_item", "uid":uid})
		if main.session.display_snapshot().phase != "battle": break
		_submit(main, {"type":"end_turn"})
	check(main.session.display_snapshot().phase == "reward", "first battle is playable")
	var offer: String = main.session.display_snapshot().reward.offer_id
	check(_submit(main, {"type":"reward_skip", "offer_id":offer}) and _submit(main, {"type":"advance"}), "continue to evidence")
	var event: Dictionary = main.session.display_snapshot().event
	check(_submit(main, {"type":"event_take", "event_id":event.id}) and _submit(main, {"type":"event_confirm", "event_id":event.id}), "keep evidence")
	check(_submit(main, {"type":"choose_route", "route_id":main.inventory.config.routes[0].id}), "choose Arang route")
	check(main.session.stash("hat").is_empty() and main.session.place(event.uid, Vector2i(1, 2), 0).is_empty(), "pack the evidence")
	check(_submit(main, {"type":"start"}) and _submit(main, {"type":"resolve_encounter"}) and _submit(main, {"type":"event_continue", "event_id":event.id}), "resolve Arang and finish chapter one")
	check(main.session.display_snapshot().phase == "complete" and main.primary.text == "Next: Stage 2 Preview", "completion exposes the next preview")
	var saved_arang := FileAccess.get_file_as_string(arang_slot)
	_click(main.primary)
	await process_frame
	check(flow.intro != null and flow.intro.note.contains("not saved") and flow.intro.note.contains("Separate starting bag"), "transition discloses the preview limitations")
	_click(flow.intro.action_button)
	await process_frame
	check(flow.preview != null and flow.preview.session.save_service == null and flow.preview.session.display_snapshot().phase == "packing", "next preview is playable without touching save")
	check(_english(flow.preview), "next preview has English visible text")
	check(FileAccess.get_file_as_string(arang_slot) == saved_arang, "entering the preview does not rewrite Arang progress")
	check(_submit(flow.preview, {"type":"start"}) and flow.preview.session.display_snapshot().get("puzzle", {}).has("target"), "stage-two preview runs its own target rules")
	for turn in 3: check(_submit(flow.preview, {"type":"end_turn"}), "stage-two turns can advance")
	check(_english(flow.preview) and not flow.preview.session.display_snapshot().puzzle.stolen.is_empty(), "stage-two theft and combat display remain English")
	flow._return_to_arang()
	await process_frame
	check(main.is_visible_in_tree() and main.session.display_snapshot().phase == "complete" and FileAccess.get_file_as_string(arang_slot) == saved_arang, "exiting restores completed Arang without modifying the save")
	flow.queue_free()
	await process_frame
	flow = DemoFlow.new()
	flow.save_slot = arang_slot
	root.add_child(flow)
	await process_frame
	check(flow.intro.action_button.text == "Continue Delivery" and FileAccess.get_file_as_string(arang_slot) == saved_arang, "completed Arang save is offered without modification")
	_click(flow.intro.action_button)
	await process_frame
	check(flow.arang.session.display_snapshot().phase == "complete" and flow.arang.primary.text == "Next: Stage 2 Preview", "reopening completed Arang restores the preview entry")
	flow.queue_free()
	await process_frame
	flow = DemoFlow.new()
	flow.skip_intro = true
	root.add_child(flow)
	main = flow.arang
	check(_submit(main, {"type":"start"}), "combat-route first battle starts")
	for turn in 8:
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty(): _submit(main, {"type":"use_item", "uid":uid})
		if main.session.display_snapshot().phase != "battle": break
		_submit(main, {"type":"end_turn"})
	check(main.session.display_snapshot().phase == "reward", "combat-route first encounter ends")
	offer = main.session.display_snapshot().reward.offer_id
	check(_submit(main, {"type":"reward_skip", "offer_id":offer}) and _submit(main, {"type":"advance"}), "combat-route reaches evidence")
	event = main.session.display_snapshot().event
	check(_submit(main, {"type":"event_leave", "event_id":event.id}) and _submit(main, {"type":"choose_route", "route_id":main.inventory.config.routes[0].id}), "combat-route leaves the evidence")
	check(_submit(main, {"type":"start"}), "combat-route reaches Arang")
	var nearly_won: Dictionary = main.session.display_snapshot()
	nearly_won.enemy_health = 1
	main.session.reset(main.inventory, nearly_won)
	check(_submit(main, {"type":"use_item", "uid":"sword"}) and main.session.display_snapshot().phase == "event_result", "defeating Arang opens the event outcome")
	check(_submit(main, {"type":"event_continue", "event_id":event.id}) and main.primary.text == "Next: Stage 2 Preview", "combat ending also exposes the next preview")
	flow.queue_free()
	await process_frame
	print("START AND NEXT STAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
