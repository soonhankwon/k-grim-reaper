extends SceneTree

const Experiment = preload("res://tests/arang_experiment_setup.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func submit(main: Control, request: Dictionary) -> String:
	var error: String = main.session.submit(request)
	if error.is_empty(): main.session.skip_playback()
	return error

func win_by_combat(main: Control) -> bool:
	for turn in range(8):
		for uid in ["sword", "bell", "hat"]:
			if main.session.display_snapshot().phase != "battle": break
			if main.session.use_error(uid).is_empty():
				if not submit(main, {"type":"use_item", "uid":uid}).is_empty(): return false
		if main.session.display_snapshot().phase != "battle": break
		if not submit(main, {"type":"end_turn"}).is_empty(): return false
	return main.session.display_snapshot().phase in ["reward", "event_result"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(ContentLoader.new().load_json(Experiment.CONTENT_PATH).error.is_empty(), "scenario catalog passes normal validator")
	check(not Experiment.load_resolution().is_empty() and not StoryBook.load_entries(Experiment.STORY_PATH).is_empty(), "scenario rules and story validate")
	for variant in ["packed", "stashed", "left"]:
		var main := Experiment.create(root)
		check(main != null and main.session.save_service == null, "isolated scenario: " + variant)
		if main == null: continue
		check(submit(main, {"type":"start"}).is_empty() and win_by_combat(main), "first encounter can be won from initial state")
		var offer: String = main.session.display_snapshot().reward.offer_id
		check(submit(main, {"type":"reward_skip", "offer_id":offer}).is_empty(), "skip reward")
		check(submit(main, {"type":"advance"}).is_empty(), "open evidence")
		var event: Dictionary = main.session.display_snapshot().event
		var uid: String = event.uid
		if variant == "left":
			check(submit(main, {"type":"event_leave", "event_id":event.id}).is_empty(), "leave evidence")
		else:
			check(submit(main, {"type":"event_take", "event_id":event.id}).is_empty(), "take evidence")
			check(main.inventory.items.has(uid) and not main.inventory.is_packed(uid), "evidence starts in stash")
			check(not main.primary.disabled, "can confirm evidence in stash")
			check(submit(main, {"type":"event_confirm", "event_id":event.id}).is_empty(), "confirm without bag space")
		check(submit(main, {"type":"choose_route", "route_id":main.inventory.config.routes[0].id}).is_empty(), "choose path")
		if variant == "packed":
			check(main.session.stash("hat").is_empty() and main.session.place(uid, Vector2i(1,2), 0).is_empty(), "pack evidence before encounter")
		check(submit(main, {"type":"start"}).is_empty(), "start encounter")
		var button: Button = main.layout.get_node("ResolutionButton")
		check(button.visible and button.disabled == (variant != "packed"), "resolution button reflects evidence")
		var before: Dictionary = main.session.state_snapshot()
		if variant == "packed":
			if "--capture" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/arang-encounter-screen.png"))
			button.pressed.emit()
			check(main.session.state_snapshot().phase == "event_result", "button resolves using evidence")
			check(main.session.state_snapshot().phase == "event_result" and main.session.display_snapshot() == before, "resolution commits before playback")
			check(not main.session.submit({"type":"resolve_encounter"}).is_empty(), "double input blocked during playback")
			main.session.skip_playback()
			check(main.session.display_snapshot().event.get("method") == "resolution", "peaceful ending recorded")
			check(main.layout.encounter_event.description.text == Experiment.load_resolution().result, "peaceful ending visible")
		else:
			check(not main.session.submit({"type":"resolve_encounter"}).is_empty() and main.session.state_snapshot() == before, "missing or stashed evidence cannot resolve")
			check(win_by_combat(main), "fight can end encounter from actual state")
			check(main.session.display_snapshot().phase == "event_result" and main.session.display_snapshot().event.get("method", "") != "resolution", "combat ending distinct")
		check(submit(main, {"type":"event_continue", "event_id":event.id}).is_empty() and main.session.display_snapshot().phase == "complete", "ending completes experiment")
		check(not main.session.submit({"type":"event_continue", "event_id":event.id}).is_empty(), "ending cannot repeat")
		main._reset_run()
		check(main.session.display_snapshot().phase == "packing" and not main.session.display_snapshot().config.get("resolutions", []).is_empty(), "restart retains isolated rules")
		main.queue_free()
		await process_frame
	print("ARANG EXPERIMENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
