extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	main.sounds.set_enabled(false)
	var state: Dictionary = main.session.state_snapshot()
	var route: Dictionary = state.config.routes[0]
	state.route = {"choice":route.id, "step":1}
	state.encounter = route.encounters[1]
	state.enemy_health = state.config.encounters[state.encounter].hp
	state.phase = "packing"
	main.session.reset(main.inventory, state)
	var args := OS.get_cmdline_user_args()
	var path := "res://../build/cinematic-intro.png"
	if "--memory" in args:
		state.phase = "event_result"
		state.event = {"id":state.config.events[0].id, "uid":"event/test", "selected":"leave", "status":"resolved", "outcome":"leave", "method":""}
		main.session.reset(main.inventory, state)
		main.session.submit({"type":"event_continue", "event_id":state.event.id})
		main.session.playback.queue._process(0)
		path = "res://../build/cinematic-memory.png"
	elif "--kill" in args:
		state.phase = "battle"
		state.enemy_health = 1
		var result := CombatSimulator.resolve(state, {"type":"use_item", "uid":"sword"})
		var hit: Dictionary = result.events().filter(func(event): return event.kind == "damage" and event.target == "enemy")[0]
		main.session.playback.reset(state)
		main.session.playback.play(CombatResolution.new(state, hit.after, [hit]))
		main.session.playback.queue._process(0)
		main.session.playback.queue._current._impact()
		path = "res://../build/cinematic-ink-hit.png"
	else:
		main.session.submit({"type":"start"})
		main.session.playback.queue._process(0)
	if main.session.playback.queue._current != null and main.session.playback.queue._current._tween != null: main.session.playback.queue._current._tween.pause()
	await process_frame
	if "--kill" in args:
		main.session.playback._update_feedback_progress(0.80)
		await process_frame
		await process_frame
	else: main.cinematics.set_progress(0.86)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if "--kill" in args:
		main.vfx.burst.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/cinematic-ink-without-particles.png"))
	print("CINEMATICS CAPTURE: PASS ", path)
	quit(0)
